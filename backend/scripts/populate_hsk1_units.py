#!/usr/bin/env python3
"""
Populate HSK1 Units - organize existing concepts into 20 thematic units.

Important:
- This is a legacy thematic scaffold, not an official HSK2.0 lock script.
- The official HSK2.0 core list is 150 words for HSK1.
- This script currently maps a broader pilot set (about 200 slots).
"""

import sqlite3
import json
from pathlib import Path

# HSK1 thematic unit definitions (legacy pilot mapping into 20 units)
UNITS = [
    {
        "id": "UNIT_HSK1_001",
        "title": "Greetings & Politeness",
        "description": "Learn basic greetings and polite expressions",
        "objectives": ["Greet people", "Say thank you and sorry", "Basic courtesy"],
        "word_ids": ["W00036", "W00123", "W00135", "W00008", "W00023", "W00137", "W00069", "W00136", "W00156", "W00157"]
    },
    {
        "id": "UNIT_HSK1_002",
        "title": "Self-Introduction",
        "description": "Introduce yourself and ask about others",
        "objectives": ["Say your name", "Ask someone's name", "Basic personal info"],
        "word_ids": ["W00046", "W00117", "W00118", "W00119", "W00120", "W00121", "W00122", "W00124", "W00125", "W00126"]
    },
    {
        "id": "UNIT_HSK1_003",
        "title": "Family Members",
        "description": "Talk about family relationships",
        "objectives": ["Name family members", "Describe family", "Ask about family"],
        "word_ids": ["W00003", "W00069", "W00026", "W00070", "W00071", "W00072", "W00073", "W00074", "W00075", "W00076"]
    },
    {
        "id": "UNIT_HSK1_004",
        "title": "Numbers 1-10",
        "description": "Count from 1 to 10 in Chinese",
        "objectives": ["Count to 10", "Use numbers in context", "Basic quantities"],
        "word_ids": ["W00027", "W00002", "W00048", "W00077", "W00078", "W00079", "W00080", "W00081", "W00082", "W00083"]
    },
    {
        "id": "UNIT_HSK1_005",
        "title": "Time & Dates",
        "description": "Tell time and talk about dates",
        "objectives": ["Tell time", "Say dates", "Days of the week"],
        "word_ids": ["W00047", "W00084", "W00085", "W00086", "W00016", "W00030", "W00087", "W00088", "W00089", "W00090"]
    },
    {
        "id": "UNIT_HSK1_006",
        "title": "Food & Drinks",
        "description": "Order food and drinks",
        "objectives": ["Name common foods", "Order at restaurant", "Express preferences"],
        "word_ids": ["W00011", "W00038", "W00010", "W00091", "W00009", "W00092", "W00093", "W00094", "W00095", "W00096"]
    },
    {
        "id": "UNIT_HSK1_007",
        "title": "Shopping & Money",
        "description": "Buy things and talk about prices",
        "objectives": ["Ask prices", "Buy items", "Use money vocabulary"],
        "word_ids": ["W00024", "W00025", "W00097", "W00098", "W00099", "W00100", "W00101", "W00102", "W00103", "W00104"]
    },
    {
        "id": "UNIT_HSK1_008",
        "title": "Locations & Directions",
        "description": "Ask for and give directions",
        "objectives": ["Name places", "Ask where", "Give directions"],
        "word_ids": ["W00105", "W00106", "W00107", "W00041", "W00108", "W00109", "W00110", "W00111", "W00112", "W00113"]
    },
    {
        "id": "UNIT_HSK1_009",
        "title": "Transportation",
        "description": "Talk about how to get around",
        "objectives": ["Name vehicles", "Ask about transport", "Travel vocabulary"],
        "word_ids": ["W00012", "W00029", "W00114", "W00115", "W00116", "W00049", "W00042", "W00050", "W00051", "W00052"]
    },
    {
        "id": "UNIT_HSK1_010",
        "title": "Daily Activities",
        "description": "Describe your daily routine",
        "objectives": ["Talk about activities", "Describe routine", "Use action verbs"],
        "word_ids": ["W00033", "W00127", "W00128", "W00129", "W00130", "W00131", "W00132", "W00133", "W00134", "W00022"]
    },
    {
        "id": "UNIT_HSK1_011",
        "title": "Hobbies & Interests",
        "description": "Talk about what you like to do",
        "objectives": ["Express likes", "Talk about hobbies", "Describe interests"],
        "word_ids": ["W00001", "W00138", "W00139", "W00140", "W00141", "W00142", "W00143", "W00144", "W00145", "W00146"]
    },
    {
        "id": "UNIT_HSK1_012",
        "title": "Weather & Seasons",
        "description": "Describe weather and seasons",
        "objectives": ["Talk about weather", "Name seasons", "Describe climate"],
        "word_ids": ["W00147", "W00148", "W00149", "W00150", "W00151", "W00152", "W00153", "W00154", "W00155", "W00031"]
    },
    {
        "id": "UNIT_HSK1_013",
        "title": "School & Learning",
        "description": "Talk about school and studying",
        "objectives": ["School vocabulary", "Talk about learning", "Describe classes"],
        "word_ids": ["W00035", "W00158", "W00159", "W00160", "W00161", "W00162", "W00163", "W00164", "W00165", "W00166"]
    },
    {
        "id": "UNIT_HSK1_014",
        "title": "Work & Professions",
        "description": "Talk about jobs and work",
        "objectives": ["Name professions", "Describe work", "Ask about jobs"],
        "word_ids": ["W00167", "W00168", "W00169", "W00170", "W00171", "W00172", "W00173", "W00174", "W00175", "W00176"]
    },
    {
        "id": "UNIT_HSK1_015",
        "title": "Colors & Descriptions",
        "description": "Describe things using colors and adjectives",
        "objectives": ["Name colors", "Use adjectives", "Describe objects"],
        "word_ids": ["W00014", "W00177", "W00178", "W00179", "W00180", "W00181", "W00182", "W00183", "W00184", "W00185"]
    },
    {
        "id": "UNIT_HSK1_016",
        "title": "Body & Health",
        "description": "Talk about body parts and health",
        "objectives": ["Name body parts", "Describe health", "Express feelings"],
        "word_ids": ["W00186", "W00187", "W00188", "W00189", "W00190", "W00191", "W00192", "W00193", "W00194", "W00195"]
    },
    {
        "id": "UNIT_HSK1_017",
        "title": "Home & Furniture",
        "description": "Describe your home and furniture",
        "objectives": ["Name rooms", "Describe furniture", "Talk about home"],
        "word_ids": ["W00045", "W00196", "W00197", "W00198", "W00199", "W00200", "W00017", "W00018", "W00004", "W00020"]
    },
    {
        "id": "UNIT_HSK1_018",
        "title": "Clothing & Appearance",
        "description": "Talk about clothes and how you look",
        "objectives": ["Name clothing", "Describe appearance", "Talk about style"],
        "word_ids": ["W00201", "W00202", "W00203", "W00204", "W00205", "W00206", "W00207", "W00208", "W00209", "W00210"]
    },
    {
        "id": "UNIT_HSK1_019",
        "title": "Animals & Nature",
        "description": "Name animals and talk about nature",
        "objectives": ["Name animals", "Describe nature", "Talk about pets"],
        "word_ids": ["W00034", "W00211", "W00212", "W00213", "W00214", "W00215", "W00216", "W00217", "W00218", "W00219"]
    },
    {
        "id": "UNIT_HSK1_020",
        "title": "Review & Integration",
        "description": "Practice all HSK1 vocabulary in context",
        "objectives": ["Review all units", "Use vocabulary together", "Prepare for HSK1 test"],
        "word_ids": ["W00220", "W00221", "W00222", "W00223", "W00224", "W00225", "W00226", "W00227", "W00228", "W00229"]
    }
]


def populate_units(db_path: str):
    """Populate units and unit_concepts tables."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    
    print(f"📚 Populating HSK1 units in {db_path}...")
    
    # Check existing concepts to validate word_ids
    existing_concepts = set()
    rows = conn.execute("SELECT id FROM concepts WHERE id LIKE 'W%'").fetchall()
    existing_concepts = {row[0] for row in rows}
    print(f"   Found {len(existing_concepts)} existing concepts")
    
    units_created = 0
    mappings_created = 0
    skipped_words = []
    
    for i, unit in enumerate(UNITS, start=1):
        # Insert unit
        try:
            conn.execute("""
                INSERT OR REPLACE INTO units (id, title, unit_number, level, description, learning_objectives)
                VALUES (?, ?, ?, 'HSK1', ?, ?)
            """, [
                unit["id"],
                unit["title"],
                i,
                unit["description"],
                json.dumps(unit["objectives"])
            ])
            units_created += 1
            print(f"   ✅ Unit {i}: {unit['title']}")
        except Exception as e:
            print(f"   ❌ Failed to create unit {unit['id']}: {e}")
            continue
        
        # Insert unit_concepts mappings
        for seq, word_id in enumerate(unit["word_ids"], start=1):
            # Only add if concept exists
            if word_id in existing_concepts:
                try:
                    conn.execute("""
                        INSERT OR REPLACE INTO unit_concepts (unit_id, concept_id, sequence)
                        VALUES (?, ?, ?)
                    """, [unit["id"], word_id, seq])
                    mappings_created += 1
                except Exception as e:
                    print(f"      ⚠️  Failed to map {word_id}: {e}")
            else:
                skipped_words.append(word_id)
    
    conn.commit()
    conn.close()
    
    print(f"\n✅ Population complete!")
    print(f"   Units created: {units_created}")
    print(f"   Word mappings created: {mappings_created}")
    if skipped_words:
        print(f"   ⚠️  Skipped {len(skipped_words)} non-existent word IDs")
        print(f"      (These will be auto-filled from available concepts)")


if __name__ == "__main__":
    db_path = Path(__file__).parent.parent / "learning_path.db"
    populate_units(str(db_path))
