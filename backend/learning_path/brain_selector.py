"""
Learning Path 2.0 - Brain Selector (Hardened)
Technical Memo v1.1 - Phase 6.5

Deterministic selector with:
- Stable tie-breaking (variant_index, exercise_id)
- Selection reason tracking
- Content exhaustion flags
- Full analytics support
"""

import sqlite3
import json
import hashlib
import random
import re
from typing import List, Dict, Optional, Set
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from .srs_plan import (
    MasteryVector, get_srs_plan, SKILL_TO_TYPES, FOCUS_TO_SKILL,
    make_slot_key, make_plan_slot_id
)
from .audio_map import resolve_audio_url, load_audio_map
from .image_map import resolve_image_url, load_image_map
from .sense_store import get_primary_gloss, get_sense_payload, get_senses


# ============================================================
# SELECTION REASON ENUM
# ============================================================

class SelectionReason(str, Enum):
    UNSEEN = "UNSEEN"                    # Never seen before
    LRU = "LRU"                          # Least recently used
    RELAX_GROUP = "RELAX_GROUP"          # Group exclusion relaxed
    RELAX_RECENCY = "RELAX_RECENCY"      # Recency window relaxed
    RELAX_DIFFICULTY = "RELAX_DIFFICULTY"  # Difficulty relaxed
    FALLBACK = "FALLBACK"                # Generated on-the-fly from concepts
    EXHAUSTED = "EXHAUSTED"              # All constraints exhausted


@dataclass
class ExclusionApplied:
    """Track which exclusions were applied during selection."""
    recency_days: int = 30
    group_exclusion: bool = True
    mission_exclusion: bool = True
    relaxed_group: bool = False
    relaxed_recency: bool = False


@dataclass
class SelectedExercise:
    """A selected exercise with full metadata and selection analytics."""
    exercise_id: str
    word_id: str
    exercise_type: str
    difficulty: int
    payload: Dict
    skill_focus: str
    stage: int
    review_instance_id: str
    slot_key: str
    plan_slot_id: str
    group_id: Optional[str] = None
    # Analytics fields
    selected_by: SelectionReason = SelectionReason.UNSEEN
    content_exhausted: bool = False
    exhaustion_reason: Optional[str] = None
    exclusion_applied: ExclusionApplied = field(default_factory=ExclusionApplied)


class BrainSelector:
    """Deterministic Brain that selects (not generates) exercises."""
    
    def __init__(self, conn: sqlite3.Connection, mission_seed: Optional[str] = None):
        self.conn = conn
        self.mission_seed = mission_seed or ""
        self.type_rotation: Dict[str, str] = {}
        self.used_groups: Dict[str, Set[str]] = {}
        self.used_exercise_ids: Set[str] = set()
        self.used_sentence_keys: Set[str] = set()
        self._exhaustion_log: List[Dict] = []
        self._audio_map: Optional[Dict[str, str]] = None
        self._image_map: Optional[Dict[str, str]] = None
        self._vocab_conn: Optional[sqlite3.Connection] = None
        self._recent_sentence_cache: Dict[str, Set[str]] = {}

    def _filter_to_existing_concepts(self, word_ids: List[str]) -> List[str]:
        """Keep only ids that exist in concepts table, preserving input order."""
        if not word_ids:
            return []
        placeholders = ",".join("?" for _ in word_ids)
        rows = self.conn.execute(
            f"SELECT id FROM concepts WHERE id IN ({placeholders})",
            word_ids,
        ).fetchall()
        existing = {str(r[0]) for r in rows}
        return [wid for wid in word_ids if wid in existing]

    def _sense_mode_enabled(self, user_id: str, language_code: str) -> bool:
        """Return true when sense mastery tables exist and user has sense rows."""
        try:
            table = self.conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='user_sense_mastery' LIMIT 1"
            ).fetchone()
            if not table:
                return False
            row = self.conn.execute(
                """
                SELECT 1
                FROM user_sense_mastery
                WHERE user_id = ? AND language_code = ?
                LIMIT 1
                """,
                (user_id, language_code),
            ).fetchone()
            return row is not None
        except sqlite3.OperationalError:
            return False

    def _primary_sense_id(self, word_id: str) -> str:
        """Resolve primary sense id for a word with deterministic fallback."""
        try:
            row = self.conn.execute(
                """
                SELECT sense_id
                FROM concept_senses
                WHERE concept_id = ? AND is_primary = 1
                LIMIT 1
                """,
                (word_id,),
            ).fetchone()
            if row and row[0]:
                return str(row[0])
        except sqlite3.OperationalError:
            pass
        return f"{word_id}::s01"
    
    # ============================================================
    # GATING LOGIC (v1.2.2 Architecture)
    # ============================================================
    
    def check_unit_gate(
        self,
        user_id: str,
        language_code: str,
        unit_id: str,
        recognition_min: int = 60,
        production_min: int = 40,
        stage_min: int = 4
    ) -> Dict:
        """
        Check if user can unlock the NEXT unit.
        Returns { unlocked: bool, failing_count: int, failing_concepts: [...] }
        
        A concept PASSES the gate if:
        - mastery_state IN ('MASTERED', 'MASTERED_PENDING_REVIEW') OR srs_stage >= stage_min
        - AND recognition >= recognition_min
        - AND production >= production_min
        """
        row = self.conn.execute("""
            SELECT COUNT(*) as failing_count
            FROM unit_concepts uc
            LEFT JOIN concept_senses cs
              ON cs.concept_id = uc.concept_id AND cs.is_primary = 1
            LEFT JOIN user_sense_mastery sm
              ON sm.sense_id = cs.sense_id
              AND sm.user_id = ? AND sm.language_code = ?
            LEFT JOIN user_word_mastery m 
              ON uc.concept_id = m.word_id 
              AND m.user_id = ? AND m.language_code = ?
            WHERE uc.unit_id = ?
              AND NOT (
                -- Concept passes if mastered OR stage >= threshold
                (COALESCE(sm.mastery_state, m.mastery_state, 'UNKNOWN') IN ('MASTERED', 'MASTERED_PENDING_REVIEW')
                 OR COALESCE(sm.srs_stage, m.srs_stage, 0) >= ?)
                -- AND vector thresholds met
                AND COALESCE(sm.recognition, m.recognition, 0) >= ?
                AND COALESCE(sm.production, m.production, 0) >= ?
              )
        """, [user_id, language_code, user_id, language_code, unit_id, stage_min, recognition_min, production_min]).fetchone()
        
        failing_count = row[0] if row else 0
        
        # Get failing concept IDs for UI
        failing_concepts = []
        if failing_count > 0:
            rows = self.conn.execute("""
                SELECT uc.concept_id, 
                       COALESCE(sm.srs_stage, m.srs_stage, 0) as stage,
                       COALESCE(sm.mastery_state, m.mastery_state, 'UNKNOWN') as state,
                       COALESCE(sm.recognition, m.recognition, 0) as recognition,
                       COALESCE(sm.production, m.production, 0) as production
                FROM unit_concepts uc
                LEFT JOIN concept_senses cs
                  ON cs.concept_id = uc.concept_id AND cs.is_primary = 1
                LEFT JOIN user_sense_mastery sm
                  ON sm.sense_id = cs.sense_id
                  AND sm.user_id = ? AND sm.language_code = ?
                LEFT JOIN user_word_mastery m 
                  ON uc.concept_id = m.word_id 
                  AND m.user_id = ? AND m.language_code = ?
                WHERE uc.unit_id = ?
                  AND NOT (
                    (COALESCE(sm.mastery_state, m.mastery_state, 'UNKNOWN') IN ('MASTERED', 'MASTERED_PENDING_REVIEW')
                     OR COALESCE(sm.srs_stage, m.srs_stage, 0) >= ?)
                    AND COALESCE(sm.recognition, m.recognition, 0) >= ?
                    AND COALESCE(sm.production, m.production, 0) >= ?
                  )
                LIMIT 5
            """, [user_id, language_code, user_id, language_code, unit_id, stage_min, recognition_min, production_min]).fetchall()
            failing_concepts = [
                {"word_id": r[0], "stage": r[1], "state": r[2], "recognition": r[3], "production": r[4]}
                for r in rows
            ]
        
        return {
            "unlocked": failing_count == 0,
            "failing_count": failing_count,
            "failing_concepts": failing_concepts
        }
    
    def get_batch_unit_status(
        self,
        user_id: str,
        language_code: str,
        unit_ids: List[str],
        recognition_min: int = 60,
        production_min: int = 40,
        stage_min: int = 4
    ) -> Dict[str, Dict]:
        """
        Efficiently check lock status for multiple units in one go.
        Returns dict: { unit_id: { unlocked: bool, failing_count: int } }
        """
        if not unit_ids:
            return {}
            
        placeholders = ",".join("?" for _ in unit_ids)
        
        # Query counts of failing concepts per unit
        # Concept FAILS if: NOT (mastered OR stage>=min) OR recognition<min OR production<min
        rows = self.conn.execute(f"""
            SELECT uc.unit_id, COUNT(*) as failing_count
            FROM unit_concepts uc
            LEFT JOIN concept_senses cs
              ON cs.concept_id = uc.concept_id AND cs.is_primary = 1
            LEFT JOIN user_sense_mastery sm
              ON sm.sense_id = cs.sense_id
              AND sm.user_id = ? AND sm.language_code = ?
            LEFT JOIN user_word_mastery m 
              ON uc.concept_id = m.word_id 
              AND m.user_id = ? AND m.language_code = ?
            WHERE uc.unit_id IN ({placeholders})
              AND NOT (
                (COALESCE(sm.mastery_state, m.mastery_state, 'UNKNOWN') IN ('MASTERED', 'MASTERED_PENDING_REVIEW')
                 OR COALESCE(sm.srs_stage, m.srs_stage, 0) >= ?)
                AND COALESCE(sm.recognition, m.recognition, 0) >= ?
                AND COALESCE(sm.production, m.production, 0) >= ?
              )
            GROUP BY uc.unit_id
        """, [user_id, language_code, user_id, language_code, *unit_ids, stage_min, recognition_min, production_min]).fetchall()
        
        failing_map = {row[0]: row[1] for row in rows}
        
        results = {}
        for uid in unit_ids:
            fc = failing_map.get(str(uid), 0)
            results[uid] = {
                "unlocked": fc == 0,
                "failing_count": fc
            }
            
        return results
    
    # ============================================================
    # INTENT-BASED CANDIDATE SOURCING (v1.2.2 Architecture)
    # ============================================================
    
    def get_candidates_for_intent(
        self,
        user_id: str,
        language_code: str,
        intent: str,  # 'DAILY', 'LEARN', 'REVIEW', 'DRILL'
        forced_ids: Optional[List[str]] = None,
        unit_id: Optional[str] = None,
        focus_dimension: Optional[str] = None,
        mastery_ceiling: int = 80,
        max_new: int = 3,
        max_review: int = 7
    ) -> List[Dict]:
        """
        Get candidate words based on intent policy.
        Returns list of { word_id, reason, srs_stage, ... }
        """
        candidates = []
        seen_word_ids = set()
        valid_forced_ids = self._filter_to_existing_concepts(
            [str(w) for w in (forced_ids or [])]
        )
        sense_mode = self._sense_mode_enabled(user_id, language_code)
        
        # Helper for unit filtering
        unit_filter_clause = ""
        unit_params = []
        if unit_id:
            unit_filter_clause = "AND uwm.word_id IN (SELECT concept_id FROM unit_concepts WHERE unit_id = ?)"
            unit_params = [unit_id]

        if intent == "LEARN" and valid_forced_ids:
            # [P0 FIX] Filter forced_ids to prioritize UNMASTERED words.
            # Otherwise we just keep practicing the first 3 words of the unit forever.
            if len(valid_forced_ids) > 0:
                placeholders = ",".join(["?"] * len(valid_forced_ids))
                # Check for mastery or high stage (>=5)
                q = f"""
                    SELECT word_id FROM user_word_mastery 
                    WHERE user_id = ? AND language_code = ? 
                    AND word_id IN ({placeholders})
                    AND (mastery_state = 'MASTERED' OR srs_stage >= 5)
                """
                # forced_ids are strings, make sure params match
                params = [user_id, language_code] + list(valid_forced_ids)
                rows = self.conn.execute(q, params).fetchall()
                mastered_set = {str(row['word_id']) for row in rows}
                
                # Filter: Keep order, remove mastered
                unmastered = [wid for wid in valid_forced_ids if wid not in mastered_set]
                
                # If we have unmastered words, use them. Else fall back to review.
                target_ids = unmastered if unmastered else valid_forced_ids
            else:
                target_ids = []

            # Take top N
            for wid in target_ids[:max_new]:
                if wid not in seen_word_ids:
                    row = {"word_id": wid, "reason": "forced_from_manifest"}
                    if sense_mode:
                        row["sense_id"] = self._primary_sense_id(wid)
                    candidates.append(row)
                    seen_word_ids.add(wid)
            
            # If we didn't fill the slot with unmastered, maybe fill with reviews?
            # The original logic just appended due reviews below. That is fine.
            # Also include due reviews (excluding what we already picked)
            # Fetch extra to be safe, or let SQL handle exclusion
            due = self._get_due_reviews(
                user_id,
                language_code,
                max_review,
                exclude_ids=list(seen_word_ids),
                primary_only=sense_mode,
            )
            for d in due:
                candidates.append(d)
                seen_word_ids.add(d['word_id'])
        
        elif intent == "DRILL":
            # Skill Mode: Query weak items (no new words)
            dim_col = focus_dimension if focus_dimension in ['recognition', 'listening', 'production', 'usage'] else 'recognition'
            if sense_mode:
                rows = self.conn.execute(
                    f"""
                    SELECT usm.word_id, usm.sense_id, usm.{dim_col} as dim_value, usm.srs_stage
                    FROM user_sense_mastery usm
                    JOIN concept_senses cs
                      ON cs.sense_id = usm.sense_id
                     AND cs.concept_id = usm.word_id
                     AND cs.is_primary = 1
                    WHERE usm.user_id = ? AND usm.language_code = ?
                      AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = usm.word_id)
                      AND COALESCE(usm.{dim_col}, 0) < ?
                      {"AND usm.word_id IN (SELECT concept_id FROM unit_concepts WHERE unit_id = ?)" if unit_id else ""}
                    ORDER BY usm.{dim_col} ASC, usm.next_review_at ASC, usm.word_id ASC, usm.sense_id ASC
                    LIMIT ?
                    """,
                    [user_id, language_code, mastery_ceiling, *([unit_id] if unit_id else []), max_review * 6],
                ).fetchall()
                seen_words = set()
                for r in rows:
                    wid = str(r[0])
                    if wid in seen_words:
                        continue
                    seen_words.add(wid)
                    candidates.append(
                        {
                            "word_id": wid,
                            "sense_id": str(r[1]),
                            "dim_value": r[2],
                            "srs_stage": r[3],
                            "reason": f"weak_{focus_dimension}",
                        }
                    )
                    if len(candidates) >= max_review:
                        break
            else:
                rows = self.conn.execute(f"""
                    SELECT uwm.word_id, uwm.{dim_col} as dim_value, uwm.srs_stage
                    FROM user_word_mastery uwm
                    WHERE uwm.user_id = ? AND uwm.language_code = ?
                      AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = uwm.word_id)
                      AND COALESCE({dim_col}, 0) < ?
                      {unit_filter_clause}
                    ORDER BY {dim_col} ASC, uwm.word_id ASC
                    LIMIT ?
                """, [user_id, language_code, mastery_ceiling, *unit_params, max_review]).fetchall()
                candidates = [
                    {"word_id": str(r[0]), "dim_value": r[1], "srs_stage": r[2], "reason": f"weak_{focus_dimension}"}
                    for r in rows
                ]
        
        elif intent == "REVIEW":
            # Review only
            candidates = self._get_due_reviews(
                user_id,
                language_code,
                max_review,
                unit_id=unit_id,
                primary_only=sense_mode,
            )
        
        else:  # DAILY (default)
            # 1. Due reviews first
            due = self._get_due_reviews(
                user_id,
                language_code,
                max_review,
                unit_id=unit_id,
                primary_only=sense_mode,
            )
            for d in due:
                candidates.append(d)
                seen_word_ids.add(d['word_id'])
                
            # 2. New words if room
            if len(candidates) < max_new + max_review and valid_forced_ids:
                remaining = max_new
                for wid in valid_forced_ids: # Iterate all, break when enough
                    if remaining <= 0: break
                    if wid not in seen_word_ids:
                        row = {"word_id": wid, "reason": "new_from_manifest"}
                        if sense_mode:
                            row["sense_id"] = self._primary_sense_id(wid)
                        candidates.append(row)
                        seen_word_ids.add(wid)
                        remaining -= 1
        
        return candidates
    
    def _get_due_reviews(
        self,
        user_id: str,
        language_code: str,
        limit: int,
        exclude_ids: Optional[List[str]] = None,
        unit_id: Optional[str] = None,
        primary_only: bool = False,
    ) -> List[Dict]:
        """Get words due for review (SRS)."""
        sense_mode = self._sense_mode_enabled(user_id, language_code)
        params = [user_id, language_code]
        exclude_clause = ""
        if exclude_ids:
            placeholders = ",".join("?" for _ in exclude_ids)
            exclude_clause = f"AND {{alias}}.word_id NOT IN ({placeholders})"
            params.extend(exclude_ids)
        
        unit_filter_clause = ""
        if unit_id:
            unit_filter_clause = "AND {alias}.word_id IN (SELECT concept_id FROM unit_concepts WHERE unit_id = ?)"
            params.append(unit_id)

        fetch_limit = max(limit * 8, limit + 20)
        params_with_limit = [*params, fetch_limit]

        if sense_mode:
            primary_join = ""
            if primary_only:
                primary_join = """
                JOIN concept_senses cs
                  ON cs.sense_id = usm.sense_id
                 AND cs.concept_id = usm.word_id
                 AND cs.is_primary = 1
                """
            sql = f"""
                SELECT usm.word_id, usm.sense_id, usm.srs_stage, usm.next_review_at
                FROM user_sense_mastery usm
                {primary_join}
                WHERE usm.user_id = ? AND usm.language_code = ?
                  AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = usm.word_id)
                  AND usm.next_review_at <= datetime('now')
                  {exclude_clause.format(alias='usm')}
                  {unit_filter_clause.format(alias='usm')}
                ORDER BY usm.next_review_at ASC, usm.word_id ASC, usm.sense_id ASC
                LIMIT ?
            """
            rows = self.conn.execute(sql, params_with_limit).fetchall()
            out: List[Dict] = []
            seen_words = set()
            for r in rows:
                wid = str(r[0])
                if wid in seen_words:
                    continue
                seen_words.add(wid)
                out.append(
                    {
                        "word_id": wid,
                        "sense_id": str(r[1]),
                        "srs_stage": r[2],
                        "next_review_at": r[3],
                        "reason": "srs_due",
                    }
                )
                if len(out) >= limit:
                    break
            return out

        sql = f"""
            SELECT uwm.word_id, uwm.srs_stage, uwm.next_review_at
            FROM user_word_mastery uwm
            WHERE uwm.user_id = ? AND uwm.language_code = ?
              AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = uwm.word_id)
              AND uwm.next_review_at <= datetime('now')
              {exclude_clause.format(alias='uwm')}
              {unit_filter_clause.format(alias='uwm')}
            ORDER BY uwm.next_review_at ASC, uwm.word_id ASC
            LIMIT ?
        """
        rows = self.conn.execute(sql, params_with_limit).fetchall()
        return [
            {"word_id": str(r[0]), "srs_stage": r[1], "next_review_at": r[2], "reason": "srs_due"}
            for r in rows[:limit]
        ]
    
    def _stable_hash(self, *args) -> int:
        """Generate stable hash for deterministic tie-breaking."""
        combined = ":".join(str(a) for a in args) + self.mission_seed
        return int(hashlib.md5(combined.encode()).hexdigest()[:8], 16)

    def _normalize_sentence_text(self, text: str) -> str:
        normalized = text.strip().lower()
        normalized = re.sub(r"[\s\.\,\!\?\u3002\uff01\uff1f\uff0c;:]+", "", normalized)
        return normalized

    def _merge_punctuation_segments(self, segments: List[str]) -> List[str]:
        """
        Merge punctuation-only chunks into the previous chunk so sentence builder
        doesn't render dots/commas as standalone draggable tiles.
        """
        merged: List[str] = []
        punct_re = re.compile(
            r"^[\.\,\!\?\;\:\u3002\uff01\uff1f\uff0c\u3001\u2026\u2014\u2013"
            r"\u300c\u300d\u300e\u300f\u201c\u201d\u2018\u2019"
            r"\(\)\[\]\{\}\uff08\uff09\u300a\u300b<>]+$"
        )
        for item in segments:
            token = str(item).strip()
            if not token:
                continue
            if punct_re.match(token) and merged:
                merged[-1] = f"{merged[-1]}{token}"
            else:
                merged.append(token)
        return merged

    def _extract_sentence_keys(self, payload: Dict) -> Set[str]:
        keys: Set[str] = set()
        if not isinstance(payload, dict):
            return keys

        candidates: List[str] = []
        for field in ("sentence", "context_sentence", "text"):
            value = payload.get(field)
            if isinstance(value, str) and value.strip():
                candidates.append(value)

        reading = payload.get("reading")
        if isinstance(reading, dict):
            story = reading.get("story_zh") or reading.get("text")
            if isinstance(story, str) and story.strip():
                candidates.append(story)

        for text in candidates:
            normalized = self._normalize_sentence_text(text)
            if not normalized:
                continue
            digest = hashlib.md5(normalized.encode("utf-8")).hexdigest()[:12]
            keys.add(f"s:{digest}")
        return keys

    def _recent_sentence_keys(
        self,
        user_id: str,
        language_code: str,
        exclude_days: int,
    ) -> Set[str]:
        cache_key = f"{user_id}:{language_code}:{exclude_days}"
        if cache_key in self._recent_sentence_cache:
            return self._recent_sentence_cache[cache_key]

        rows = self.conn.execute("""
            SELECT e.payload
            FROM user_exercise_history h
            JOIN word_exercises e ON h.exercise_id = e.id
            WHERE h.user_id = ? AND h.language_code = ?
              AND h.last_seen_at > datetime('now', '-' || ? || ' days')
            ORDER BY h.last_seen_at DESC
            LIMIT 600
        """, [user_id, language_code, exclude_days]).fetchall()

        keys: Set[str] = set()
        for row in rows:
            try:
                payload = json.loads(row[0]) if row[0] else {}
            except Exception:
                payload = {}
            keys.update(self._extract_sentence_keys(payload))
        self._recent_sentence_cache[cache_key] = keys
        return keys
    
    def select_variant(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        exercise_type: str,
        max_difficulty: int,
        mission_id: str,
        exclude_days: int = 30,
        preferred_sense_id: Optional[str] = None,
    ) -> Optional[Dict]:
        """
        Select exercise variant with full exclusion + fallback chain.
        
        Priority:
        1. Unseen variants (excluding groups in mission + recency window)
        2. LRU variants (excluding groups)
        3. Relax group exclusion
        4. Relax recency window
        5. Any variant (exhausted)
        """
        exclusion = ExclusionApplied(recency_days=exclude_days)
        group_key = f"{word_id}:{exercise_type}"
        
        # Get groups used in this mission
        mission_groups = self.used_groups.get(group_key, set())
        
        # Get groups seen recently
        recent_groups = self._get_recent_groups(
            user_id, language_code, word_id, exercise_type,
            mission_id, exclude_days
        )
        recent_exercise_ids = self._get_recent_exercise_ids(
            user_id, language_code, word_id, exercise_type, mission_id, exclude_days
        )
        excluded_exercise_ids = self.used_exercise_ids | recent_exercise_ids
        
        all_excluded = mission_groups | recent_groups
        
        def _query_with_relaxation(strict_sense_only: bool) -> Optional[Dict]:
            # Try 1: Full exclusions
            variant_local = self._query_variant_deterministic(
                user_id,
                language_code,
                word_id,
                exercise_type,
                max_difficulty,
                all_excluded,
                excluded_exercise_ids,
                exclude_days,
                preferred_sense_id=preferred_sense_id,
                strict_sense_only=strict_sense_only,
            )
            if variant_local:
                reason_local = SelectionReason.UNSEEN if variant_local.get('is_unseen') else SelectionReason.LRU
                return self._finalize_selection(variant_local, reason_local, exclusion, group_key)

            # Try 2: Relax group exclusion (allow recent groups)
            variant_local = self._query_variant_deterministic(
                user_id,
                language_code,
                word_id,
                exercise_type,
                max_difficulty,
                mission_groups,
                excluded_exercise_ids,
                exclude_days,
                preferred_sense_id=preferred_sense_id,
                strict_sense_only=strict_sense_only,
            )
            if variant_local:
                exclusion.relaxed_group = True
                return self._finalize_selection(variant_local, SelectionReason.RELAX_GROUP, exclusion, group_key)

            # Try 3: Relax all exclusions
            variant_local = self._query_variant_deterministic(
                user_id,
                language_code,
                word_id,
                exercise_type,
                max_difficulty,
                set(),
                excluded_exercise_ids,
                exclude_days,
                preferred_sense_id=preferred_sense_id,
                strict_sense_only=strict_sense_only,
            )
            if variant_local:
                exclusion.relaxed_group = True
                exclusion.relaxed_recency = True
                return self._finalize_selection(
                    variant_local,
                    SelectionReason.EXHAUSTED,
                    exclusion,
                    group_key,
                    exhausted=True,
                    reason_text="all_groups_excluded",
                )
            return None

        # Sense-strict pass first when a preferred sense exists.
        if preferred_sense_id:
            strict_variant = _query_with_relaxation(strict_sense_only=True)
            if strict_variant:
                return strict_variant

        # Fallback pass (sense-agnostic) only if strict pass failed.
        variant = _query_with_relaxation(strict_sense_only=False)
        if variant:
            return variant
        
        # No variants at all
        if preferred_sense_id:
            self._log_exhaustion(word_id, exercise_type, "no_variants_for_preferred_sense")
        else:
            self._log_exhaustion(word_id, exercise_type, "no_variants_exist")
        return None
    
    def _finalize_selection(
        self,
        variant: Dict,
        reason: SelectionReason,
        exclusion: ExclusionApplied,
        group_key: str,
        exhausted: bool = False,
        reason_text: Optional[str] = None
    ) -> Dict:
        """Finalize variant selection and track state."""
        variant['selected_by'] = reason
        variant['content_exhausted'] = exhausted
        variant['exhaustion_reason'] = reason_text
        variant['exclusion_applied'] = exclusion
        
        # Track group usage
        if variant.get('group_id'):
            if group_key not in self.used_groups:
                self.used_groups[group_key] = set()
            self.used_groups[group_key].add(variant['group_id'])
        if variant.get('id'):
            self.used_exercise_ids.add(variant['id'])
        self.used_sentence_keys.update(
            self._extract_sentence_keys(variant.get('payload', {}))
        )
        
        if exhausted:
            self._log_exhaustion(variant['word_id'], variant['exercise_type'], reason_text)
        
        return variant
    
    def _get_recent_groups(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        exercise_type: str,
        mission_id: str,
        exclude_days: int
    ) -> Set[str]:
        """Get group_ids seen in current mission or recently."""
        rows = self.conn.execute("""
            SELECT DISTINCT e.group_id 
            FROM user_exercise_history h
            JOIN word_exercises e ON h.exercise_id = e.id
            WHERE h.user_id = ? AND h.language_code = ?
              AND e.word_id = ? AND e.exercise_type = ?
              AND (h.mission_id = ? 
                   OR h.last_seen_at > datetime('now', '-' || ? || ' days'))
              AND e.group_id IS NOT NULL
        """, [user_id, language_code, word_id, exercise_type,
              mission_id, exclude_days]).fetchall()
        
        return {r[0] for r in rows}

    def _get_recent_exercise_ids(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        exercise_type: str,
        mission_id: str,
        exclude_days: int,
    ) -> Set[str]:
        rows = self.conn.execute("""
            SELECT DISTINCT h.exercise_id
            FROM user_exercise_history h
            JOIN word_exercises e ON h.exercise_id = e.id
            WHERE h.user_id = ? AND h.language_code = ?
              AND e.word_id = ? AND e.exercise_type = ?
              AND (
                h.mission_id = ?
                OR h.last_seen_at > datetime('now', '-' || ? || ' days')
              )
            LIMIT 300
        """, [user_id, language_code, word_id, exercise_type, mission_id, exclude_days]).fetchall()
        ids = {r[0] for r in rows if r[0]}

        # Fallback exercise ids are not present in word_exercises. Exclude them too.
        auto_prefix = {
            "order_sentence": "auto_usage_",
            "meaning_select": "auto_recog_",
            "audio_select": "auto_listen_",
            "character_select": "auto_prod_",
        }.get(exercise_type)
        auto_pattern = f"{auto_prefix}{word_id}" if auto_prefix else "__no_match__"
        fallback_pattern = f"fallback_{word_id}_*"
        fallback_rows = self.conn.execute("""
            SELECT DISTINCT exercise_id
            FROM user_exercise_history
            WHERE user_id = ? AND language_code = ?
              AND (
                mission_id = ?
                OR last_seen_at > datetime('now', '-' || ? || ' days')
              )
              AND (
                exercise_id GLOB ?
                OR exercise_id GLOB ?
              )
            LIMIT 100
        """, [
            user_id,
            language_code,
            mission_id,
            exclude_days,
            auto_pattern,
            fallback_pattern,
        ]).fetchall()
        ids.update(r[0] for r in fallback_rows if r[0])

        return ids
    
    def _query_variant_deterministic(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        exercise_type: str,
        max_difficulty: int,
        excluded_groups: Set[str],
        excluded_exercise_ids: Set[str],
        exclude_days: int,
        preferred_sense_id: Optional[str] = None,
        strict_sense_only: bool = False,
    ) -> Optional[Dict]:
        """
        Query variant with DETERMINISTIC tie-breaking.
        
        Order by:
        1. Unseen first (h.last_seen_at IS NULL)
        2. Oldest seen (h.last_seen_at ASC)
        3. Stable: variant_index ASC, exercise_id ASC
        """
        clauses = []
        params = [user_id, language_code, word_id, exercise_type, max_difficulty]
        if excluded_groups:
            placeholders = ','.join('?' * len(excluded_groups))
            clauses.append(f"(e.group_id IS NULL OR e.group_id NOT IN ({placeholders}))")
            params.extend(list(excluded_groups))
        if excluded_exercise_ids:
            placeholders = ','.join('?' * len(excluded_exercise_ids))
            clauses.append(f"e.id NOT IN ({placeholders})")
            params.extend(list(excluded_exercise_ids))

        extra_clause = ""
        if clauses:
            extra_clause = " AND " + " AND ".join(clauses)

        rows = self.conn.execute(f"""
            SELECT 
                e.id, e.word_id, e.exercise_type, e.difficulty,
                e.payload, e.group_id, e.tags, e.variant_index,
                CASE WHEN h.last_seen_at IS NULL THEN 1 ELSE 0 END as is_unseen,
                h.last_seen_at
            FROM word_exercises e
            LEFT JOIN user_exercise_history h 
                ON e.id = h.exercise_id 
                AND h.user_id = ? AND h.language_code = ?
            WHERE e.word_id = ? 
              AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = e.word_id)
              AND e.exercise_type = ?
              AND e.difficulty <= ?
              {extra_clause}
            ORDER BY 
                is_unseen DESC,
                h.last_seen_at ASC,
                e.variant_index ASC,
                e.id ASC
            LIMIT 30
        """, params).fetchall()

        recent_sentence_keys = self._recent_sentence_keys(user_id, language_code, exclude_days)
        preferred_candidates: List[Dict] = []
        non_preferred_candidates: List[Dict] = []
        for row in rows:
            try:
                payload = json.loads(row[4]) if row[4] else {}
            except Exception:
                payload = {}
            payload_sense_id = self._extract_payload_sense_id(payload, word_id)
            if preferred_sense_id:
                is_match = payload_sense_id == preferred_sense_id
                if strict_sense_only and not is_match:
                    continue
            sentence_keys = self._extract_sentence_keys(payload)
            if sentence_keys and (
                (sentence_keys & self.used_sentence_keys)
                or (sentence_keys & recent_sentence_keys)
            ):
                continue
            candidate = {
                'id': row[0],
                'word_id': row[1],
                'exercise_type': row[2],
                'difficulty': row[3],
                'payload': payload,
                'group_id': row[5],
                'tags': row[6],
                'variant_index': row[7],
                'is_unseen': bool(row[8]),
            }
            if preferred_sense_id and payload_sense_id == preferred_sense_id:
                preferred_candidates.append(candidate)
            else:
                non_preferred_candidates.append(candidate)

        if preferred_candidates:
            return preferred_candidates[0]
        if strict_sense_only:
            return None
        if non_preferred_candidates:
            return non_preferred_candidates[0]
        return None

    def _extract_payload_sense_id(self, payload: Dict, word_id: str) -> Optional[str]:
        if not isinstance(payload, dict):
            return None
        sense_obj = payload.get("sense")
        if not isinstance(sense_obj, dict):
            return None
        sense_id = sense_obj.get("sense_id")
        if isinstance(sense_id, str) and sense_id.startswith(f"{word_id}::"):
            return sense_id
        return None
    
    def _log_exhaustion(self, word_id: str, exercise_type: str, reason: str):
        """Log content exhaustion for analytics."""
        self._exhaustion_log.append({
            'word_id': word_id,
            'exercise_type': exercise_type,
            'reason': reason,
        })
    
    def get_exhaustion_log(self) -> List[Dict]:
        """Return accumulated exhaustion events."""
        return self._exhaustion_log.copy()
    
    def get_exercise_type_for_skill(self, skill: str) -> str:
        """Rotate exercise types within a skill."""
        types = SKILL_TO_TYPES.get(skill, ['flashcard'])
        
        last_type = self.type_rotation.get(skill)
        if last_type and last_type in types:
            idx = (types.index(last_type) + 1) % len(types)
            selected = types[idx]
        else:
            selected = types[0]
        
        self.type_rotation[skill] = selected
        return selected
    
    def _generate_distractors(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        correct_answer: str,
        exercise_type: str,
        needed: int = 3
    ) -> List[str]:
        """
        Generate contextual distractors deterministically.
        Resolves integer/string IDs to actual word text via word_exercises lookup.
        """
        # 1. Get Unit Siblings (Same Context) - ORDER BY for Determinism
        unit_rows = self.conn.execute("""
            SELECT uc2.concept_id 
            FROM unit_concepts uc1
            JOIN unit_concepts uc2 ON uc1.unit_id = uc2.unit_id
            WHERE uc1.concept_id = ? AND uc2.concept_id != ?
            ORDER BY uc2.concept_id ASC
        """, [word_id, word_id]).fetchall()
        sibling_ids = [str(r[0]) for r in unit_rows]
        
        # 2. Get Seen Words (fallback) - ORDER BY for Determinism
        seen_ids = []
        if len(sibling_ids) < needed * 3:
            seen_rows = self.conn.execute("""
                SELECT word_id FROM user_word_mastery
                WHERE user_id = ? AND language_code = ? AND word_id != ?
                AND srs_stage >= 1
                ORDER BY word_id ASC
                LIMIT 30
            """, [user_id, language_code, word_id]).fetchall()
            seen_ids = [str(r[0]) for r in seen_rows]
        
        pool_ids = sorted(list(set(sibling_ids + seen_ids)))
        
        # 3. Deterministic Shuffle (Hash-based sort)
        # We shuffle IDs first to pick random candidates
        seed_val = self._stable_hash(word_id, exercise_type, "distractors_selection")
        pool_ids.sort(key=lambda x: self._stable_hash(seed_val, x))
        
        # 4. Resolve IDs to Text (Canonical Source)
        # We map these IDs to text (e.g. "36" -> "好") via the concepts table.
        candidates_to_resolve = pool_ids[:needed * 2] # Fetch extra in case of resolution failure
        
        resolved_texts = []
        if candidates_to_resolve:
            placeholders = ",".join("?" for _ in candidates_to_resolve)
            rows = self.conn.execute(f"""
                SELECT id, text 
                FROM concepts 
                WHERE id IN ({placeholders}) 
            """, candidates_to_resolve).fetchall()
            
            text_map = {str(r[0]): r[1] for r in rows}
            
            # Collect resolved texts in deterministic order of pool_ids
            for pid in pool_ids:
                if pid in text_map:
                    txt = text_map[pid]
                    if txt != correct_answer and txt not in resolved_texts:
                        resolved_texts.append(txt)
                        if len(resolved_texts) >= needed:
                            break
        
        # 5. Last Resort Fallback (Deterministic)
        # Only reached if concepts table is missing data (should be 0 skipped)
        if len(resolved_texts) < needed:
            # We do NOT return nonsense. We return fewer options if we must.
            # But the requirement says "never inject random unrelated tokens".
            # The previous "什么" fallback was deemed nonsense.
            # We will just return what we have. Frontend should handle < 3 distractors.
            pass
                        
        return resolved_texts[:needed]

    def _tone_from_pinyin(self, pinyin: str) -> Optional[int]:
        """Extract the first tone number from pinyin with tone marks or numbers."""
        if not pinyin:
            return None
        tone_map = {
            "ā": 1, "á": 2, "ǎ": 3, "à": 4,
            "ē": 1, "é": 2, "ě": 3, "è": 4,
            "ī": 1, "í": 2, "ǐ": 3, "ì": 4,
            "ō": 1, "ó": 2, "ǒ": 3, "ò": 4,
            "ū": 1, "ú": 2, "ǔ": 3, "ù": 4,
            "ǖ": 1, "ǘ": 2, "ǚ": 3, "ǜ": 4,
        }
        parts = pinyin.strip().split()
        for part in parts:
            if part and part[-1].isdigit():
                tone = int(part[-1])
                if 1 <= tone <= 5:
                    return tone
            for ch in part:
                if ch in tone_map:
                    return tone_map[ch]
        return None

    def _get_vocab_pinyin(self, word_id: str) -> Optional[str]:
        """Fetch pronunciation from vocabulary_v2.db if available."""
        if self._vocab_conn is None:
            vocab_path = Path(__file__).parent.parent / "vocabulary_v2.db"
            if not vocab_path.exists():
                return None
            self._vocab_conn = sqlite3.connect(str(vocab_path))
            self._vocab_conn.row_factory = sqlite3.Row
        row = self._vocab_conn.execute(
            "SELECT pronunciation FROM concepts WHERE id = ?",
            (word_id,)
        ).fetchone()
        if row and row[0]:
            return row[0]
        return None

    def _ensure_tone_select_payload(self, word_id: str, payload: Dict) -> Optional[Dict]:
        """Validate/repair tone_select payload using concepts table."""
        pinyin = payload.get("pinyin")
        correct = payload.get("correct_tone")
        tone = self._tone_from_pinyin(pinyin) if pinyin else None

        if tone is None and isinstance(correct, int) and pinyin:
            parts = pinyin.strip().split()
            if parts:
                parts[0] = f"{parts[0]}{correct}"
                pinyin = " ".join(parts)
                payload["pinyin"] = pinyin
                tone = self._tone_from_pinyin(pinyin)

        if tone is not None and isinstance(correct, int) and correct == tone:
            return payload

        concept_row = self.conn.execute(
            "SELECT text, pinyin FROM concepts WHERE id = ?",
            (word_id,)
        ).fetchone()
        if not concept_row:
            return None

        new_pinyin = concept_row[1]
        if not new_pinyin or self._tone_from_pinyin(new_pinyin) is None:
            vocab_pinyin = self._get_vocab_pinyin(word_id)
            if vocab_pinyin:
                new_pinyin = vocab_pinyin
        new_tone = self._tone_from_pinyin(new_pinyin) if new_pinyin else None
        if new_tone is None:
            return None

        repaired = dict(payload) if payload else {}
        repaired["word"] = concept_row[0]
        repaired["pinyin"] = new_pinyin
        repaired["correct_tone"] = new_tone
        return repaired

    def _apply_audio_mapping(self, word_id: str, exercise_type: str, payload: Dict) -> Dict:
        """Attach audio URL mapping only for audio-relevant exercise types."""
        audio_types = {'audio_select', 'audio_match', 'dictation_select', 'tone_select', 'flashcard'}
        if exercise_type not in audio_types:
            return payload
        if self._audio_map is None:
            self._audio_map = load_audio_map()
        audio_url = payload.get("audio") or payload.get("audio_url")
        if not audio_url or str(audio_url).startswith("/content/audio/"):
            resolved = resolve_audio_url(word_id, self._audio_map)
            payload["audio"] = resolved
            payload["audio_url"] = resolved
        elif "audio_url" not in payload and audio_url:
            payload["audio_url"] = audio_url
        return payload

    def _apply_image_mapping(self, word_id: str, exercise_type: str, payload: Dict) -> Dict:
        """
        Attach image_url mapping only for image-first exercise types.
        This prevents every exercise from becoming image-heavy.
        """
        image_types = {'flashcard'}
        if exercise_type not in image_types:
            payload.pop("image_url", None)
            return payload
        if self._image_map is None:
            self._image_map = load_image_map()
        image_url = payload.get("image_url")
        if not image_url or str(image_url).startswith("/static/images/"):
            resolved = resolve_image_url(word_id, self._image_map)
            payload["image_url"] = resolved
        return payload

    def _apply_sense_metadata(self, word_id: str, payload: Dict, preferred_sense_id: Optional[str] = None) -> Dict:
        """Attach/normalize canonical sense metadata for UI + submit tracking."""
        existing_sense = payload.get("sense") if isinstance(payload.get("sense"), dict) else None
        payload_sense_id = None
        if existing_sense and isinstance(existing_sense.get("sense_id"), str):
            sid = str(existing_sense["sense_id"])
            if sid.startswith(f"{word_id}::"):
                payload_sense_id = sid

        fallback = None
        prompt = payload.get("prompt")
        if isinstance(prompt, dict):
            fallback = prompt.get("meaning")
        if not fallback:
            fallback = payload.get("back") or payload.get("meaning")
        hint = None
        if existing_sense and isinstance(existing_sense.get("primary_gloss"), str):
            hint = existing_sense.get("primary_gloss")
        if not hint:
            hint = fallback

        senses = get_senses(self.conn, word_id, fallback=fallback)
        if not senses:
            return payload

        selected = senses[0]
        if payload_sense_id:
            match = next((s for s in senses if str(s.get("sense_id")) == payload_sense_id), None)
            if match:
                selected = match
        elif preferred_sense_id:
            match = next((s for s in senses if str(s.get("sense_id")) == preferred_sense_id), None)
            if match:
                selected = match
        elif isinstance(hint, str) and hint.strip():
            normalized_hint = re.sub(r"\s+", " ", hint.strip().lower())

            def norm_gloss(text: str) -> str:
                cleaned = re.sub(r"\s+", " ", text.strip().lower())
                return cleaned[3:] if cleaned.startswith("to ") else cleaned

            exact_match = next(
                (s for s in senses if norm_gloss(str(s.get("gloss", ""))) == norm_gloss(normalized_hint)),
                None,
            )
            if exact_match:
                selected = exact_match
            else:
                token_match = next(
                    (
                        s
                        for s in senses
                        if norm_gloss(str(s.get("gloss", ""))) in norm_gloss(normalized_hint)
                        or norm_gloss(normalized_hint) in norm_gloss(str(s.get("gloss", "")))
                    ),
                    None,
                )
                if token_match:
                    selected = token_match

        alternatives = [
            str(s.get("gloss", "")).strip()
            for s in senses
            if str(s.get("sense_id")) != str(selected.get("sense_id")) and str(s.get("gloss", "")).strip()
        ]
        payload["sense"] = {
            "sense_id": str(selected.get("sense_id")),
            "primary_gloss": str(selected.get("gloss", "")).strip(),
            "alternatives": alternatives,
        }
        return payload

    def select_exercises_for_word(
        self,
        user_id: str,
        language_code: str,
        word_id: str,
        stage: int,
        vector: MasteryVector,
        review_instance_id: str,
        mission_id: str,
        remaining_slots: Optional[List[str]] = None,
        preferred_sense_id: Optional[str] = None,
    ) -> List[SelectedExercise]:
        """Select exercises for all slots of a word."""
        exercises = []
        plan = get_srs_plan(stage, vector)
        
        for focus, difficulty in plan:
            slot_key = make_slot_key(focus, difficulty)
            
            # Skip already-passed slots
            if remaining_slots is not None and slot_key not in remaining_slots:
                continue
            
            ex_type = self.get_exercise_type_for_skill(focus)
            
            variant = self.select_variant(
                user_id, language_code, word_id,
                ex_type, difficulty, mission_id, preferred_sense_id=preferred_sense_id
            )
            
            # [FALLBACK GENERATION]
            # Smart auto-generation from Concepts and Sentences
            if not variant:
                concept_row = self.conn.execute(
                    "SELECT text, pinyin, meaning FROM concepts WHERE id = ?", 
                    (word_id,)
                ).fetchone()
                
                if concept_row:
                    hanzi, pinyin, meaning = concept_row[0], concept_row[1], concept_row[2]
                    primary_gloss = get_primary_gloss(self.conn, word_id, fallback=meaning)
                    sense_payload = get_sense_payload(self.conn, word_id, fallback=meaning)
                    
                    # 1. Try Usage (Sentence Order)
                    if focus == 'usage':
                        sent_rows = self.conn.execute("""
                            SELECT s.text, s.translation, s.pinyin, s.segmentation 
                            FROM sentences s
                            JOIN word_sentences ws ON s.id = ws.sentence_id
                            WHERE ws.word_id = ? AND ws.is_primary = 1
                            ORDER BY ws.is_primary DESC, ws.sentence_id ASC
                            LIMIT 8
                        """, (word_id,)).fetchall()

                        recent_sentence_keys = self._recent_sentence_keys(
                            user_id, language_code, 30
                        )
                        for sent_row in sent_rows:
                            if not sent_row[3]:
                                continue
                            try:
                                segs = json.loads(sent_row[3])
                            except Exception:
                                continue
                            payload = {
                                "sentence": sent_row[0],
                                "pinyin": sent_row[2],
                                "translation": sent_row[1],
                                "segments": segs,
                                "instruction_en": "Arrange the sentence",
                            }
                            sentence_keys = self._extract_sentence_keys(payload)
                            if sentence_keys and (
                                (sentence_keys & self.used_sentence_keys)
                                or (sentence_keys & recent_sentence_keys)
                            ):
                                continue
                            variant = {
                                'id': f"auto_usage_{word_id}",
                                'word_id': word_id,
                                'exercise_type': 'order_sentence',
                                'difficulty': 3,
                                'payload': payload,
                                'group_id': None,
                                'selected_by': SelectionReason.FALLBACK
                            }
                            break

                    # 2. Try Recognition (Quiz)
                    if not variant and focus == 'recognition':
                        distractors = self._generate_distractors(
                            user_id, language_code, word_id, hanzi, 'meaning_select'
                        )
                        if len(distractors) >= 1: # We need at least some options
                            # Fetch meanings for distractors
                            dist_meanings = []
                            for d_txt in distractors:
                                d_row = self.conn.execute(
                                    "SELECT id, meaning FROM concepts WHERE text = ? ORDER BY id ASC LIMIT 1",
                                    (d_txt,),
                                ).fetchone()
                                if d_row:
                                    dist_meanings.append(
                                        get_primary_gloss(
                                            self.conn,
                                            str(d_row[0]),
                                            fallback=d_row[1],
                                        )
                                    )
                            
                            # Pad if needed (fallback to generic)
                            while len(dist_meanings) < 3:
                                dist_meanings.append("Something else")

                            all_opts = [primary_gloss] + dist_meanings[:3]
                            # Shuffle deterministically
                            seed_q = self._stable_hash(word_id, "auto_quiz")
                            all_opts.sort(key=lambda x: self._stable_hash(seed_q, x))
                            
                            variant = {
                                'id': f"auto_recog_{word_id}",
                                'word_id': word_id,
                                'exercise_type': 'meaning_select',
                                'difficulty': 1,
                                'payload': {
                                    "prompt": {"hanzi": hanzi, "pinyin": pinyin},
                                    "options": all_opts,
                                    "answer": primary_gloss,
                                    "answer_index": all_opts.index(primary_gloss),
                                    "instruction_en": "Choose the correct meaning",
                                    "sense": sense_payload,
                                },
                                'group_id': None,
                                'selected_by': SelectionReason.FALLBACK
                            }

                    # 3. Try Listening (Audio Select)
                    if not variant and focus in ('listening', 'tone'):
                        distractors = self._generate_distractors(
                            user_id, language_code, word_id, hanzi, 'audio_select'
                        )
                        choices = [hanzi] + distractors[:3]
                        if len(choices) < 4:
                            # deterministic padding from concepts if distractors are scarce
                            rows = self.conn.execute("""
                                SELECT text FROM concepts
                                WHERE id != ?
                                ORDER BY id ASC
                                LIMIT 6
                            """, (word_id,)).fetchall()
                            for row in rows:
                                text = row[0]
                                if text not in choices:
                                    choices.append(text)
                                if len(choices) >= 4:
                                    break
                        seed_q = self._stable_hash(word_id, "auto_audio_select")
                        choices.sort(key=lambda x: self._stable_hash(seed_q, x))
                        variant = {
                            'id': f"auto_listen_{word_id}",
                            'word_id': word_id,
                            'exercise_type': 'audio_select',
                            'difficulty': 1,
                            'payload': {
                                "choices": choices,
                                "answer": hanzi,
                                "answer_index": choices.index(hanzi),
                                "instruction_en": "Listen and choose the characters",
                                "prompt": {"meaning": primary_gloss, "pinyin": pinyin},
                                "sense": sense_payload,
                            },
                            'group_id': None,
                            'selected_by': SelectionReason.FALLBACK
                        }

                    # 4. Try Production (Speaking/Character Select)
                    if not variant and focus == 'production':
                        sent_rows = self.conn.execute("""
                            SELECT s.text, s.translation
                            FROM sentences s
                            JOIN word_sentences ws ON s.id = ws.sentence_id
                            WHERE ws.word_id = ? AND ws.is_primary = 1
                            ORDER BY ws.sentence_id ASC
                            LIMIT 5
                        """, (word_id,)).fetchall()

                        if ex_type == 'speak_read_aloud':
                            sample_answers = [hanzi]
                            for row in sent_rows:
                                sentence_zh = str(row[0] or '').strip()
                                if sentence_zh and sentence_zh not in sample_answers:
                                    sample_answers.append(sentence_zh)
                                if len(sample_answers) >= 3:
                                    break
                            variant = {
                                'id': f"auto_speak_read_{word_id}_{difficulty}",
                                'word_id': word_id,
                                'exercise_type': 'speak_read_aloud',
                                'difficulty': 2,
                                'payload': {
                                    "prompt": {
                                        "hanzi": hanzi,
                                        "pinyin": pinyin,
                                        "meaning": primary_gloss,
                                    },
                                    "sample_answers": sample_answers,
                                    "instruction_en": "Read aloud and self-rate",
                                    "sense": sense_payload,
                                },
                                'group_id': None,
                                'selected_by': SelectionReason.FALLBACK
                            }

                        elif ex_type == 'speak_prompted_reply':
                            sample_sentence = None
                            sample_translation = None
                            if sent_rows:
                                sample_sentence = str(sent_rows[0][0] or '').strip() or None
                                sample_translation = str(sent_rows[0][1] or '').strip() or None
                            prompt_text = sample_translation or f"Say a short sentence with '{hanzi}'"
                            sample_answers = [sample_sentence] if sample_sentence else [hanzi]
                            variant = {
                                'id': f"auto_speak_reply_{word_id}_{difficulty}",
                                'word_id': word_id,
                                'exercise_type': 'speak_prompted_reply',
                                'difficulty': 2,
                                'payload': {
                                    "prompt_text": prompt_text,
                                    "prompt": {
                                        "hanzi": hanzi,
                                        "pinyin": pinyin,
                                        "meaning": primary_gloss,
                                    },
                                    "sample_answers": sample_answers,
                                    "instruction_en": "Respond aloud and self-rate",
                                    "sentence": sample_sentence,
                                    "translation": sample_translation,
                                    "sense": sense_payload,
                                },
                                'group_id': None,
                                'selected_by': SelectionReason.FALLBACK
                            }

                        if not variant:
                            distractors = self._generate_distractors(
                                user_id, language_code, word_id, hanzi, 'character_select'
                            )
                            choices = [hanzi] + distractors[:3]
                            if len(choices) < 4:
                                rows = self.conn.execute("""
                                    SELECT text FROM concepts
                                    WHERE id != ?
                                    ORDER BY id ASC
                                    LIMIT 6
                                """, (word_id,)).fetchall()
                                for row in rows:
                                    text = row[0]
                                    if text not in choices:
                                        choices.append(text)
                                    if len(choices) >= 4:
                                        break
                            seed_q = self._stable_hash(word_id, "auto_character_select")
                            choices.sort(key=lambda x: self._stable_hash(seed_q, x))
                            variant = {
                                'id': f"auto_prod_{word_id}",
                                'word_id': word_id,
                                'exercise_type': 'character_select',
                                'difficulty': 2,
                                'payload': {
                                    "prompt": {"meaning": primary_gloss, "pinyin": pinyin},
                                    "choices": choices,
                                    "answer": hanzi,
                                    "answer_index": choices.index(hanzi),
                                    "instruction_en": "Choose the correct characters",
                                    "sense": sense_payload,
                                },
                                'group_id': None,
                                'selected_by': SelectionReason.FALLBACK
                            }

                    # 5. Last Resort: Flashcard
                    if not variant:
                        variant = {
                            'id': f"fallback_{word_id}_{difficulty}",
                            'word_id': word_id,
                            'exercise_type': 'flashcard', 
                            'difficulty': 1, 
                            'payload': {
                                "front": hanzi,
                                "pinyin": pinyin,
                                "back": primary_gloss,
                                "audio": None,
                                "type": "flashcard",
                                "instruction_en": "Learn this word",
                                "sense": sense_payload,
                            },
                            'group_id': None,
                            'selected_by': SelectionReason.FALLBACK
                        }
                    
                    # Fill common fields
                    variant.setdefault('content_exhausted', False)
                    variant.setdefault('exhaustion_reason', None)
                    variant.setdefault('exclusion_applied', ExclusionApplied())

            
            if variant:
                # [DISTRACTOR INJECTION]
                # Inject real distractors for sentence_fill and collocation_pick
                if variant['exercise_type'] in ('sentence_fill', 'collocation_pick'):
                    payload = variant.get('payload', {})
                    correct = payload.get('correct')
                    # If we have a correct answer string, generate distractors
                    if correct:
                        distractors = self._generate_distractors(
                            user_id, language_code, word_id, correct, variant['exercise_type']
                        )
                        # Combine and Deterministic Shuffle
                        options = [correct] + distractors
                        seed_opt = self._stable_hash(word_id, variant['id'], "options_shuffle")
                        options.sort(key=lambda x: self._stable_hash(seed_opt, x))
                        
                        payload['options'] = options
                        payload['option_type'] = 'hanzi'
                        variant['payload'] = payload

                # [TONE_SELECT VALIDATION/REPAIR]
                if variant['exercise_type'] == 'tone_select':
                    repaired = self._ensure_tone_select_payload(word_id, variant.get('payload', {}))
                    if repaired is None:
                        # If we can't validate/repair, skip this variant
                        continue
                    variant['payload'] = repaired

                    # [AUDIO MAPPING]
                payload = variant.get('payload', {})
                if isinstance(payload, dict):
                    if variant['exercise_type'] == 'order_sentence':
                        raw_segments = payload.get("segments") or payload.get("chunks")
                        if isinstance(raw_segments, list):
                            merged_segments = self._merge_punctuation_segments(
                                [str(item) for item in raw_segments if item is not None]
                            )
                            payload["segments"] = merged_segments
                            payload["chunks"] = merged_segments
                    payload = self._apply_sense_metadata(word_id, payload, preferred_sense_id=preferred_sense_id)
                    payload = self._apply_audio_mapping(word_id, variant['exercise_type'], payload)
                    payload = self._apply_image_mapping(word_id, variant['exercise_type'], payload)
                    variant['payload'] = payload
                    self.used_sentence_keys.update(self._extract_sentence_keys(payload))
                if variant.get('id'):
                    self.used_exercise_ids.add(variant['id'])

                plan_slot_id = make_plan_slot_id(review_instance_id, slot_key)
                exercises.append(SelectedExercise(
                    exercise_id=variant['id'],
                    word_id=word_id,
                    exercise_type=variant['exercise_type'],
                    difficulty=variant['difficulty'],
                    payload=variant['payload'],
                    skill_focus=focus,
                    stage=stage,
                    review_instance_id=review_instance_id,
                    slot_key=slot_key,
                    plan_slot_id=plan_slot_id,
                    group_id=variant.get('group_id'),
                    selected_by=variant.get('selected_by', SelectionReason.UNSEEN),
                    content_exhausted=variant.get('content_exhausted', False),
                    exhaustion_reason=variant.get('exhaustion_reason'),
                    exclusion_applied=variant.get('exclusion_applied', ExclusionApplied())
                ))
        
        return exercises
    
    def reset_mission_state(self):
        """Reset per-mission tracking."""
        self.type_rotation.clear()
        self.used_groups.clear()
        self.used_exercise_ids.clear()
        self.used_sentence_keys.clear()
        self._recent_sentence_cache.clear()
        self._exhaustion_log.clear()


def create_selector(conn: sqlite3.Connection, mission_seed: str = "") -> BrainSelector:
    """Factory function."""
    return BrainSelector(conn, mission_seed)
