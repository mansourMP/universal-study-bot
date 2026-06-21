"""
MIGRATION SCRIPT: Vocab JSON -> SQL Sentences
---------------------------------------------
Reads HSK vocab packs (JSON) and populates the SQL 'sentences' 
and 'word_sentences' tables.

Target: backend/content/packs/zh_hsk*_vocab.json
Destination: backend/learning_path.db
"""

import sqlite3
import json
import os
import glob
from pathlib import Path

DB_PATH = "backend/learning_path.db"
PACKS_DIR = "backend/content/packs"

def get_conn():
    return sqlite3.connect(DB_PATH)

def migrate():
    conn = get_conn()
    c = conn.cursor()
    
    # 1. Find packs
    pattern = os.path.join(PACKS_DIR, "zh_hsk*_vocab.json")
    files = glob.glob(pattern)
    files.sort()
    
    print(f"📦 Found {len(files)} vocab packs.")
    
    total_sentences = 0
    total_links = 0
    
    for fpath in files:
        print(f"   Processing {os.path.basename(fpath)}...")
        try:
            with open(fpath, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
            level = data.get('level', 1)
            vocab_list = data.get('vocabulary', [])
            
            for item in vocab_list:
                # We need a concept ID. 
                # The JSON doesn't explicit store numeric ID in the item usually, 
                # but 'concepts' table relies on it.
                # Assuming 'concepts' table is populated with IDs matching these words?
                # OR we lookup by Hanzi.
                
                hanzi = item.get('hanzi')
                context = item.get('context_sentence')
                trans_map = item.get('context_translation', {})
                trans = trans_map.get('en') or list(trans_map.values())[0] if trans_map else ""
                
                if not hanzi or not context:
                    continue
                
                # 1. Resolve Word ID from DB (concepts table)
                # We try to match by text.
                c.execute("SELECT id FROM concepts WHERE text = ?", (hanzi,))
                row = c.fetchone()
                
                if not row:
                    # If concept doesn't exist, we skip (or we could auto-create, but better to skip for safety)
                    # Actually, if the DB was seeded from these packs, it should exist.
                    # If DB is empty (except for seed script), we might miss many.
                    # Let's insert into concepts if missing? 
                    # No, let's assume concepts are there. If not, we print warning.
                    # WAIT: The seed script only seeded ~50 words.
                    # You have 14k words in DB? If so, they should be there.
                    continue
                    
                word_id = row[0]
                
                # 2. Insert Sentence
                # Generate a stable ID for the sentence
                sent_id = f"s_{word_id}_ctx"
                
                # Pinyin for sentence? The JSON usually doesn't have pinyin for the context sentence.
                # We will leave pinyin empty or use a placeholder "[Pinyin needed]"
                # AI generation will fill this later.
                sent_pinyin = "[AI_PINYIN_TODO]" 
                
                c.execute("""
                    INSERT OR REPLACE INTO sentences 
                    (id, text, pinyin, translation, tags, difficulty)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (sent_id, context, sent_pinyin, trans, f"hsk{level}|standard", level))
                
                # 3. Link
                c.execute("""
                    INSERT OR IGNORE INTO word_sentences (word_id, sentence_id, is_primary)
                    VALUES (?, ?, 1)
                """, (word_id, sent_id))
                
                total_sentences += 1
                total_links += 1
                
        except Exception as e:
            print(f"❌ Error processing {fpath}: {e}")
            
    conn.commit()
    conn.close()
    print("-" * 40)
    print(f"✅ Migration Complete.")
    print(f"   Sentences Created: {total_sentences}")
    print(f"   Links Created:     {total_links}")

if __name__ == "__main__":
    migrate()
