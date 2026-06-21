#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/4] Backend compile check"
python3 -m py_compile \
  "$ROOT_DIR/backend/api/v2/listening.py" \
  "$ROOT_DIR/backend/main.py" \
  "$ROOT_DIR/backend/learning_path/router_brain.py"

echo "[2/4] Backend listening contract tests"
(
  cd "$ROOT_DIR/backend"
  source .venv/bin/activate
  pytest -q tests/test_listening_api_contract.py
)

echo "[3/4] Flutter targeted analyze"
(
  cd "$ROOT_DIR/dragon_chinese"
  flutter analyze \
    lib/core/net/endpoints.dart \
    lib/features/course/services/listening_service.dart \
    lib/features/course/screens/listening_levels_screen.dart
)

echo "[4/4] Flutter focused tests"
(
  cd "$ROOT_DIR/dragon_chinese"
  flutter test \
    test/api_client_test.dart \
    test/skill_service_test.dart \
    test/listening_service_test.dart
)

echo "Quality gate passed."
