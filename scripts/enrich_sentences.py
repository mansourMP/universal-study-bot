"""
ENRICHMENT SCRIPT
-----------------
Enriches 'sentences' table with:
1. Pinyin (via pypinyin)
2. Segmentation (via jieba)
3. Word Links (mapping segments to Concept W-IDs)

Prerequisites: pip install jieba pypinyin
"""

import sqlite3
import json
import jieba
from pypinyin import pinyin, Style

DB_PATH = "backend/learning_path.db"

def get_conn():
    return sqlite3.connect(DB_PATH)

def enrich():
    conn = get_conn()
    c = conn.cursor()
    
    print("🧠 Loading Concepts for matching...")
    c.execute("SELECT text, id FROM concepts")
    # Store text -> ID mapping
    # Note: Collisions possible if multiple IDs have same text (unlikely after migration).
    concept_map = {row[0]: row[1] for row in c.fetchall()}
    print(f"   Loaded {len(concept_map)} concepts.")
    
    print("📝 Fetching Sentences...")
    c.execute("SELECT id, text, pinyin FROM sentences")
    sentences = c.fetchall()
    print(f"   Found {len(sentences)} sentences to enrich.")
    
    updates = []
    
    count = 0
    for sid, text, curr_pinyin in sentences:
        if not text:
            continue
            
        # 1. Pinyin Generation
        # Only regenerate if missing or placeholder
        if not curr_pinyin or "[AI_PINYIN_TODO]" in curr_pinyin or curr_pinyin == "":
            # pypinyin returns list of lists [['wǒ'], ['yào']]
            py_list = pinyin(text, style=Style.TONE)
            # Flatten and join
            new_pinyin = " ".join([item[0] for item in py_list])
        else:
            new_pinyin = curr_pinyin

        # 2. Segmentation
        segs = jieba.lcut(text)
        # remove punctuation/spaces from segments list for clean storage?
        # Actually, keeping punctuation is good for reconstructing structure.
        
        # 3. Word Linking
        linked_ids = []
        for seg in segs:
            if seg in concept_map:
                linked_ids.append(concept_map[seg])
            else:
                # Try handling punctuation?
                pass
                
        # Prepare Update
        updates.append((
            new_pinyin,
            json.dumps(segs, ensure_ascii=False),
            json.dumps(linked_ids),
            sid
        ))
        
        count += 1
        if count % 1000 == 0:
            print(f"   Prepared {count}...")

    print(f"💾 Committing {len(updates)} updates to database...")
    
    c.executemany("""
        UPDATE sentences 
        SET pinyin = ?, segmentation = ?, word_ids = ?
        WHERE id = ?
    """, updates)
    
    conn.commit()
    conn.close()
    print("✅ Enrichment Complete.")

if __name__ == "__main__":
    enrich()
