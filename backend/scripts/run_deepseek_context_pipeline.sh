#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DB_PATH="${DB_PATH:-backend/learning_path.db}"
PACK_PATH="${PACK_PATH:-backend/content/packs/zh_hsk7_vocab.json}"
SHARDS_DIR="${SHARDS_DIR:-docs/context_shards_50}"
RESULTS_DIR="${RESULTS_DIR:-docs/context_results}"
SHARD_SIZE="${SHARD_SIZE:-200}"
AGENTS="${AGENTS:-50}"
LANGS_PER_CALL="${LANGS_PER_CALL:-4}"
MAX_RETRIES="${MAX_RETRIES:-6}"
PROVIDER="${PROVIDER:-deepseek}"
SOURCE_TAG="${SOURCE_TAG:-${PROVIDER}_context_batch}"

echo "[1/3] Exporting missing context jobs..."
python3 backend/scripts/export_missing_context_shards.py \
  --db "$DB_PATH" \
  --pack "$PACK_PATH" \
  --out-dir "$SHARDS_DIR" \
  --shard-size "$SHARD_SIZE"

echo "[2/3] Running context agents (provider=$PROVIDER)..."
python3 backend/scripts/run_deepseek_context_agents.py \
  --shards-dir "$SHARDS_DIR" \
  --out-dir "$RESULTS_DIR" \
  --provider "$PROVIDER" \
  --agents "$AGENTS" \
  --langs-per-call "$LANGS_PER_CALL" \
  --max-retries "$MAX_RETRIES" \
  --resume

echo "[3/3] Applying context results..."
python3 backend/scripts/apply_context_results.py \
  --db "$DB_PATH" \
  --pack "$PACK_PATH" \
  --input-glob "$RESULTS_DIR/*.result.json" \
  --apply \
  --source-tag "$SOURCE_TAG"

echo "Done."
