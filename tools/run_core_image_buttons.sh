#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 tools/hsk1_image_buttons.py \
  --catalog docs/reports/hsk_core_images_queue_v1_catalog_2026-02-17.csv \
  --naming docs/reports/hsk_core_images_queue_v1_naming_2026-02-17.csv \
  --links docs/reports/hsk_core_images_queue_v1_links_2026-02-17.csv \
  --word-map docs/reports/hsk_core_images_queue_v1_word_map_2026-02-17.csv \
  --all-categories \
  "$@"

