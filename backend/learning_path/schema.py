"""
Learning Path 2.0 - Database Schema
Technical Memo v1.1 (with 6 final fixes)

This module provides the SQLite schema for the mastery-driven learning system.
"""

import sqlite3
from pathlib import Path
from datetime import datetime

# Schema version for migrations
SCHEMA_VERSION = "1.6.1"


def get_schema_sql() -> str:
    """Return the complete schema SQL with all v1.1 fixes applied."""
    return """
-- ============================================================
-- USER PROFILES
-- ============================================================

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT PRIMARY KEY,
    native_lang TEXT DEFAULT 'en',
    learning_goal TEXT DEFAULT 'hsk', -- 'hsk', 'casual', 'travel', etc.
    current_hsk_level INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);


-- ============================================================
-- CONTENT LIBRARY (per-language, read-only)
-- ============================================================

CREATE TABLE IF NOT EXISTS word_exercises (
    id TEXT PRIMARY KEY,
    word_id TEXT NOT NULL,
    exercise_type TEXT NOT NULL,
    difficulty INTEGER CHECK(difficulty BETWEEN 1 AND 5),
    variant_index INTEGER,
    payload TEXT NOT NULL,  -- JSON
    tags TEXT,              -- pipe-delimited: 'formal|collocation|grammar_ba'
    group_id TEXT,          -- for near-duplicate exclusion
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(word_id, exercise_type, variant_index)
);

CREATE INDEX IF NOT EXISTS idx_we_word_type 
    ON word_exercises(word_id, exercise_type, difficulty);
CREATE INDEX IF NOT EXISTS idx_we_group 
    ON word_exercises(word_id, exercise_type, group_id);


-- ============================================================
-- CANONICAL CONCEPTS (Text/Pinyin/Meaning Source)
-- ============================================================

CREATE TABLE IF NOT EXISTS concepts (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,       -- Surface text (e.g., Hanzi)
    pinyin TEXT,
    meaning TEXT,             -- English summary/gloss
    created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================================
-- CONCEPT SENSES (Sense-level semantics)
-- ============================================================

CREATE TABLE IF NOT EXISTS concept_senses (
    sense_id TEXT PRIMARY KEY,             -- e.g. W00001::s01
    concept_id TEXT NOT NULL,              -- concepts.id
    ordinal INTEGER NOT NULL DEFAULT 1,    -- 1-based order
    gloss TEXT NOT NULL,                   -- short EN gloss for this sense
    pos TEXT,                              -- optional part-of-speech
    register TEXT,                         -- optional register ("formal", "casual")
    example_zh TEXT,                       -- optional canonical example
    example_en TEXT,                       -- optional translation for example
    is_primary INTEGER NOT NULL DEFAULT 0 CHECK(is_primary IN (0, 1)),
    source TEXT DEFAULT 'bootstrap',
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(concept_id, ordinal),
    UNIQUE(concept_id, gloss)
);

CREATE INDEX IF NOT EXISTS idx_cs_concept ON concept_senses(concept_id);
CREATE INDEX IF NOT EXISTS idx_cs_primary ON concept_senses(concept_id, is_primary);

-- ============================================================
-- CURRICULUM STANDARD LOCK (HSK core vs extension)
-- ============================================================

CREATE TABLE IF NOT EXISTS concept_curriculum_map (
    concept_id TEXT NOT NULL,             -- concepts.id
    standard TEXT NOT NULL,               -- e.g. HSK2.0
    level TEXT NOT NULL,                  -- e.g. HSK1..HSK6
    band TEXT NOT NULL DEFAULT 'core',    -- core | extension
    source TEXT,                          -- provenance (pack file, manual, etc.)
    metadata TEXT,                        -- optional JSON metadata
    created_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (concept_id, standard, level, band)
);

CREATE INDEX IF NOT EXISTS idx_ccm_standard_level
    ON concept_curriculum_map(standard, level, band);
CREATE INDEX IF NOT EXISTS idx_ccm_concept
    ON concept_curriculum_map(concept_id);

-- ============================================================
-- UNITS (Curriculum Structure)
-- ============================================================

CREATE TABLE IF NOT EXISTS units (
    id TEXT PRIMARY KEY,              -- "UNIT_HSK1_001"
    title TEXT NOT NULL,              -- "Greetings & Self-Introduction"
    unit_number INTEGER NOT NULL,     -- 1, 2, 3...
    level TEXT DEFAULT 'HSK1',        -- HSK1, HSK2, etc.
    description TEXT,
    learning_objectives TEXT,         -- JSON: ["Greet people", "Introduce yourself"]
    estimated_hours REAL DEFAULT 2.0,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_units_level_number ON units(level, unit_number);

-- ============================================================
-- PATH GATING (unit_concepts mapping)
-- ============================================================

CREATE TABLE IF NOT EXISTS unit_concepts (
    unit_id TEXT NOT NULL,
    concept_id TEXT NOT NULL,  -- word_id
    sequence INTEGER,          -- ordering within unit
    PRIMARY KEY(unit_id, concept_id)
);

CREATE INDEX IF NOT EXISTS idx_uc_unit ON unit_concepts(unit_id);


-- ============================================================
-- UNIT INTROS (Audio Priming)
-- ============================================================

CREATE TABLE IF NOT EXISTS unit_intros (
    unit_id TEXT PRIMARY KEY,
    audio_url TEXT NOT NULL,
    script_hanzi TEXT NOT NULL,
    script_pinyin TEXT NOT NULL,
    translation TEXT NOT NULL,
    target_words TEXT,  -- JSON list of word_ids highlighted in this intro
    created_at TEXT DEFAULT (datetime('now'))
);


-- ============================================================
-- RICH SENTENCE BANK (First-class Content)
-- ============================================================

CREATE TABLE IF NOT EXISTS sentences (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,          -- Surface text (Hanzi)
    pinyin TEXT NOT NULL,
    translation TEXT NOT NULL,
    
    -- Analysis
    segmentation TEXT,           -- JSON: ["Wǒ", "yào", "kāfēi"]
    word_ids TEXT,               -- JSON: ["wo_3", "yao_2", "kafei_1"] linking to concepts.id
    
    -- Audio Assets (Multi-voice support)
    audio_male_url TEXT,
    audio_female_url TEXT,
    
    -- Context
    tags TEXT,                   -- pipe-delimited: "business|polite|ordering"
    difficulty INTEGER,          -- 1-5
    
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sentences_tags ON sentences(tags);


-- ============================================================
-- WORD <-> SENTENCE MAPPING (Context Injection)
-- ============================================================

CREATE TABLE IF NOT EXISTS word_sentences (
    word_id TEXT NOT NULL,
    sentence_id TEXT NOT NULL,
    is_primary BOOLEAN DEFAULT 0,  -- Is this the definitive example?
    PRIMARY KEY(word_id, sentence_id)
);

CREATE INDEX IF NOT EXISTS idx_ws_word ON word_sentences(word_id);


-- ============================================================
-- CONVERSATIONS / SCENARIOS
-- ============================================================

CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    title TEXT,
    topic TEXT,
    difficulty INTEGER,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS conversation_lines (
    conversation_id TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    speaker_id TEXT,       -- "A", "B", "Narrator"
    sentence_id TEXT NOT NULL,
    is_user_turn BOOLEAN DEFAULT 0, -- If true, user must select/speak this line
    PRIMARY KEY(conversation_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_conv_lines ON conversation_lines(conversation_id);


-- ============================================================
-- USER MASTERY STATE (scores stored 0-100)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_word_mastery (
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    word_id TEXT NOT NULL,
    -- Skill scores (0-100, display as score // 20 for 0-5)
    recognition INTEGER DEFAULT 0 CHECK(recognition BETWEEN 0 AND 100),
    listening INTEGER DEFAULT 0 CHECK(listening BETWEEN 0 AND 100),
    production INTEGER DEFAULT 0 CHECK(production BETWEEN 0 AND 100),
    usage INTEGER DEFAULT 0 CHECK(usage BETWEEN 0 AND 100),
    writing INTEGER DEFAULT 0 CHECK(writing BETWEEN 0 AND 100),
    -- State machine
    mastery_state TEXT DEFAULT 'UNKNOWN',
    srs_stage INTEGER DEFAULT 0,
    next_review_at TEXT,
    pending_since TEXT,  -- FIX #6: timestamp when entered MASTERED_PENDING_REVIEW
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY(user_id, language_code, word_id)
);

CREATE INDEX IF NOT EXISTS idx_uwm_review 
    ON user_word_mastery(user_id, language_code, next_review_at);
CREATE INDEX IF NOT EXISTS idx_uwm_state 
    ON user_word_mastery(user_id, language_code, mastery_state);


-- ============================================================
-- STAGE COMPLETION TRACKING
-- FIX #1: plan_slot_id = "{review_instance_id}:{slot_key}"
-- FIX #2: Stage completes when every slot_key in required_slots appears in passed_slots
-- ============================================================

CREATE TABLE IF NOT EXISTS user_word_stage_progress (
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    word_id TEXT NOT NULL,
    stage INTEGER NOT NULL,
    review_instance_id TEXT NOT NULL,  -- unique per review cycle
    required_slots TEXT NOT NULL,      -- JSON: ["recognition:1", "usage:1"]
    passed_slots TEXT DEFAULT '[]',    -- JSON: slot_keys that have been passed
    failed_attempts INTEGER DEFAULT 0, -- count of failures (for analytics)
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY(user_id, language_code, word_id, review_instance_id)
);

CREATE INDEX IF NOT EXISTS idx_uwsp_active 
    ON user_word_stage_progress(user_id, language_code, word_id, stage);


-- ============================================================
-- USER SENSE MASTERY STATE (sense-first tracking)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_sense_mastery (
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    sense_id TEXT NOT NULL,          -- e.g. W00001::s01
    word_id TEXT NOT NULL,           -- parent concept id for compatibility/debug
    -- Skill scores (0-100)
    recognition INTEGER DEFAULT 0 CHECK(recognition BETWEEN 0 AND 100),
    listening INTEGER DEFAULT 0 CHECK(listening BETWEEN 0 AND 100),
    production INTEGER DEFAULT 0 CHECK(production BETWEEN 0 AND 100),
    usage INTEGER DEFAULT 0 CHECK(usage BETWEEN 0 AND 100),
    writing INTEGER DEFAULT 0 CHECK(writing BETWEEN 0 AND 100),
    -- State machine
    mastery_state TEXT DEFAULT 'UNKNOWN',
    srs_stage INTEGER DEFAULT 0,
    next_review_at TEXT,
    pending_since TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY(user_id, language_code, sense_id)
);

CREATE INDEX IF NOT EXISTS idx_usm_word
    ON user_sense_mastery(user_id, language_code, word_id);
CREATE INDEX IF NOT EXISTS idx_usm_review
    ON user_sense_mastery(user_id, language_code, next_review_at);
CREATE INDEX IF NOT EXISTS idx_usm_state
    ON user_sense_mastery(user_id, language_code, mastery_state);


-- ============================================================
-- SENSE STAGE COMPLETION TRACKING
-- ============================================================

CREATE TABLE IF NOT EXISTS user_sense_stage_progress (
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    sense_id TEXT NOT NULL,
    word_id TEXT NOT NULL,
    stage INTEGER NOT NULL,
    review_instance_id TEXT NOT NULL,
    required_slots TEXT NOT NULL,
    passed_slots TEXT DEFAULT '[]',
    failed_attempts INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY(user_id, language_code, sense_id, review_instance_id)
);

CREATE INDEX IF NOT EXISTS idx_ussp_active
    ON user_sense_stage_progress(user_id, language_code, sense_id, stage);
CREATE INDEX IF NOT EXISTS idx_ussp_word_lookup
    ON user_sense_stage_progress(user_id, language_code, word_id, review_instance_id);


-- ============================================================
-- EXERCISE HISTORY
-- FIX #3: language_code in PK for language-safety
-- FIX #4: mission_id consistently stored
-- ============================================================

CREATE TABLE IF NOT EXISTS user_exercise_history (
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,  -- FIX #3
    exercise_id TEXT NOT NULL,
    mission_id TEXT,              -- FIX #4: always stored
    last_seen_at TEXT,
    times_seen INTEGER DEFAULT 1,
    last_correct INTEGER,         -- 0 or 1
    PRIMARY KEY(user_id, language_code, exercise_id)  -- FIX #3
);

CREATE INDEX IF NOT EXISTS idx_ueh_mission 
    ON user_exercise_history(user_id, language_code, mission_id);


-- ============================================================
-- APPEND-ONLY ATTEMPTS (Analytics)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    word_id TEXT NOT NULL,
    sense_id TEXT,                -- optional sense-level target (e.g. W00001::s01)
    exercise_id TEXT NOT NULL,
    mission_id TEXT NOT NULL,
    plan_slot_id TEXT NOT NULL,   -- FIX #1: "{review_instance_id}:{slot_key}"
    skill TEXT NOT NULL,
    is_correct INTEGER NOT NULL,
    latency_ms INTEGER,
    attempt_meta_json TEXT,      -- optional client attempt metadata (json)
    knowledge_state TEXT,        -- optional derived state: knows|learning|struggling
    knowledge_confidence REAL,   -- optional confidence score from engine
    idempotency_key TEXT,         -- For idempotent submits
    created_at TEXT DEFAULT (datetime('now')),
    -- UNIQUE on (user_id, mission_id, idempotency_key) for DB-enforced idempotency
    UNIQUE(user_id, mission_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_ua_user_word 
    ON user_attempts(user_id, language_code, word_id);
CREATE INDEX IF NOT EXISTS idx_ua_mission 
    ON user_attempts(mission_id);
CREATE INDEX IF NOT EXISTS idx_ua_skill 
    ON user_attempts(skill, is_correct);
CREATE INDEX IF NOT EXISTS idx_ua_created 
    ON user_attempts(user_id, language_code, word_id, created_at);
CREATE INDEX IF NOT EXISTS idx_ua_word_sense_created
    ON user_attempts(user_id, language_code, word_id, sense_id, created_at);
-- Index for idempotency lookups
CREATE INDEX IF NOT EXISTS idx_ua_idempotency 
    ON user_attempts(user_id, mission_id, idempotency_key);


-- ============================================================
-- ADDITIONAL SCALE INDEXES (5k-10k words)
-- ============================================================

-- Fast variant lookup by word+type+difficulty
CREATE INDEX IF NOT EXISTS idx_we_word_type_diff 
    ON word_exercises(word_id, exercise_type, difficulty, variant_index);

-- Fast history lookup for LRU selection
CREATE INDEX IF NOT EXISTS idx_ueh_lru 
    ON user_exercise_history(user_id, language_code, exercise_id, last_seen_at);

-- Fast review scheduling queries
CREATE INDEX IF NOT EXISTS idx_uwm_schedule 
    ON user_word_mastery(user_id, language_code, mastery_state, next_review_at);

-- Fast stage progress lookup
CREATE INDEX IF NOT EXISTS idx_uwsp_lookup 
    ON user_word_stage_progress(user_id, language_code, word_id, review_instance_id);


-- ============================================================
-- SCHEMA METADATA
-- ============================================================

CREATE TABLE IF NOT EXISTS schema_info (
    key TEXT PRIMARY KEY,
    value TEXT
);

INSERT OR REPLACE INTO schema_info (key, value) 
    VALUES ('version', '1.6.0');
INSERT OR REPLACE INTO schema_info (key, value) 
    VALUES ('created_at', datetime('now'));
"""


def init_database(db_path: Path) -> sqlite3.Connection:
    """Initialize or upgrade the learning path database."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    
    # Apply schema
    conn.executescript(get_schema_sql())
    _apply_runtime_migrations(conn)
    # Bootstrap sense rows for legacy concepts.meaning values.
    try:
        from .sense_store import bootstrap_concept_senses
    except ImportError:
        # Allows running this module directly: python backend/learning_path/schema.py
        from sense_store import bootstrap_concept_senses
    inserted_senses = bootstrap_concept_senses(conn)
    conn.commit()
    
    print(f"✅ Learning Path database initialized: {db_path}")
    print(f"   Schema version: {SCHEMA_VERSION}")
    if inserted_senses > 0:
        print(f"   Bootstrapped concept senses: {inserted_senses}")
    
    return conn


def _apply_runtime_migrations(conn: sqlite3.Connection) -> None:
    """Apply additive migrations for existing DBs created on older schema versions."""
    sentence_cols = {str(r[1]) for r in conn.execute("PRAGMA table_info(sentences)").fetchall()}
    # Backward compatibility: some legacy queries still select sentences.hanzi.
    if "hanzi" not in sentence_cols:
        conn.execute("ALTER TABLE sentences ADD COLUMN hanzi TEXT")
    conn.execute("UPDATE sentences SET hanzi = text WHERE COALESCE(TRIM(hanzi), '') = ''")

    columns = {str(r[1]) for r in conn.execute("PRAGMA table_info(user_attempts)").fetchall()}
    if "sense_id" not in columns:
        conn.execute("ALTER TABLE user_attempts ADD COLUMN sense_id TEXT")
    if "attempt_meta_json" not in columns:
        conn.execute("ALTER TABLE user_attempts ADD COLUMN attempt_meta_json TEXT")
    if "knowledge_state" not in columns:
        conn.execute("ALTER TABLE user_attempts ADD COLUMN knowledge_state TEXT")
    if "knowledge_confidence" not in columns:
        conn.execute("ALTER TABLE user_attempts ADD COLUMN knowledge_confidence REAL")
    # Ensure index exists even if table predates the schema SQL block.
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_ua_word_sense_created
        ON user_attempts(user_id, language_code, word_id, sense_id, created_at)
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_ua_knowledge_state
        ON user_attempts(user_id, language_code, knowledge_state, created_at)
        """
    )
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS user_sense_mastery (
            user_id TEXT NOT NULL,
            language_code TEXT NOT NULL,
            sense_id TEXT NOT NULL,
            word_id TEXT NOT NULL,
            recognition INTEGER DEFAULT 0 CHECK(recognition BETWEEN 0 AND 100),
            listening INTEGER DEFAULT 0 CHECK(listening BETWEEN 0 AND 100),
            production INTEGER DEFAULT 0 CHECK(production BETWEEN 0 AND 100),
            usage INTEGER DEFAULT 0 CHECK(usage BETWEEN 0 AND 100),
            writing INTEGER DEFAULT 0 CHECK(writing BETWEEN 0 AND 100),
            mastery_state TEXT DEFAULT 'UNKNOWN',
            srs_stage INTEGER DEFAULT 0,
            next_review_at TEXT,
            pending_since TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(user_id, language_code, sense_id)
        );
        CREATE INDEX IF NOT EXISTS idx_usm_word
            ON user_sense_mastery(user_id, language_code, word_id);
        CREATE INDEX IF NOT EXISTS idx_usm_review
            ON user_sense_mastery(user_id, language_code, next_review_at);
        CREATE INDEX IF NOT EXISTS idx_usm_state
            ON user_sense_mastery(user_id, language_code, mastery_state);

        CREATE TABLE IF NOT EXISTS user_sense_stage_progress (
            user_id TEXT NOT NULL,
            language_code TEXT NOT NULL,
            sense_id TEXT NOT NULL,
            word_id TEXT NOT NULL,
            stage INTEGER NOT NULL,
            review_instance_id TEXT NOT NULL,
            required_slots TEXT NOT NULL,
            passed_slots TEXT DEFAULT '[]',
            failed_attempts INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(user_id, language_code, sense_id, review_instance_id)
        );
        CREATE INDEX IF NOT EXISTS idx_ussp_active
            ON user_sense_stage_progress(user_id, language_code, sense_id, stage);
        CREATE INDEX IF NOT EXISTS idx_ussp_word_lookup
            ON user_sense_stage_progress(user_id, language_code, word_id, review_instance_id);
        """
    )
    # Legacy hardening: normalize numeric/blank mastery_state values into canonical strings.
    conn.executescript(
        """
        UPDATE user_word_mastery
        SET mastery_state = CASE TRIM(CAST(mastery_state AS TEXT))
            WHEN '' THEN 'UNKNOWN'
            WHEN '0' THEN 'LEARNING'
            WHEN '1' THEN 'LEARNING'
            WHEN '2' THEN 'PRACTICING'
            WHEN '3' THEN 'MASTERED_PENDING_REVIEW'
            WHEN '4' THEN 'MASTERED'
            ELSE mastery_state
        END;

        UPDATE user_sense_mastery
        SET mastery_state = CASE TRIM(CAST(mastery_state AS TEXT))
            WHEN '' THEN 'UNKNOWN'
            WHEN '0' THEN 'LEARNING'
            WHEN '1' THEN 'LEARNING'
            WHEN '2' THEN 'PRACTICING'
            WHEN '3' THEN 'MASTERED_PENDING_REVIEW'
            WHEN '4' THEN 'MASTERED'
            ELSE mastery_state
        END;
        """
    )
    uwm_columns = {
        str(r[1]) for r in conn.execute("PRAGMA table_info(user_word_mastery)").fetchall()
    }
    uwm_created_expr = "uwm.created_at" if "created_at" in uwm_columns else "datetime('now')"
    uwm_updated_expr = "uwm.updated_at" if "updated_at" in uwm_columns else "datetime('now')"
    # Backfill existing word-level mastery into sense-level mastery (primary sense).
    conn.execute(
        f"""
        INSERT OR IGNORE INTO user_sense_mastery
            (user_id, language_code, sense_id, word_id,
             recognition, listening, production, usage, writing,
             mastery_state, srs_stage, next_review_at, pending_since, created_at, updated_at)
        SELECT
            uwm.user_id,
            uwm.language_code,
            COALESCE(cs.sense_id, uwm.word_id || '::s01') AS sense_id,
            uwm.word_id,
            uwm.recognition,
            uwm.listening,
            uwm.production,
            uwm.usage,
            uwm.writing,
            uwm.mastery_state,
            uwm.srs_stage,
            uwm.next_review_at,
            uwm.pending_since,
            {uwm_created_expr},
            {uwm_updated_expr}
        FROM user_word_mastery uwm
        LEFT JOIN concept_senses cs
          ON cs.concept_id = uwm.word_id AND cs.is_primary = 1
        """
    )
    uwsp_columns = {
        str(r[1]) for r in conn.execute("PRAGMA table_info(user_word_stage_progress)").fetchall()
    }
    uwsp_created_expr = "uwsp.created_at" if "created_at" in uwsp_columns else "datetime('now')"
    uwsp_updated_expr = "uwsp.updated_at" if "updated_at" in uwsp_columns else "datetime('now')"
    # Backfill existing stage instances into sense stage progress (primary sense).
    conn.execute(
        f"""
        INSERT OR IGNORE INTO user_sense_stage_progress
            (user_id, language_code, sense_id, word_id, stage,
             review_instance_id, required_slots, passed_slots, failed_attempts,
             created_at, updated_at)
        SELECT
            uwsp.user_id,
            uwsp.language_code,
            COALESCE(cs.sense_id, uwsp.word_id || '::s01') AS sense_id,
            uwsp.word_id,
            uwsp.stage,
            uwsp.review_instance_id,
            uwsp.required_slots,
            uwsp.passed_slots,
            uwsp.failed_attempts,
            {uwsp_created_expr},
            {uwsp_updated_expr}
        FROM user_word_stage_progress uwsp
        LEFT JOIN concept_senses cs
          ON cs.concept_id = uwsp.word_id AND cs.is_primary = 1
        """
    )
    conn.execute(
        """
        INSERT OR REPLACE INTO schema_info(key, value)
        VALUES('version', ?)
        """,
        (SCHEMA_VERSION,),
    )


# ============================================================
# CONSTANTS
# ============================================================

# Mastery thresholds (raw 0-100 scores)
MASTERY_THRESHOLD = 60       # displays as 3
PRODUCTION_MIN = 40          # displays as 2
DELAYED_RECALL_HOURS = 24    # FIX #6

# Mastery states
STATE_UNKNOWN = 'UNKNOWN'
STATE_LEARNING = 'LEARNING'
STATE_PRACTICING = 'PRACTICING'
STATE_MASTERED_PENDING = 'MASTERED_PENDING_REVIEW'
STATE_MASTERED = 'MASTERED'

# SRS intervals (hours)
SRS_INTERVALS_HOURS = {
    0: 4,       # 4 hours (same-day)
    1: 24,      # 1 day
    2: 72,      # 3 days
    3: 168,     # 7 days
    4: 336,     # 14 days
    5: 504,     # 21 days
    6: 720,     # 30 days (MASTERED cycle)
}


if __name__ == "__main__":
    # Test database creation
    test_db = Path(__file__).parent / "test_learning_path.db"
    if test_db.exists():
        test_db.unlink()
    conn = init_database(test_db)
    
    # Verify tables
    tables = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).fetchall()
    print(f"\n📊 Tables created: {[t['name'] for t in tables]}")
    
    conn.close()
    test_db.unlink()
    print("\n✅ Schema test passed!")
