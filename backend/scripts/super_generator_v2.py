#!/usr/bin/env python3
"""
SUPER GENERATOR V2
------------------
- 50 Agents (Strict)
- Queue-based (No file I/O blocking)
- Parallel Language Chunks (Fast)
- SQLite Storage (Safe & Fast)
- Matrix Logging (Visual)
"""

import asyncio
import json
import os
import sqlite3
import time
import random
from pathlib import Path
from typing import List, Dict, Any

# CONFIG
AGENTS = 200
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")
DB_PATH = "fast_results.db"

# --- NETWORK HELPERS ---
import urllib.request as urlrequest
import urllib.error as urlerror

def _http_post_json(url, headers, payload, timeout=60):
    body = json.dumps(payload).encode("utf-8")
    req = urlrequest.Request(url, data=body, headers=headers, method="POST")
    try:
        with urlrequest.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        raise RuntimeError(str(e))

async def call_deepseek(messages, max_tokens=420):
    payload = {
        "model": "deepseek-chat",
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.1
    }
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json"
    }
    return await asyncio.to_thread(_http_post_json, f"{DEEPSEEK_BASE_URL}/chat/completions", headers, payload)

# --- WORKER LOGIC ---

async def process_job(job: Dict[str, Any], semaphore: asyncio.Semaphore):
    cid = job["concept_id"]
    hanzi = job["hanzi"]
    
    # 1. Build Chunks (36 langs -> 9 chunks of 4)
    missing_langs = job.get("missing_langs", [])
    chunks = [missing_langs[i:i+4] for i in range(0, len(missing_langs), 4)]
    
    tasks = []
    
    # Log ONCE
    print(f"🚀 [Agent {id(asyncio.current_task()) % 50}] Generating {hanzi} ({cid})...", flush=True)

    for chunk in chunks:
        tasks.append(process_chunk(chunk, job, semaphore))
    
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    final_translations = {}
    for res in results:
        if isinstance(res, dict):
            final_translations.update(res)
            
    return final_translations

async def process_chunk(chunk, job, semaphore):
    # Retry loop
    for attempt in range(3):
        try:
            async with semaphore:
                prompt = build_prompt(job, chunk)
                resp = await call_deepseek(prompt)
                
            content = resp["choices"][0]["message"]["content"]
            # Parse JSON
            try:
                data = json.loads(content)
                return data.get("translations", {})
            except:
                # Try to find JSON in text
                s = content.find("{")
                e = content.rfind("}")
                if s >= 0 and e > s:
                    return json.loads(content[s:e+1]).get("translations", {})
                raise ValueError("Bad JSON")
                
        except Exception as e:
            await asyncio.sleep(1 + attempt)
    return {} # Failed after retries

def build_prompt(job, langs):
    return [
        {"role": "system", "content": "Return valid JSON only."},
        {"role": "user", "content": f"Translate concept {job['hanzi']} ({job['concept_id']}) to {langs}. JSON format: {{ \"translations\": {{ \"code\": \"text\" }} }}"}
    ]

# --- MAIN CONTROLLER ---

async def worker(queue: asyncio.Queue, db_queue: asyncio.Queue, semaphore: asyncio.Semaphore):
    while True:
        job = await queue.get()
        try:
            translations = await process_job(job, semaphore)
            if translations:
                # Send to DB Writer
                await db_queue.put((job["concept_id"], job["hanzi"], json.dumps(translations)))
                print(f"✅ [Completed] {job['hanzi']}", flush=True)
            else:
                print(f"❌ [Failed] {job['hanzi']}", flush=True)
        except Exception as e:
            print(f"❌ [Error] {job['hanzi']}: {e}", flush=True)
        finally:
            queue.task_done()

async def db_writer(db_queue: asyncio.Queue):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    while True:
        item = await db_queue.get()
        try:
            c.execute("INSERT OR REPLACE INTO translations (concept_id, hanzi, data) VALUES (?, ?, ?)", item)
            conn.commit()
            # print("💾 Saved.", flush=True)
        except Exception as e:
            print(f"DB Error: {e}")
        finally:
            db_queue.task_done()

async def main():
    # 1. Load Jobs
    print("📂 Loading jobs from shards...", flush=True)
    jobs = []
    shards_dir = Path("docs/translation_shards_50")
    for f in shards_dir.glob("localization_shard_*.json"):
        data = json.loads(f.read_text())
        jobs.extend(data["jobs"])
    
    # Filter done
    conn = sqlite3.connect(DB_PATH)
    # Treat only fully-complete rows as "done".
    # Partial rows (<36 languages) stay in todo and will be retried on rerun.
    done_ids = {
        row[0]
        for row in conn.execute(
            """
            SELECT concept_id
            FROM translations
            WHERE (SELECT COUNT(*) FROM json_each(data)) >= 36
            """
        )
    }
    conn.close()
    
    todo = [j for j in jobs if j["concept_id"] not in done_ids]
    print(f"📊 Total: {len(jobs)}, Done: {len(done_ids)}, Todo: {len(todo)}")
    
    if not todo:
        print("🎉 All done!")
        return

    # 2. Setup Queues
    queue = asyncio.Queue()
    for j in todo:
        queue.put_nowait(j)
        
    db_queue = asyncio.Queue()
    
    # 3. Launch 50 Agents
    semaphore = asyncio.Semaphore(AGENTS * 9) # Allow 9 calls per agent (parallel chunks)
    
    workers = []
    for _ in range(AGENTS):
        workers.append(asyncio.create_task(worker(queue, db_queue, semaphore)))
        
    # Launch 1 DB Writer
    asyncio.create_task(db_writer(db_queue))
    
    print(f"🔥 LAUNCHING {AGENTS} AGENTS...", flush=True)
    await queue.join()
    print("🎉 Queue empty! Waiting for DB...", flush=True)
    await db_queue.join()
    print("✅ DONE.")

if __name__ == "__main__":
    asyncio.run(main())
