"""
DRAGON CHINESE BRAIN V3.2 — Production Grade Engine
--------------------------------------------------
Synthesized from DeepSeek, OpenAI, and Gemini Pro research.
Optimizations: Latency-aware readiness, Level-locked confusion, Preview cooldown.
"""

import sqlite3
import os
import json
import random
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple, Any


# --- Architectural Helpers ---

def utc_iso_z(dt: datetime) -> str:
    """Standardized UTC ISO format matching SQLite defaults (Z suffix)."""
    return dt.astimezone(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")

def utc_now_iso() -> str:
    return utc_iso_z(datetime.now(timezone.utc))

def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


class DatabaseV2:
    def __init__(self, db_path="vocabulary_v2.db"):
        self.db_path = db_path
        self._init_mastery_tables()

    def _get_conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;") 
        conn.execute("PRAGMA foreign_keys=ON;")
        return conn

    # --- Schema & Maintenance ---

    def _safe_alter(self, conn, table, col, definition):
        try: conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} {definition}")
        except sqlite3.OperationalError: pass

    def _safe_index(self, conn, name, on_expr):
        try: conn.execute(f"CREATE INDEX IF NOT EXISTS {name} ON {on_expr}")
        except sqlite3.OperationalError: pass

    def _init_mastery_tables(self):
        conn = self._get_conn()
        try:
            # 1. Base V3 Mastery Schema
            schema_path = os.path.join(os.path.dirname(__file__), "schema_v3_mastery.sql")
            if os.path.exists(schema_path):
                with open(schema_path, "r", encoding="utf-8") as f:
                    for stmt in f.read().split(';'):
                        if stmt.strip():
                            try: conn.execute(stmt)
                            except sqlite3.OperationalError: pass

            # 2. DeepSeek Linguistic Extensions (With Safety Defaults)
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS tone_error_patterns (
                user_id TEXT NOT NULL,
                concept_id INTEGER NOT NULL,
                error_type TEXT NOT NULL, 
                pattern TEXT NOT NULL,
                occurrence_count INTEGER DEFAULT 1,
                last_seen TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
                PRIMARY KEY (user_id, concept_id, error_type)
            );

            CREATE TABLE IF NOT EXISTS character_confusions (
                user_id TEXT NOT NULL,
                base_character_id INTEGER NOT NULL,
                confused_with_id INTEGER NOT NULL,
                confusion_type TEXT DEFAULT 'visual',
                confusion_count INTEGER DEFAULT 1,
                last_confused TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
                PRIMARY KEY (user_id, base_character_id, confused_with_id)
            );

            CREATE TABLE IF NOT EXISTS character_components (
                character_id INTEGER,
                component_hanzi TEXT,
                component_type TEXT,
                UNIQUE(character_id, component_hanzi)
            );
            """)

            # 3. Analytics & Metadata Columns
            self._safe_alter(conn, "concepts", "avg_latency_ms", "REAL DEFAULT 0.0")
            self._safe_alter(conn, "concepts", "total_attempts", "INTEGER DEFAULT 0")
            self._safe_alter(conn, "concepts", "struggle_count", "INTEGER DEFAULT 0")
            self._safe_alter(conn, "concepts", "confusion_rate", "REAL DEFAULT 0.0")
            self._safe_alter(conn, "concepts", "tone_pattern", "TEXT")
            self._safe_alter(conn, "concepts", "stroke_count", "INTEGER DEFAULT 1")
            
            self._safe_alter(conn, "user_mastery_v3", "is_preview_word", "BOOLEAN DEFAULT 0")
            self._safe_alter(conn, "user_mastery_v3", "last_tone_error", "TEXT")

            # 4. Performance Indexes
            self._safe_index(conn, "idx_mastery_user_concept", "user_mastery_v3(user_id, concept_id)")
            self._safe_index(conn, "idx_mastery_user_next", "user_mastery_v3(user_id, next_review)")
            self._safe_index(conn, "idx_concepts_level", "concepts(level)")
            self._safe_index(conn, "idx_events_user_created", "learning_events(user_id, created_at)")
            self._safe_index(conn, "idx_tone_user_seen", "tone_error_patterns(user_id, last_seen)")

            conn.commit()
        finally:
            conn.close()

    # --- Profile Logic ---

    def get_or_create_profile(self, user_id: str, native_lang: str = "en") -> Dict:
        conn = self._get_conn()
        try:
            row = conn.execute("SELECT * FROM user_profiles WHERE user_id = ?", (user_id,)).fetchone()
            if not row:
                conn.execute("INSERT INTO user_profiles (user_id, native_lang) VALUES (?, ?)", (user_id, native_lang))
                conn.commit()
                row = conn.execute("SELECT * FROM user_profiles WHERE user_id = ?", (user_id,)).fetchone()
            return dict(row)
        finally:
            conn.close()

    def update_profile_goal(self, user_id: str, goal: str):
        conn = self._get_conn()
        conn.execute("UPDATE user_profiles SET learning_goal = ?, updated_at = ? WHERE user_id = ?", 
                     (goal, utc_now_iso(), user_id))
        conn.commit()
        conn.close()

    # --- Event Logging ---

    def log_learning_event(self, event_data: Dict):
        conn = self._get_conn()
        try:
            now = utc_now_iso()
            event_data['created_at'] = event_data.get('created_at') or now
            
            tone_errors = event_data.get('tone_errors_json')
            confused_with = event_data.get('confused_with', []) or []
            
            conn.execute("""
                INSERT INTO learning_events 
                (user_id, concept_id, skill_type, was_correct, latency_ms, 
                 attempts, confidence, tone_accuracy, tone_errors_json, created_at)
                VALUES (:user_id, :concept_id, :skill_type, :was_correct, :latency_ms, 
                 :attempts, :confidence, :tone_accuracy, :tone_errors_json, :created_at)
            """, event_data)

            # O(1) Global Concept Update
            latency = float(event_data.get('latency_ms', 3000))
            is_struggle = 1 if (not event_data.get('was_correct') or latency >= 5000) else 0
            
            conn.execute("""
                UPDATE concepts 
                SET 
                    avg_latency_ms = CASE WHEN total_attempts <= 0 THEN ? 
                                     ELSE avg_latency_ms + ((? - avg_latency_ms) / (total_attempts + 1.0)) END,
                    total_attempts = total_attempts + 1,
                    struggle_count = struggle_count + ?,
                    confusion_rate = (struggle_count + ?) / (total_attempts + 1.0)
                WHERE id = ?
            """, (latency, latency, is_struggle, is_struggle, event_data['concept_id']))

            if tone_errors:
                try:
                    errors = json.loads(tone_errors)
                    for err_type, pattern in errors.items():
                        conn.execute("""
                            INSERT INTO tone_error_patterns (user_id, concept_id, error_type, pattern, last_seen)
                            VALUES (?, ?, ?, ?, ?)
                            ON CONFLICT(user_id, concept_id, error_type) DO UPDATE SET
                            occurrence_count = occurrence_count + 1, last_seen = excluded.last_seen
                        """, (event_data['user_id'], event_data['concept_id'], err_type, str(pattern), now))
                except Exception as e:
                    print(f"Error logging tone pattern: {e}")

            for cid in confused_with:
                try:
                    conn.execute("""
                        INSERT INTO character_confusions (user_id, base_character_id, confused_with_id, last_confused)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(user_id, base_character_id, confused_with_id) DO UPDATE SET
                        confusion_count = confusion_count + 1, last_confused = excluded.last_confused
                    """, (event_data['user_id'], event_data['concept_id'], int(cid), now))
                except Exception as e:
                    print(f"Error logging confusion: {e}")

            conn.execute("INSERT OR IGNORE INTO user_mastery_v3 (user_id, concept_id) VALUES (?, ?)", 
                        (event_data['user_id'], event_data['concept_id']))
            conn.commit()
        finally:
            conn.close()

    # --- The Brain: Mission Generation ---

    def _tag_like_clause(self, tags: List[str]) -> Tuple[str, List[str]]:
        if not tags: return "0=1", []
        parts, params = [], []
        for t in tags:
            parts.append("c.semantic_tags LIKE ?")
            params.append(f"%|{t}|%")
        return " OR ".join(parts), params

    def get_next_mission_words(self, user_id: str, limit_new: int = 4, limit_review: int = 6) -> Dict:
        conn = self._get_conn()
        try:
            profile = self.get_or_create_profile(user_id)
            goal = profile.get('learning_goal', 'hsk')
            current_level = int(profile.get('current_hsk_level', 1))
            
            seen_ids: set[int] = set()
            final_new: List[Dict[str, Any]] = []

            # 1) READINESS GATE (Accuracy + Latency)
            perf = conn.execute("""
                SELECT AVG(CAST(was_correct AS REAL)) AS acc,
                       AVG(CAST(latency_ms AS REAL)) AS avg_lat
                FROM (
                    SELECT was_correct, latency_ms FROM learning_events
                    WHERE user_id = ? ORDER BY created_at DESC LIMIT 10
                )
            """, (user_id,)).fetchone()
            acc = float(perf["acc"]) if perf and perf["acc"] is not None else 1.0
            avg_lat = float(perf["avg_lat"]) if perf and perf["avg_lat"] is not None else 999999.0
            
            # 2) OVERSHOOT COOLDOWN (Check last preview)
            four_hours_ago = utc_iso_z(datetime.now(timezone.utc) - timedelta(hours=4))
            row = conn.execute("""
                SELECT COUNT(*) FROM user_mastery_v3 
                WHERE user_id = ? AND is_preview_word = 1 AND last_seen >= ?
            """, (user_id, four_hours_ago)).fetchone()
            recent_preview = int(row[0]) if row else 0
            
            ready_for_overshoot = (acc >= 0.7) and (avg_lat <= 3500) and (recent_preview == 0)

            # 3) TONE INTERVENTION
            since = utc_iso_z(datetime.now(timezone.utc) - timedelta(days=2))
            patterns = [r['pattern'] for r in conn.execute("""
                SELECT DISTINCT pattern FROM tone_error_patterns 
                WHERE user_id = ? AND last_seen >= ? ORDER BY last_seen DESC LIMIT 3
            """, (user_id, since)).fetchall()]

            if patterns:
                ph = ",".join(["?"] * len(patterns))
                rows = conn.execute(f"""
                    SELECT c.* FROM concepts c
                    WHERE c.level = ? AND c.tone_pattern IN ({ph})
                    AND c.id NOT IN (SELECT concept_id FROM user_mastery_v3 WHERE user_id = ?)
                    ORDER BY c.base_utility DESC LIMIT 2
                """, (current_level, *patterns, user_id)).fetchall()
                for r in rows:
                    cid = int(r["id"])
                    if cid not in seen_ids:
                        seen_ids.add(cid); final_new.append(dict(r))

            # 4) CHARACTER CONFUSION REPAIR (Level-Locked + Not Mastered)
            conf_row = conn.execute("""
                SELECT c2.* FROM character_confusions cc
                JOIN concepts c2 ON c2.id = cc.confused_with_id
                WHERE cc.user_id = ? 
                  AND c2.level <= ?
                  AND c2.id NOT IN (SELECT concept_id FROM user_mastery_v3 WHERE user_id = ?)
                ORDER BY cc.confusion_count DESC LIMIT 1
            """, (user_id, current_level + 1, user_id)).fetchone()
            if conf_row:
                cid = int(conf_row["id"])
                if cid not in seen_ids:
                    seen_ids.add(cid); final_new.append(dict(conf_row))

            # 5) CORE NEW WORDS (Weighted)
            tag_map = {
                'digital': ['tech_electronics', 'internet_digital'],
                'cultural': ['arts_entertainment', 'history_heritage'],
                'business': ['work_business', 'finance_economy'],
                'survival': ['emergency_safety', 'health_fitness'],
                'travel': ['transport_travel', 'shopping_fashion']
            }
            tags = tag_map.get(goal, [])
            tag_clause, tag_params = self._tag_like_clause(tags)
            
            remaining_limit = max(0, limit_new - len(final_new) - (1 if ready_for_overshoot else 0))
            if remaining_limit > 0:
                seen_list = sorted(seen_ids)
                seen_clause = f"AND c.id NOT IN ({','.join(['?'] * len(seen_list))})" if seen_list else ""
                core_sql = f"""
                    SELECT c.*, COALESCE(gw.weight, 1.0) as goal_weight,
                           CASE WHEN ({tag_clause}) THEN 1 ELSE 0 END as tag_hit
                    FROM concepts c
                    LEFT JOIN goal_word_weights gw ON gw.category = c.category AND gw.goal = ?
                    WHERE c.level = ? AND c.id NOT IN (SELECT concept_id FROM user_mastery_v3 WHERE user_id = ?)
                    {seen_clause}
                    ORDER BY tag_hit DESC, (c.base_utility * COALESCE(gw.weight, 1.0)) DESC
                    LIMIT ?
                """
                full_params = [*tag_params, goal, current_level, user_id, *seen_list, remaining_limit]
                rows = conn.execute(core_sql, tuple(full_params)).fetchall()
                for r in rows:
                    cid = int(r["id"])
                    if cid not in seen_ids:
                        seen_ids.add(cid); final_new.append(dict(r))

            # 6) OVERSHOOT (Persona-Aware + Cooldown Corrected)
            if ready_for_overshoot:
                seen_list = sorted(seen_ids)
                seen_clause = f"AND c.id NOT IN ({','.join(['?'] * len(seen_list))})" if seen_list else ""
                row = conn.execute(f"""
                    SELECT c.*, CASE WHEN ({tag_clause}) THEN 1 ELSE 0 END as tag_hit
                    FROM concepts c WHERE c.level = ?
                    AND c.id NOT IN (SELECT concept_id FROM user_mastery_v3 WHERE user_id = ?)
                    {seen_clause}
                    ORDER BY tag_hit DESC, c.base_utility DESC LIMIT 1
                """, tuple([*tag_params, current_level + 1, user_id, *seen_list])).fetchone()
                if row:
                    bonus_word = dict(row)
                    final_new.append(bonus_word)
                    # Corrected: Set last_seen on insert to trigger cooldown
                    conn.execute("""
                        INSERT INTO user_mastery_v3 (user_id, concept_id, is_preview_word, last_seen)
                        VALUES (?, ?, 1, ?)
                        ON CONFLICT(user_id, concept_id) DO UPDATE SET
                          is_preview_word = 1, last_seen = excluded.last_seen
                    """, (user_id, bonus_word['id'], utc_now_iso()))
                    conn.commit()

            # 7) REVIEWS
            reviews = [dict(r) for r in conn.execute("""
                SELECT c.*, m.meaning_strength, m.tone_strength FROM concepts c
                JOIN user_mastery_v3 m ON c.id = m.concept_id
                WHERE m.user_id = ? AND (m.next_review <= ? OR m.next_review IS NULL)
                ORDER BY m.next_review ASC LIMIT ?
            """, (user_id, utc_now_iso(), limit_review)).fetchall()]

            return {
                "new_words": final_new,
                "reviews": reviews,
                "mission_type": "dragon_chimera_v3.2_prod",
                "stats": {"ready_for_overshoot": ready_for_overshoot, "new_count": len(final_new), "recent_acc": round(acc, 2)}
            }
        finally:
            conn.close()

    # --- SRS Engine ---

    def update_mastery_srs(self, user_id: str, concept_id: int, result: Dict) -> Dict:
        conn = self._get_conn()
        try:
            mastery = self.get_user_mastery(user_id, concept_id)
            if not mastery:
                conn.execute("INSERT OR IGNORE INTO user_mastery_v3 (user_id, concept_id) VALUES (?, ?)", (user_id, concept_id))
                conn.commit()
                mastery = self.get_user_mastery(user_id, concept_id) or {}

            # Metrics & Tone Veto
            latency = float(result.get('latency_ms', 3000))
            tone_acc = float(result.get('tone_accuracy', 1.0))
            was_correct = bool(result.get('was_correct', False))
            if result.get('skill_type') == 'speaking' and tone_acc < 0.75: was_correct = False

            # Quality (0-5)
            if was_correct:
                if latency < 1500 and tone_acc > 0.9: q = 5
                elif latency < 3000: q = 4
                else: q = 3
            else: q = 1 if latency < 6000 else 0

            # SM-2 Logic with Fuzz
            ef = float(mastery.get('ease_factor', 2.5) or 2.5)
            interval = float(mastery.get('interval_days', 0.0) or 0.0)
            count = int(mastery.get('review_count', 0) or 0)

            if q >= 3:
                if count == 0: interval = 1
                elif count == 1: interval = 4
                else: interval = interval * ef
                count += 1
                ef = ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
            else:
                count = max(0, count - 1)
                interval = 0.2
                ef = max(1.3, ef - 0.15)

            interval *= random.uniform(0.95, 1.05)
            next_rev = utc_iso_z(datetime.now(timezone.utc) + timedelta(days=interval))

            conn.execute("""
                UPDATE user_mastery_v3 SET 
                ease_factor=?, interval_days=?, review_count=?, next_review=?, last_seen=?
                WHERE user_id=? AND concept_id=?
            """, (clamp(ef, 1.3, 2.8), interval, count, next_rev, utc_now_iso(), user_id, concept_id))
            
            conn.commit()
            return {"next_review": next_rev, "quality": q}
        finally:
            conn.close()

    def get_user_mastery(self, user_id: str, concept_id: int) -> Optional[Dict]:
        conn = self._get_conn()
        try:
            row = conn.execute("SELECT * FROM user_mastery_v3 WHERE user_id=? AND concept_id=?", (user_id, concept_id)).fetchone()
            return dict(row) if row else None
        finally:
            conn.close()

    # --- Content Retrieval ---

    def get_unit_intro(self, unit_id: str) -> Optional[Dict]:
        """Fetch the audio intro metadata for a unit."""
        conn = self._get_conn()
        try:
            row = conn.execute("SELECT * FROM unit_intros WHERE unit_id = ?", (unit_id,)).fetchone()
            if row:
                return dict(row)
            return None
        finally:
            conn.close()

    # --- Vocabulary Retrieval ---

    def get_vocabulary(self, target_lang: str, native_lang: str, level: int = None, limit: int = 50, offset: int = 0):
        """
        Efficiently joins concepts and translations to return only the needed languages.
        """
        conn = self._get_conn()
        try:
            query = """
                SELECT 
                    c.id, c.semantic_key, c.word, c.pronunciation, c.pos, c.context_sentence, c.level, c.image_url,
                    t.translation, t.context_translation
                FROM concepts c
                LEFT JOIN translations t ON c.id = t.concept_id AND t.native_lang = ?
                WHERE c.target_lang = ?
            """
            params = [native_lang, target_lang]
            
            if level:
                query += " AND c.level = ?"
                params.append(level)
                
            query += " LIMIT ? OFFSET ?"
            params.extend([limit, offset])
            
            cursor = conn.execute(query, params)
            results = [dict(row) for row in cursor.fetchall()]
            
            # Get total count
            count_query = "SELECT COUNT(*) FROM concepts WHERE target_lang = ?"
            count_params = [target_lang]
            if level:
                count_query += " AND level = ?"
                count_params.append(level)
            
            total = conn.execute(count_query, count_params).fetchone()[0]
            return results, total
        finally:
            conn.close()

    def get_random_vocabulary(self, target_lang: str, native_lang: str, level: int, limit: int = 20):
        """
        Get random vocabulary items for matching or quick study.
        """
        conn = self._get_conn()
        try:
            query = """
                SELECT 
                    c.id, c.semantic_key, c.word, c.pronunciation, c.pos, c.context_sentence, c.level, c.image_url,
                    t.translation, t.context_translation
                FROM concepts c
                LEFT JOIN translations t ON c.id = t.concept_id AND t.native_lang = ?
                WHERE c.target_lang = ? AND c.level = ?
                ORDER BY RANDOM()
                LIMIT ?
            """
            cursor = conn.execute(query, (native_lang, target_lang, level, limit))
            return [dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_brain_summary(self, user_id: str) -> Dict[str, Any]:
        """
        Get high-level stats for the Dashboard Mission Card.
        """
        conn = self._get_conn()
        try:
            now = datetime.now(timezone.utc).isoformat()
            
            # 1. Due Reviews
            row_rev = conn.execute("""
                SELECT COUNT(*) FROM user_mastery_v3 
                WHERE user_id = ? AND next_review <= ?
            """, (user_id, now)).fetchone()
            review_due = int(row_rev[0]) if row_rev else 0
            
            # 2. Next Review Time (min next_review > now)
            row_next = conn.execute("""
                SELECT MIN(next_review) FROM user_mastery_v3
                WHERE user_id = ? AND next_review > ?
            """, (user_id, now)).fetchone()
            next_review_at = row_next[0] if row_next and row_next[0] else None
            
            # 3. Learn Available (Stage 0)
            profile = self.get_or_create_profile(user_id)
            level = int(profile.get('current_hsk_level', 1))
            
            row_learn = conn.execute("""
                SELECT COUNT(*) FROM concepts c
                WHERE c.level = ? 
                AND c.id NOT IN (SELECT concept_id FROM user_mastery_v3 WHERE user_id = ?)
            """, (level, user_id)).fetchone()
            learn_count = int(row_learn[0]) if row_learn else 0
            
            return {
                "due_count": review_due, 
                "review_due_count": review_due,
                "learn_available_count": learn_count,
                "next_review_at": next_review_at,
                "has_active_mission": False,
                "active_mission_id": None,
                "server_time": now
            }
        finally:
            conn.close()