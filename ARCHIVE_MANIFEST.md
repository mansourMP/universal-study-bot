# ARCHIVE MANIFEST
Date: 2026-02-15
Method: safe archive pass (no deletion, no code refactor)

## Moved Files

1. `IMG_4530.PNG`
- moved to: `docs/_archive_2026-02-15_pass2/root_screenshots/IMG_4530.PNG`
- reason: unreferenced screenshot
- evidence: `CLEANUP_PLAN.md:7`, `REFERENCE_MAP.md:126`

2. `Screenshot 2026-02-07 at 03.17.49.png`
- moved to: `docs/_archive_2026-02-15_pass2/root_screenshots/Screenshot 2026-02-07 at 03.17.49.png`
- reason: unreferenced screenshot
- evidence: `CLEANUP_PLAN.md:7`, `REFERENCE_MAP.md:127`

3. `Screenshot 2026-02-10 at 16.53.27.png`
- moved to: `docs/_archive_2026-02-15_pass2/root_screenshots/Screenshot 2026-02-10 at 16.53.27.png`
- reason: unreferenced screenshot
- evidence: `CLEANUP_PLAN.md:7`, `REFERENCE_MAP.md:128`

4. `View recent photos.png`
- moved to: `docs/_archive_2026-02-15_pass2/root_screenshots/View recent photos.png`
- reason: unreferenced screenshot
- evidence: `CLEANUP_PLAN.md:7`, `REFERENCE_MAP.md:129`

5. `docs/specs/unit_hsk1_001_runtime_contract_v1.json`
- moved to: `docs/_archive_2026-02-15_pass2/specs/unit_hsk1_001_runtime_contract_v1.json`
- reason: spec file with no repo references
- evidence: `REFERENCE_MAP.md:116`, `REFERENCE_MAP.md:117`, `CLEANUP_PLAN.md:9`

## Not Moved In This Pass (intentional)

- `docs/specs/hsk1_unit_001_gold_v1.json`
- `docs/specs/hsk1_unit_001_dynamic_pool_v1.json`
- `docs/specs/hsk1_unit_circle_pack_v1.json`
- `docs/specs/hsk1_master_contract_v1.json`
- `docs/specs/hsk1_circle_template_v1.json`

Reason:
- These are referenced by scripts/runtime and were kept for safety.
- evidence: `REFERENCE_MAP.md` section C shows references for these files.

## Core Runtime Protected (not touched)

- `backend/main.py`
- `backend/api/v2/path.py`
- `backend/learning_path/router_brain.py`
- `backend/learning_path/schema.py`
- `backend/learning_path/brain_selector.py`
- `dragon_chinese/lib/main.dart`
- `dragon_chinese/lib/features/course/services/brain_service.dart`
- `dragon_chinese/lib/features/course/controllers/brain_exercise_controller.dart`
- `dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart`
- `dragon_chinese/lib/features/course/services/speaking_recorder.dart`
- `dragon_chinese/lib/features/course/services/speaking_evaluator.dart`
- `dragon_chinese/lib/features/course/widgets/exercises/speaking_exercise.dart`

evidence: `CLEANUP_PLAN.md:20`

## Pass 3 (2026-02-15): Moved Legacy Docs

6. `docs/AUDIT_AI_CHANGES_2026-02-04.md`
- moved to: `docs/_archive_2026-02-15_pass3/docs_legacy/AUDIT_AI_CHANGES_2026-02-04.md`
- reason: legacy dated audit doc; no active references after excluding generated inventory/reports
- evidence: local reference scan (2026-02-15) returned 0 references outside generated audit files

7. `docs/CHANGE_DOSSIER.md`
- moved to: `docs/_archive_2026-02-15_pass3/docs_legacy/CHANGE_DOSSIER.md`
- reason: legacy change note doc; no active references after excluding generated inventory/reports
- evidence: local reference scan (2026-02-15) returned 0 references outside generated audit files

8. `docs/NEXT_MILESTONE_HSK1.md`
- moved to: `docs/_archive_2026-02-15_pass3/docs_legacy/NEXT_MILESTONE_HSK1.md`
- reason: legacy planning doc; no active references after excluding generated inventory/reports
- evidence: local reference scan (2026-02-15) returned 0 references outside generated audit files

9. `docs/NETWORK_RESILIENCE_PR.md`
- moved to: `docs/_archive_2026-02-15_pass3/docs_legacy/NETWORK_RESILIENCE_PR.md`
- reason: legacy PR note doc; only referenced by a moved legacy audit doc
- evidence: local reference scan (2026-02-15) showed only `docs/AUDIT_AI_CHANGES_2026-02-04.md` reference
