#!/usr/bin/env bash
set -euo pipefail

# One-command DeepSeek pipeline:
# 1) translation agents -> translation results
# 2) apply translation results to DB
# 3) sentence agents -> sentence results
# 4) apply sentence results to DB
# 5) print pending summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${ENV_FILE:-backend/.env}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  echo "Set ENV_FILE=/path/to/.env and retry."
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "ERROR: DEEPSEEK_API_KEY is missing after loading ${ENV_FILE}"
  exit 1
fi

AGENTS="${AGENTS:-50}"
LANGS_PER_CALL="${LANGS_PER_CALL:-4}"
MAX_RETRIES="${MAX_RETRIES:-6}"
TRANSLATION_SHARDS_DIR="${TRANSLATION_SHARDS_DIR:-docs/translation_shards_50}"
SENTENCE_SHARDS_DIR="${SENTENCE_SHARDS_DIR:-docs/sentence_shards_50}"
TRANSLATION_RESULTS_DIR="${TRANSLATION_RESULTS_DIR:-docs/translation_results}"
SENTENCE_RESULTS_DIR="${SENTENCE_RESULTS_DIR:-docs/sentence_results}"

mkdir -p "${TRANSLATION_RESULTS_DIR}" "${SENTENCE_RESULTS_DIR}"

echo "[1/5] Running DeepSeek translation agents..."
python3 -u backend/scripts/run_deepseek_translation_agents.py \
  --shards-dir "${TRANSLATION_SHARDS_DIR}" \
  --out-dir "${TRANSLATION_RESULTS_DIR}" \
  --agents "${AGENTS}" \
  --langs-per-call "${LANGS_PER_CALL}" \
  --max-retries "${MAX_RETRIES}" \
  --resume

echo "[2/5] Applying translation results to DB..."
python3 backend/scripts/apply_localization_results.py \
  --db backend/learning_path.db \
  --input-glob "${TRANSLATION_RESULTS_DIR}/*.result.json" \
  --apply \
  --source-tag "deepseek_agents_translation"

echo "[3/5] Running DeepSeek sentence agents..."
python3 backend/scripts/run_deepseek_sentence_agents.py \
  --shards-dir "${SENTENCE_SHARDS_DIR}" \
  --out-dir "${SENTENCE_RESULTS_DIR}" \
  --agents "${AGENTS}" \
  --max-retries "${MAX_RETRIES}" \
  --resume

echo "[4/5] Applying sentence results to DB..."
python3 backend/scripts/apply_sentence_results.py \
  --db backend/learning_path.db \
  --input-glob "${SENTENCE_RESULTS_DIR}/*.result.json" \
  --apply \
  --source-tag "deepseek_agents_sentences" \
  --max-per-word 3

echo "[5/5] Verifying pending localization jobs..."
python3 backend/scripts/translate_hsk3_localizations.py --db backend/learning_path.db

echo "DONE"
