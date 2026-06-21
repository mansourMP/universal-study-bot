#!/usr/bin/env python3
import sys
import time
import subprocess
import os
import re
from pathlib import Path

# Total estimated jobs based on your shards
TOTAL_JOBS = 6500 

def count_results(dir_path):
    try:
        return len(list(Path(dir_path).glob("*.result.json")))
    except:
        return 0

def count_job_progress(log_file):
    try:
        if not os.path.exists(log_file):
            return 0
        # Fast line counting using grep
        # We count lines containing "Progress:"
        result = subprocess.run(
            ["grep", "-c", "Progress:", log_file], 
            capture_output=True, 
            text=True
        )
        return int(result.stdout.strip())
    except:
        return 0

def is_pipeline_running():
    try:
        # Check if the shell script is running
        res = subprocess.run(["pgrep", "-f", "run_deepseek_full_pipeline.sh"], capture_output=True)
        return res.returncode == 0
    except:
        return False

def main():
    log_file_path = "pipeline_visual.log"
    
    # 1. Check if running
    if is_pipeline_running():
        print("🚀 Pipeline is ALREADY RUNNING! Attaching to monitor...", flush=True)
    else:
        print("🛑 No active pipeline found. Starting NEW pipeline...", flush=True)
        env = os.environ.copy()
        if "AGENTS" not in env: 
            env["AGENTS"] = "450"
        
        # Start fresh
        log_f = open(log_file_path, "w")
        subprocess.Popen(
            ["bash", "backend/scripts/run_deepseek_full_pipeline.sh"],
            stdout=log_f,
            stderr=log_f,
            env=env,
            preexec_fn=os.setsid 
        )
        time.sleep(1) # Give it a moment

    print("📊 Monitoring (Press Ctrl+C to stop monitor, pipeline keeps running)...\n")
    print("\n" * 6) # Reserve space

    trans_dir = Path("docs/translation_results")
    sent_dir = Path("docs/sentence_results")
    trans_shards_total = 50 
    
    start_time = time.time()
    # Try to deduce start time from log file creation if attaching
    try:
        if os.path.exists(log_file_path):
            start_time = os.path.getctime(log_file_path)
    except:
        pass

    try:
        while True:
            # Check if process is still alive
            running = is_pipeline_running()
            
            # Metrics
            t_shards = count_results(trans_dir)
            s_shards = count_results(sent_dir)
            
            # Job counts from log
            jobs_done = count_job_progress(log_file_path)
            
            elapsed = int(time.time() - start_time)
            
            # Shard Progress
            t_pct = (t_shards / trans_shards_total) * 100
            
            # Job Progress (The fast mover)
            job_pct = (jobs_done / TOTAL_JOBS) * 100
            if job_pct > 100: job_pct = 100 # cap
            
            # Bars
            j_len = int(job_pct / 5)
            j_bar = "█" * j_len + "░" * (20 - j_len)
            
            t_len = int(t_pct / 5)
            t_bar = "█" * t_len + "░" * (20 - t_len)

            status_icon = "🟢 Active" if running else "🔴 Stopped"

            # Move cursor UP 6 lines
            sys.stdout.write("\033[6A") 
            
            print(f"⏳ Elapsed: {elapsed}s          ")
            print(f"🤖 Status:  {status_icon}          ")
            print(f"🚀 SPEED:   [{j_bar}] {jobs_done}/{TOTAL_JOBS} items ({job_pct:.1f}%)   ") 
            print(f"            (This number should move fast!)")
            print(f"📦 Files:   [{t_bar}] {t_shards}/{trans_shards_total} shards saved   ")
            print(f"                                    ") 
            sys.stdout.flush()
            
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n\n👋 Monitor stopped. Pipeline continues in background.")

if __name__ == "__main__":
    main()
