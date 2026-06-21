"""
Knowledge policy helpers for mission adaptation.

Keeps knowledge-state analytics and candidate ordering out of router_brain.py.
"""

from typing import Any, Dict, List
import sqlite3


def recent_knowledge_signal(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    lookback_minutes: int = 45,
    per_word_lookback_hours: int = 72,
    limit_words: int = 24,
) -> Dict[str, Any]:
    """
    Build knowledge-state signal from recent attempts.
    Requires user_attempts.knowledge_state values from the exercise engine.
    """
    agg = conn.execute(
        """
        SELECT
            COUNT(*) AS samples,
            SUM(CASE WHEN knowledge_state = 'knows' THEN 1 ELSE 0 END) AS knows_count,
            SUM(CASE WHEN knowledge_state = 'learning' THEN 1 ELSE 0 END) AS learning_count,
            SUM(CASE WHEN knowledge_state = 'struggling' THEN 1 ELSE 0 END) AS struggling_count
        FROM user_attempts
        WHERE user_id = ?
          AND language_code = ?
          AND knowledge_state IN ('knows', 'learning', 'struggling')
          AND created_at >= datetime('now', '-' || ? || ' minutes')
        """,
        [user_id, language_code, lookback_minutes],
    ).fetchone()

    samples = int(agg[0] or 0) if agg else 0
    knows = int(agg[1] or 0) if agg else 0
    learning = int(agg[2] or 0) if agg else 0
    struggling = int(agg[3] or 0) if agg else 0

    knows_ratio = (knows / samples) if samples > 0 else 0.0
    struggling_ratio = (struggling / samples) if samples > 0 else 0.0

    mode = "normal"
    reason = "insufficient_knowledge_history"
    if samples >= 6:
        if struggling_ratio >= 0.45:
            mode = "assist"
            reason = "knowledge_struggling_ratio_high"
        elif knows_ratio >= 0.65 and struggling <= 1:
            mode = "challenge"
            reason = "knowledge_knows_ratio_high"
        else:
            mode = "normal"
            reason = "knowledge_balanced"

    rows = conn.execute(
        """
        SELECT
            word_id,
            SUM(CASE WHEN knowledge_state = 'struggling' THEN 1 ELSE 0 END) AS struggling_count,
            SUM(CASE WHEN knowledge_state = 'knows' THEN 1 ELSE 0 END) AS knows_count,
            MAX(created_at) AS last_seen
        FROM user_attempts
        WHERE user_id = ?
          AND language_code = ?
          AND knowledge_state IN ('knows', 'learning', 'struggling')
          AND created_at >= datetime('now', '-' || ? || ' hours')
        GROUP BY word_id
        HAVING COUNT(*) > 0
        ORDER BY struggling_count DESC, knows_count ASC, last_seen DESC
        LIMIT ?
        """,
        [user_id, language_code, per_word_lookback_hours, max(limit_words * 2, 48)],
    ).fetchall()

    top_struggling_words: List[str] = []
    top_knows_words: List[str] = []
    for row in rows:
        wid = str(row[0] or "")
        if not wid:
            continue
        s_count = int(row[1] or 0)
        k_count = int(row[2] or 0)
        if s_count >= 2 and wid not in top_struggling_words:
            top_struggling_words.append(wid)
        if k_count >= 2 and s_count == 0 and wid not in top_knows_words:
            top_knows_words.append(wid)
        if len(top_struggling_words) >= limit_words and len(top_knows_words) >= limit_words:
            break

    return {
        "samples": samples,
        "knows": knows,
        "learning": learning,
        "struggling": struggling,
        "knows_ratio": round(knows_ratio, 4),
        "struggling_ratio": round(struggling_ratio, 4),
        "mode": mode,
        "mode_reason": reason,
        "top_struggling_words": top_struggling_words[:limit_words],
        "top_knows_words": top_knows_words[:limit_words],
    }


def prioritize_candidates_by_knowledge(
    candidates: List[Dict[str, Any]],
    retry_profile: Dict[str, Dict[str, Any]],
    knowledge_signal: Dict[str, Any],
) -> List[Dict[str, Any]]:
    """
    Deterministic ordering:
    1) struggling words first
    2) neutral words
    3) known words later
    Within tier, higher retry fail_count first.
    """
    if not candidates:
        return candidates

    struggling_words = set(str(w) for w in (knowledge_signal.get("top_struggling_words") or []))
    knows_words = set(str(w) for w in (knowledge_signal.get("top_knows_words") or []))
    indexed = list(enumerate(candidates))

    def _rank(entry: Any) -> Any:
        idx, cand = entry
        word_id = str(cand.get("word_id") or "")
        fail_count = int((retry_profile.get(word_id) or {}).get("fail_count") or 0)
        if word_id in struggling_words:
            tier = 0
        elif word_id in knows_words:
            tier = 2
        else:
            tier = 1
        return (tier, -fail_count, idx)

    indexed.sort(key=_rank)
    return [cand for _, cand in indexed]
