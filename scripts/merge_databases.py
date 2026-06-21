"""
DATABASE MERGE SCRIPT
---------------------
Merges content from 'vocabulary_v2.db' (Legacy Master) into 'learning_path.db' (Active Brain).

Process:
1. Import all CONCEPTS (Words) from v2 that are missing in Learning Path.
2. Import all SENTENCES_V2 (Trios) from v2, normalizing them into the new schema.
3. Link them in 'word_sentences'.

This unifies the databases without breaking existing seed data.
"""

import sqlite3
import json
import os

SOURCE_DB = "backend/vocabulary_v2.db"
TARGET_DB = "backend/learning_path.db"

def get_conns():
    if not os.path.exists(SOURCE_DB):
        print(f"❌ Source DB not found: {SOURCE_DB}")
        return None, None
    if not os.path.exists(TARGET_DB):
        print(f"❌ Target DB not found: {TARGET_DB}")
        return None, None
        
    src = sqlite3.connect(SOURCE_DB)
    tgt = sqlite3.connect(TARGET_DB)
    return src, tgt

def merge():
    src, tgt = get_conns()
    if not src or not tgt:
        return

    # Helper cursors
    s_cur = src.cursor()
    t_cur = tgt.cursor()
    
    print("🚀 Starting Database Merge...")
    
    # =========================================================
    # 1. BUILD ID MAP (Hanzi -> Target ID)
    # =========================================================
    print("   Building ID Map...")
    t_cur.execute("SELECT text, id FROM concepts")
    hanzi_to_id = {row[0]: row[1] for row in t_cur.fetchall()}
    print(f"   Target DB currently has {len(hanzi_to_id)} concepts.")
    
    # =========================================================
    # 2. IMPORT CONCEPTS
    # =========================================================
    print("📦 Importing Concepts from Vocabulary V2...")
    # vocabulary_v2.concepts: id, word, pronunciation, pos...
    s_cur.execute("SELECT id, word, pronunciation, pos FROM concepts")
    v2_concepts = s_cur.fetchall()
    
    added_concepts = 0
    for v2_id, word, pinyin, pos in v2_concepts:
        if word not in hanzi_to_id:
            # New word! Import it.
            # We use the v2 integer ID as the string ID in target for stability
            new_id = str(v2_id) 
            
            # Insert
            # schema: id, text, pinyin, meaning (we don't have meaning in this query, fetching translations is complex)
            # Let's try to get meaning if possible, or leave null for now
            # For speed, we skip meaning join for now, or fetch it?
            # Let's fetch translations from v2.translations table?
            # It's expensive to do per row. 
            # We will insert basics.
            
            t_cur.execute("INSERT INTO concepts (id, text, pinyin) VALUES (?, ?, ?)", 
                          (new_id, word, pinyin))
            
            hanzi_to_id[word] = new_id
            added_concepts += 1
            
    print(f"   ✅ Imported {added_concepts} new concepts.")
    
    # =========================================================
    # 3. IMPORT SENTENCES (The Trios)
    # =========================================================
    print("📦 Importing Sentences (Trios)...")
    # vocabulary_v2.sentences_v2: word_id, text_zh, pinyin, text_en, style
    # We join with concepts in source to get the Word text, so we can map to Target ID
    s_cur.execute("""
        SELECT c.word, s.text_zh, s.pinyin, s.text_en, s.style, s.id
        FROM sentences_v2 s
        JOIN concepts c ON s.word_id = c.id
    """)
    rows = s_cur.fetchall()
    
    added_sentences = 0
    
    for word_text, zh, pin, en, style, orig_id in rows:
        if word_text not in hanzi_to_id:
            continue # Should not happen given step 2
            
        target_word_id = hanzi_to_id[word_text]
        
        # Generate Target Sentence ID
        # style: 'core', 'dialogue', 'passage'?
        # Let's map style to tags
        tags = "imported"
        if style == 'core': tags += "|hsk_core|standard"
        elif style == 'dialogue': tags += "|dialogue|spoken"
        elif style == 'passage': tags += "|story|literary"
        else: tags += f"|{style}"
        
        target_sent_id = f"v2_{orig_id}"
        
        # Insert Sentence
        t_cur.execute("""
            INSERT OR REPLACE INTO sentences (id, text, pinyin, translation, tags)
            VALUES (?, ?, ?, ?, ?)
        """, (target_sent_id, zh, pin or "", en, tags))
        
        # Insert Link
        t_cur.execute("""
            INSERT OR IGNORE INTO word_sentences (word_id, sentence_id, is_primary)
            VALUES (?, ?, ?)
        """, (target_word_id, target_sent_id, 1 if style == 'core' else 0))
        
        added_sentences += 1
        
    tgt.commit()
    print(f"   ✅ Imported {added_sentences} sentences.")
    
    src.close()
    tgt.close()
    print("🚀 Merge Complete.")

if __name__ == "__main__":
    merge()
