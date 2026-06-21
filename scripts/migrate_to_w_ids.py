"""
MIGRATION: W-ID Standardization
-------------------------------
Converts all Concept IDs to 'W{05d}' format (e.g., '71' -> 'W00071').
Updates all foreign key references to maintain integrity.

Tables affected:
- concepts
- word_exercises
- word_sentences
- user_word_mastery
- unit_concepts
- sentences (ids derived from word_id)
"""

import sqlite3
import shutil

DB_PATH = "backend/learning_path.db"

def get_conn():
    return sqlite3.connect(DB_PATH)

def to_w_id(raw_id):
    """Convert raw ID to W-format."""
    # If already W format, keep it
    s_id = str(raw_id)
    if s_id.startswith('W') and s_id[1:].isdigit():
        return s_id
    
    # If integer string
    if s_id.isdigit():
        return f"W{int(s_id):05d}"
    
    # If pinyin slug (e.g. 'ni'), we need to assign a new number?
    # This is tricky. We'll mark it for special handling.
    return None

def migrate():
    print("🔒 Starting W-ID Migration...")
    conn = get_conn()
    c = conn.cursor()
    
    # Disable FK constraints temporarily to allow updates
    c.execute("PRAGMA foreign_keys = OFF")
    
    # 1. Fetch all concepts
    c.execute("SELECT id, text FROM concepts")
    all_concepts = c.fetchall()
    
    # map old_id -> new_id
    id_map = {}
    
    # For slug IDs ('ni'), we need to find the next available number
    # Find max existing integer ID
    max_num = 0
    for old_id, _ in all_concepts:
        if str(old_id).isdigit():
            max_num = max(max_num, int(old_id))
    
    next_num = max_num + 1
    
    for old_id, text in all_concepts:
        new_id = to_w_id(old_id)
        
        if new_id is None:
            # It was a slug like 'ni'
            # Check if we already have a W-ID for this text?
            # (Duplicate detection)
            # Actually, let's just assign a new number for safety
            new_id = f"W{next_num:05d}"
            next_num += 1
            
        if new_id != str(old_id):
            id_map[str(old_id)] = new_id

    print(f"📝 Remapping {len(id_map)} IDs...")
    
    # 2. Update Tables
    tables_cols = [
        ('concepts', 'id'),
        ('word_exercises', 'word_id'),
        ('word_sentences', 'word_id'),
        ('user_word_mastery', 'word_id'),
        ('unit_concepts', 'concept_id'),
        ('user_word_stage_progress', 'word_id'),
        ('user_attempts', 'word_id')
    ]
    
    # We must handle 'concepts' last or carefully to avoid PK collisions
    # Strategy: Update referencing tables first. Then update 'concepts'.
    
    count = 0
    for old, new in id_map.items():
        # Referencing tables
        for table, col in tables_cols:
            if table == 'concepts': continue
            c.execute(f"UPDATE {table} SET {col} = ? WHERE {col} = ?", (new, old))
            
        # Sentences table (IDs contain word_id often, e.g. s_71_ctx)
        # We should update sentence IDs too for consistency?
        # s_71_ctx -> s_W00071_ctx
        c.execute(f"SELECT id FROM sentences WHERE id LIKE ?", (f"%_{old}_%",))
        s_rows = c.fetchall()
        for (s_id,) in s_rows:
            new_s_id = s_id.replace(f"_{old}_", f"_{new}_")
            c.execute("UPDATE sentences SET id = ? WHERE id = ?", (new_s_id, s_id))
            # Also update the link table reference
            c.execute("UPDATE word_sentences SET sentence_id = ? WHERE sentence_id = ?", (new_s_id, s_id))

        count += 1
        if count % 1000 == 0:
            print(f"   Processed {count}...")

    # Finally update concepts table
    # We might have collisions if 'ni' maps to 'W00071' which implies '71'
    # But '71' mapped to 'W00071' too.
    # So 'ni' and '71' merge?
    # No, 'ni' gets a NEW number in my logic above.
    # But wait, if 'ni' is "你" and '71' is "你", we SHOULD merge them.
    # MERGE LOGIC:
    # Group by text.
    
    print("🧩 Resolving Merges (Duplicates)...")
    text_groups = {} # text -> list of (old_id, new_id)
    for old_id, text in all_concepts:
        if text not in text_groups: text_groups[text] = []
        # Calculate what the target WOULD be
        proposed = id_map.get(str(old_id), str(old_id))
        text_groups[text].append((str(old_id), proposed))
        
    final_updates = {} # old -> final_new
    
    for text, pairs in text_groups.items():
        # Pick the "best" ID as the winner.
        # Winner is the one that was originally numeric (e.g. W00071)
        winner = None
        for _, new in pairs:
            if new.startswith('W'):
                winner = new
                break
        
        if not winner:
             # Just pick the first one
             winner = pairs[0][1]
             
        for old, _ in pairs:
            if old != winner:
                final_updates[old] = winner

    print(f"📉 Reduced to {len(final_updates)} definitive re-maps (handling duplicates).")
    
    # Execute definitive updates
    count = 0
    for old, new in final_updates.items():
        if old == new: continue
        
        # References
        for table, col in tables_cols:
            if table == 'concepts': continue
            c.execute(f"UPDATE OR IGNORE {table} SET {col} = ? WHERE {col} = ?", (new, old))
            # Delete orphaned rows that couldn't update due to collision
            c.execute(f"DELETE FROM {table} WHERE {col} = ?", (old,))
            
        # Concept table
        # Insert new if not exists, delete old
        # Fetch old data
        c.execute("SELECT * FROM concepts WHERE id = ?", (old,))
        row = c.fetchone()
        if row:
            # We want to keep the record but move it to new ID.
            # Check if winner exists
            c.execute("SELECT id FROM concepts WHERE id = ?", (new,))
            winner_exists = c.fetchone()
            
            if not winner_exists:
                c.execute("UPDATE concepts SET id = ? WHERE id = ?", (new, old))
            else:
                # Merge: Delete old (since new exists and represents same word)
                c.execute("DELETE FROM concepts WHERE id = ?", (old,))

        count += 1
        if count % 1000 == 0:
            print(f"   Merged {count}...")

    conn.commit()
    c.execute("PRAGMA foreign_keys = ON")
    conn.close()
    print("✅ W-ID Migration Complete.")

if __name__ == "__main__":
    migrate()
