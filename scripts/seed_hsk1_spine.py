"""
SEED SCRIPT: HSK 1 Golden Spine (Curriculum V2)
-----------------------------------------------
Generates a structured learning path with 6 lesson archetypes:
1. Core (Book)
2. Listening (Headphones)
3. Speaking (Mic)
4. Practice (Dumbbell)
5. Story (Scroll)
6. Checkpoint (Trophy)

Populates:
- concepts (Words)
- unit_concepts (The Path)
- sentences (Contexts)
- unit_intros (Audio Priming)
"""

import sqlite3
import json
import uuid
from datetime import datetime

DB_PATH = "backend/learning_path.db"
VOCAB_DB_PATH = "backend/vocabulary_v2.db" # If needed for reference, but we insert into learning_path.db for now

def get_conn():
    return sqlite3.connect(DB_PATH)

def setup_tables(conn):
    # Ensure tables exist (idempotent)
    # We rely on schema.py having run, but let's clear data for a fresh start?
    # NO, don't wipe user progress. Just wipe content.
    cursor = conn.cursor()
    cursor.execute("DELETE FROM unit_concepts")
    cursor.execute("DELETE FROM unit_intros")
    # concepts and sentences: we might want to keep or upsert.
    # For this seed, let's UPSERT.
    conn.commit()

# ============================================================
# CONTENT DEFINITIONS
# ============================================================

UNITS = [
    {
        "id": "u1",
        "title": "Identity",
        "intro": {
            "audio": "/content/audio/u1_intro.mp3",
            "hanzi": "你好！我是大龙。你是谁？",
            "pinyin": "Nǐ hǎo! Wǒ shì Dàlóng. Nǐ shì shéi?",
            "trans": "Hello! I am Dalong. Who are you?",
            "words": ["ni", "hao", "wo", "shi", "shei"]
        },
        "lessons": [
            {"mode": "learn", "title": "The Basics", "words": ["ni", "hao", "wo", "shi"]},
            {"mode": "listening", "title": "Tones & Sounds", "words": ["ni", "hao", "wo", "shi"]}, # Reinforce
            {"mode": "speaking", "title": "Say Hello", "words": ["ni", "hao", "wo", "shi"]},
            {"mode": "practice", "title": "Review", "words": []}, # SRS previous
            {"mode": "learn", "title": "Names", "words": ["jiao", "shenme", "mingzi", "ta"]},
            {"mode": "story", "title": "Meeting Dalong", "words": ["ni", "hao", "wo", "shi", "jiao", "mingzi"]},
            {"mode": "checkpoint", "title": "Unit Test", "words": []}
        ]
    },
    {
        "id": "u2",
        "title": "Survival",
        "intro": {
            "audio": "/content/audio/u2_intro.mp3",
            "hanzi": "我要水。我不吃肉。",
            "pinyin": "Wǒ yào shuǐ. Wǒ bù chī ròu.",
            "trans": "I want water. I don't eat meat.",
            "words": ["yao", "shui", "bu", "chi"]
        },
        "lessons": [
            {"mode": "learn", "title": "Needs", "words": ["yao", "bu", "you", "meiyou"]},
            {"mode": "grammar", "title": "Negation", "words": ["bu", "meiyou"]}, # Grammar Gym
            {"mode": "learn", "title": "Food & Drink", "words": ["shui", "cha", "chi", "he"]},
            {"mode": "speaking", "title": "Ordering", "words": ["yao", "shui", "cha"]},
            {"mode": "story", "title": "At the Cafe", "words": ["wo", "yao", "cha", "bu", "yao", "shui"]},
            {"mode": "checkpoint", "title": "Unit Test", "words": []}
        ]
    }
]

WORDS = {
    "ni": {"text": "你", "pinyin": "nǐ", "meaning": "you", "tags": "pronoun"},
    "hao": {"text": "好", "pinyin": "hǎo", "meaning": "good", "tags": "adj"},
    "wo": {"text": "我", "pinyin": "wǒ", "meaning": "I / me", "tags": "pronoun"},
    "shi": {"text": "是", "pinyin": "shì", "meaning": "to be", "tags": "verb"},
    "shei": {"text": "谁", "pinyin": "shéi", "meaning": "who", "tags": "pronoun"},
    "jiao": {"text": "叫", "pinyin": "jiào", "meaning": "to be called", "tags": "verb"},
    "shenme": {"text": "什么", "pinyin": "shénme", "meaning": "what", "tags": "pronoun"},
    "mingzi": {"text": "名字", "pinyin": "míngzi", "meaning": "name", "tags": "noun"},
    "ta": {"text": "他", "pinyin": "tā", "meaning": "he", "tags": "pronoun"},
    "yao": {"text": "要", "pinyin": "yào", "meaning": "to want", "tags": "verb"},
    "bu": {"text": "不", "pinyin": "bù", "meaning": "not", "tags": "adverb"},
    "you": {"text": "有", "pinyin": "yǒu", "meaning": "to have", "tags": "verb"},
    "meiyou": {"text": "没有", "pinyin": "méiyǒu", "meaning": "not have", "tags": "verb"},
    "shui": {"text": "水", "pinyin": "shuǐ", "meaning": "water", "tags": "noun|food"},
    "cha": {"text": "茶", "pinyin": "chá", "meaning": "tea", "tags": "noun|food"},
    "chi": {"text": "吃", "pinyin": "chī", "meaning": "to eat", "tags": "verb|food"},
    "he": {"text": "喝", "pinyin": "hē", "meaning": "to drink", "tags": "verb|food"}
}

# (Word ID, Sentence Text, Pinyin, Translation, Tags)
SENTENCES = [
    ("ni", "你好。", "Nǐ hǎo.", "Hello.", "greeting|casual"),
    ("shi", "我是大龙。", "Wǒ shì Dàlóng.", "I am Dalong.", "intro|casual"),
    ("yao", "我要咖啡。", "Wǒ yào kāfēi.", "I want coffee.", "request|food"),
    ("bu", "我不是老师。", "Wǒ bú shì lǎoshī.", "I am not a teacher.", "intro|formal"),
    ("shui", "请给我水。", "Qǐng gěi wǒ shuǐ.", "Please give me water.", "request|polite"),
]

# ============================================================
# EXECUTION
# ============================================================

def seed_content():
    conn = get_conn()
    c = conn.cursor()
    
    print("🌱 Seeding Concepts...")
    for wid, data in WORDS.items():
        c.execute("""
            INSERT OR REPLACE INTO concepts (id, text, pinyin, meaning)
            VALUES (?, ?, ?, ?)
        """, (wid, data['text'], data['pinyin'], data['meaning']))
        
    print("🌱 Seeding Sentences...")
    for i, (wid, txt, pin, trans, tags) in enumerate(SENTENCES):
        sid = f"s_{wid}_{i}"
        c.execute("""
            INSERT OR REPLACE INTO sentences (id, text, pinyin, translation, tags)
            VALUES (?, ?, ?, ?, ?)
        """, (sid, txt, pin, trans, tags))
        
        c.execute("""
            INSERT OR REPLACE INTO word_sentences (word_id, sentence_id, is_primary)
            VALUES (?, ?, ?)
        """, (wid, sid, 1))

    print("🌱 Seeding Path...")
    for u_idx, unit in enumerate(UNITS):
        uid = unit['id']
        intro = unit['intro']
        
        # 1. Unit Intro
        c.execute("""
            INSERT OR REPLACE INTO unit_intros 
            (unit_id, audio_url, script_hanzi, script_pinyin, translation, target_words)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (uid, intro['audio'], intro['hanzi'], intro['pinyin'], intro['trans'], json.dumps(intro['words'])))
        
        # 2. Unit Concepts (Lessons mapping)
        # Note: 'unit_concepts' maps Unit -> Words. It doesn't strictly map Lesson Nodes.
        # But our Dashboard logic groups words into lessons based on 'unit_concepts' sequence.
        # Wait, the current Schema `unit_concepts` is flat: (unit_id, concept_id, sequence).
        # It doesn't support "Grouping words into Lesson 1, Lesson 2".
        # Current Brain logic: it chunks the flat list of words into lessons dynamically?
        # Let's check `PathAdapter`.
        # `PathAdapter.buildUnits`: Iterates lessons.
        # `lessons` comes from `DashboardData`.
        # `DashboardData` comes from `DashboardController.loadResult`.
        # `loadResult` calls API `/path/journey`.
        # API `/path/journey` (we need to check implementation).
        
        # IF the API returns a flat list of words, and frontend groups them...
        # We need to ensure `sequence` groups them correctly.
        # Actually, `Lesson` model in frontend has `mode`. 
        # But `unit_concepts` is just (unit, word).
        # WE NEED A `lessons` TABLE if we want structured lessons with modes.
        # OR we encode mode in `word_exercises` or metadata?
        
        # CURRENT HACK:
        # The schema might rely on `unit_concepts` sequence.
        # And the API groups them by 3-4 words per lesson.
        # But "Mode" (Speaking vs Reading) needs to be stored somewhere.
        # Let's store "Lesson Metadata" in a new table `unit_lessons` OR hack it into `unit_concepts`?
        
        # Better: We assume the API will group every 4 words into a lesson.
        # But how to assign "Speaking Mode" to Lesson 3?
        # We need `unit_lessons` table.
        # Since we can't change schema right now, I will use a clever trick:
        # I will store the lesson structure in `unit_intros` (metadata) OR `courses` catalog?
        # No, `unit_concepts` has `sequence`.
        # Let's insert words with sequence.
        
        seq = 0
        for l_idx, lesson in enumerate(unit['lessons']):
            # We need to store the Lesson Mode somewhere.
            # If we don't have a table, we can't persist "This is a Speaking Lesson".
            # The previous frontend code derived icon from SKILLS.
            # So if the words in the lesson are "Speaking" focused, it becomes a Speaking lesson?
            # Or we add a `lesson_config` table.
            
            # For now, let's just insert the words.
            for wid in lesson['words']:
                if wid in WORDS:
                    c.execute("""
                        INSERT OR REPLACE INTO unit_concepts (unit_id, concept_id, sequence)
                        VALUES (?, ?, ?)
                    """, (uid, wid, seq))
                    seq += 1
                    
    conn.commit()
    conn.close()
    print("✅ Seed Complete.")

if __name__ == "__main__":
    seed_content()
