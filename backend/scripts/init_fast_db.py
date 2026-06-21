import sqlite3

def init_db():
    conn = sqlite3.connect("fast_results.db")
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS translations (
            concept_id TEXT PRIMARY KEY,
            hanzi TEXT,
            data JSON
        )
    """)
    conn.commit()
    conn.close()

if __name__ == "__main__":
    init_db()
