# CLEANUP PLAN (PROPOSAL ONLY)
No files were moved or deleted in this audit.

## A) SAFE TO ARCHIVE
- `docs/_archive_2026-02-15/**`
  - reason: archive/dump-style folder; mostly historical result shards and backups; runtime routes in `backend/main.py` do not reference this path directly (verified via backend route includes).
- Root screenshot files: `IMG_4530.PNG`, `Screenshot 2026-02-07 at 03.17.49.png`, `Screenshot 2026-02-10 at 16.53.27.png`, `View recent photos.png`
  - reason: marked `UNREFERENCED` in image scan (see `REFERENCE_MAP.md` section D).
- Any spec JSON listed as `NO REFERENCES FOUND` in `REFERENCE_MAP.md` section C
  - reason: no filename references detected in repo scan.

## B) NEEDS CONSOLIDATION
- `docs/specs/hsk1_unit_001_gold_v1.json`, `docs/specs/unit_hsk1_001_runtime_contract_v1.json`, `docs/specs/hsk1_unit_001_dynamic_pool_v1.json`
  - reason: multiple unit-001 contract/spec variants; all in active specs namespace, likely overlapping purpose (reference evidence in `REFERENCE_MAP.md` section C).
- `docs/specs/hsk1_circle_template_v1.json`, `docs/specs/hsk1_unit_circle_pack_v1.json`, `docs/specs/hsk1_master_contract_v1.json`
  - reason: multiple curriculum spec layers are all referenced by scripts; consolidation opportunity to reduce contract drift.
- Backup DB set under `backups/*.db` and `backend/*.bak*`
  - reason: large duplicate database snapshots shown in top-30 largest files (`INVENTORY.md` section 3).

## C) CORE — MUST KEEP
- `backend/main.py`
  - reason: FastAPI app creation + router mounting (`backend/main.py:957`, `backend/main.py:982-995`).
- `backend/api/v2/path.py`
  - reason: path journey/config/units/gate endpoints (`backend/api/v2/path.py:307`, `backend/api/v2/path.py:325`, `backend/api/v2/path.py:639`).
- `backend/learning_path/router_brain.py`
  - reason: mission/submit/summary APIs (`backend/learning_path/router_brain.py:1829`, `backend/learning_path/router_brain.py:2452`, `backend/learning_path/router_brain.py:2380`).
- `backend/learning_path/schema.py` and `backend/learning_path/brain_selector.py`
  - reason: DB schema + selection/gate logic used by path/brain (`backend/learning_path/schema.py:16`, `backend/learning_path/brain_selector.py:76`).
- `dragon_chinese/lib/main.dart`
  - reason: Flutter entrypoint and route setup (`dragon_chinese/lib/main.dart:15`, `dragon_chinese/lib/main.dart:54`).
- `dragon_chinese/lib/features/course/services/brain_service.dart`
  - reason: mission fetch + submit network calls (`dragon_chinese/lib/features/course/services/brain_service.dart:117`, `dragon_chinese/lib/features/course/services/brain_service.dart:182`).
- `dragon_chinese/lib/features/course/controllers/brain_exercise_controller.dart`
  - reason: mission session flow and submit orchestration (`dragon_chinese/lib/features/course/controllers/brain_exercise_controller.dart:148`, `dragon_chinese/lib/features/course/controllers/brain_exercise_controller.dart:228`).
- `dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart` + speaking widget/services
  - reason: active exercise runner and speaking path (`dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart:112`, `dragon_chinese/lib/features/course/services/speaking_recorder.dart:42`, `dragon_chinese/lib/features/course/services/speaking_evaluator.dart:11`, `dragon_chinese/lib/features/course/widgets/exercises/speaking_exercise.dart:135`).
