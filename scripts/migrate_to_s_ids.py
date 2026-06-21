"""
MIGRATION: S-ID Standardization
-------------------------------
Converts Sentence IDs to 'S{05d}' format.
Updates:
- sentences (PK)
- word_sentences (FK)
- word_exercises (JSON Payload - sentence_id)
"""

import sqlite3
import json

DB_PATH = "backend/learning_path.db"

def get_conn():
    return sqlite3.connect(DB_PATH)

def migrate():
    print("🔒 Starting S-ID Migration...")
    conn = get_conn()
    c = conn.cursor()
    c.execute("PRAGMA foreign_keys = OFF")
    
    # 1. Fetch all sentences
    c.execute("SELECT id FROM sentences ORDER BY created_at, id")
    rows = c.fetchall()
    
    # Map old -> new
    id_map = {}
    
    # Find max existing S-ID to avoid collision if mixed
    next_num = 1
    
    # Check if we already have S-IDs
    for (sid,) in rows:
        if sid.startswith("S") and sid[1:].isdigit():
            val = int(sid[1:])
            if val >= next_num:
                next_num = val + 1
    
    print(f"   Starting sequence at S{next_num:05d}...")
    
    remap_count = 0
    for (old_id,) in rows:
        # Skip if already correct format
        if old_id.startswith("S") and old_id[1:].isdigit():
            continue
            
        new_id = f"S{next_num:05d}"
        id_map[old_id] = new_id
        next_num += 1
        remap_count += 1

    print(f"📝 Remapping {len(id_map)} Sentences...")
    
    # 2. Update DB
    count = 0
    for old, new in id_map.items():
        # A. Update 'sentences' table
        # We use INSERT + DELETE to handle PK change safely or UPDATE if supported
        # SQLite supports updating PK if FKs are off
        c.execute("UPDATE sentences SET id = ? WHERE id = ?", (new, old))
        
        # B. Update 'word_sentences' link table
        c.execute("UPDATE word_sentences SET sentence_id = ? WHERE sentence_id = ?", (new, old))
        
        # C. Update 'sentence_audio' (if we had it, we don't have it populated yet, but good practice)
        # c.execute("UPDATE sentence_audio SET sentence_id = ? WHERE sentence_id = ?", (new, old))
        
        # D. Update 'sentence_tags' (if we migrated to it)
        # c.execute("UPDATE sentence_tags SET sentence_id = ? WHERE sentence_id = ?", (new, old))
        
        count += 1
        if count % 1000 == 0:
            print(f"   Processed {count}...")

    # 3. Scan JSON Payloads (Expensive but necessary)
    print("🕵️ Scanning JSON Payloads for references...")
    c.execute("SELECT id, payload FROM word_exercises")
    exercises = c.fetchall()
    
    payload_updates = 0
    for eid, payload_json in exercises:
        try:
            payload = json.loads(payload_json)
            changed = False
            
            # Check for 'sentence_id' key
            if "sentence_id" in payload:
                curr = payload["sentence_id"]
                if curr in id_map:
                    payload["sentence_id"] = id_map[curr]
                    changed = True
            
            # Check for 'context_id' or other keys?
            
            if changed:
                new_json = json.dumps(payload)
                c.execute("UPDATE word_exercises SET payload = ? WHERE id = ?", (new_json, eid))
                payload_updates += 1
                
        except:
            continue

    conn.commit()
    c.execute("PRAGMA foreign_keys = ON")
    conn.close()
    
    print(f"✅ S-ID Migration Complete.")
    print(f"   Sentences Renamed: {count}")
    print(f"   Payloads Updated:  {payload_updates}")

if __name__ == "__main__":
    migrate()
