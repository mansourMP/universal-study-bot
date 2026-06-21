"""
ASSET AUDIT TOOL
----------------
Scans the database and asset directories to report content coverage.
Usage: python3 tools/audit_assets.py
"""

import sqlite3
import os
import json
from pathlib import Path
from collections import defaultdict

DB_PATH = "backend/learning_path.db"
ASSET_DIRS = [
    "assets/images",
    "static/images",
    "backend/content/assets" # Potential other location
]

def get_conn():
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found at {DB_PATH}")
        return None
    return sqlite3.connect(DB_PATH)

def scan_assets():
    print(f"🔍 Scanning assets in: {ASSET_DIRS}")
    found_images = set()
    for d in ASSET_DIRS:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith(('.png', '.jpg', '.webp')):
                    found_images.add(f)
                    # Also add relative path
                    found_images.add(os.path.join(d, f))
    print(f"   Found {len(found_images)} distinct image files.")
    return found_images

def analyze_db(conn, existing_images):
    c = conn.cursor()
    
    # 1. Get Concepts
    try:
        c.execute("SELECT id, text, pinyin FROM concepts")
        concepts = c.fetchall()
    except sqlite3.OperationalError:
        print("❌ 'concepts' table not found. Did you seed the DB?")
        return

    print(f"\n📊 Database Analysis ({len(concepts)} words)")
    
    # 2. Check Coverage
    stats = {
        "total": len(concepts),
        "has_sentence": 0,
        "has_image_ref": 0,
        "has_valid_image": 0,
        "has_audio_ref": 0
    }
    
    missing_images_nouns = []
    
    for (wid, text, pinyin) in concepts:
        # Check Sentences (word_sentences table)
        # We need to check if word_sentences exists first
        try:
            c.execute("SELECT COUNT(*) FROM word_sentences WHERE word_id=?", (wid,))
            s_count = c.fetchone()[0]
            if s_count > 0:
                stats["has_sentence"] += 1
        except:
            pass

        # Check Image (concepts table might have image_url? No, schema didn't have it initially)
        # But word_exercises payload might have it.
        # Let's check word_exercises
        c.execute("SELECT payload FROM word_exercises WHERE word_id=?", (wid,))
        exercises = c.fetchall()
        
        has_img = False
        has_audio = False
        
        for (payload_json,) in exercises:
            try:
                payload = json.loads(payload_json)
                if payload.get("image_url"):
                    has_img = True
                    # Validate existence
                    path = payload["image_url"]
                    # Clean path
                    clean_path = path.lstrip("/").split("/")[-1]
                    if clean_path in existing_images or os.path.exists(path.lstrip("/")):
                        stats["has_valid_image"] += 1
                if payload.get("audio") or payload.get("audio_url"):
                    has_audio = True
            except:
                pass
        
        if has_img: stats["has_image_ref"] += 1
        if has_audio: stats["has_audio_ref"] += 1
        
        # Heuristic for Noun (if pinyin doesn't start with verb verb marker... tough without POS)
        # We'll just list it if missing
        if not has_img:
            missing_images_nouns.append(f"{text} ({pinyin})")

    # 3. Report
    print("-" * 40)
    print(f"Sentences Linked: {stats['has_sentence']}/{stats['total']} ({stats['has_sentence']/stats['total']*100:.1f}%)")
    print(f"Audio Refs:       {stats['has_audio_ref']}/{stats['total']} ({stats['has_audio_ref']/stats['total']*100:.1f}%)")
    print(f"Image Refs:       {stats['has_image_ref']}/{stats['total']} ({stats['has_image_ref']/stats['total']*100:.1f}%)")
    print(f"Valid Images:     {stats['has_valid_image']}/{stats['total']} (Files actually exist)")
    print("-" * 40)
    
    if len(missing_images_nouns) > 0:
        print(f"\nExample Missing Images (Top 10):")
        for w in missing_images_nouns[:10]:
            print(f" - {w}")

if __name__ == "__main__":
    conn = get_conn()
    if conn:
        assets = scan_assets()
        analyze_db(conn, assets)
        conn.close()
