# Brain Sovereignty State (Learning Path 2.0)

Date verified: 2026-02-03  
Repo: /Users/mansur/universal_study_bot org  
Raw outputs: docs/reports/proofs_run_2026-02-03.md

## Current status (verified)
- Missions/submit/gating are correct; determinism + LEARN hard contract intact (see latest proofs).
- Audio/image placeholder status: see `docs/reports/proofs_run_2026-02-03.md`.
- Manifest sync: see `docs/reports/proofs_run_2026-02-03.md`.
- Flutter tests: see `docs/reports/proofs_run_2026-02-03.md`.
- Backend tests last verified in `docs/proofs/2026-02-01.md` (rerun if needed).

## Invariants (do not regress)
- Brain Sovereignty: frontend never decides content; BrainSelector decides.
- Active Brain router: backend/learning_path/router_brain.py backed by backend/learning_path.db.
- Path API: backend/api/v2/path.py reads backend/content/paths/zh_standard.json and delegates gating to BrainSelector.get_batch_unit_status.
- Determinism: stable SQL ordering + mission-seeded stable hash for options/distractors.
- LEARN hard contract: forced_ids always covered; effective_limit >= len(forced_ids); two-pass selection.
- Submit is transactional and user_id is token-derived (summary/submit must reject mismatches).

## Verification commands (latest outputs in docs/reports/proofs_run_2026-02-03.md)
```
backend/.venv/bin/pytest backend/tests
python3 backend/scripts/verify_manifest_db_sync.py
python3 backend/scripts/report_audio_coverage.py
python3 backend/scripts/report_variant_coverage.py
python3 backend/scripts/report_image_coverage.py
python3 backend/scripts/report_sentence_coverage.py
python3 backend/scripts/report_passage_coverage.py
python3 backend/scripts/audit_tone_select.py
```

## Content Pack v1 (real assets pipeline; no Brain logic changes)
Inputs:
- assets/audio/word_{concept_id}.mp3 (primary)
- assets/images/word_{concept_id}.webp (primary)
- Optional fallback folders (TODO if used): assets/audio_v1/{concept_id}.mp3, assets/images_v1/{concept_id}.webp
- Optional manifest: assets/content_pack_v1.json
  - Schema:
  ```
  {
    "version": "v1",
    "audio": { "36": "assets/audio_v1/36.mp3" },
    "images": { "36": "assets/images_v1/36.webp" }
  }
  ```

Builders:
```
python3 backend/scripts/build_audio_pack_v1.py [--overwrite] [--strict]
python3 backend/scripts/build_image_pack_v1.py [--overwrite] [--strict]
```

Placeholder detection (release-ready = 0 placeholders):
- Audio: SHA256 == backend/static/audio/_placeholder_template.mp3
- Images: 1x1 dimensions or SHA256 == backend/static/images/_placeholder_1x1.webp

Release-ready definition:
- Missing audio IDs = 0 and placeholder_audio_count = 0
- Missing image IDs = 0 and placeholder_image_count = 0

## Next objective
Replace placeholder audio + image packs with real assets without changing Brain logic or determinism.

## Removed/Archived files (cleanup pass)
Archived to `docs/archive/` (see folder for current list):
- docs/archive/

Quarantined to `docs/quarantine/`:
- docs/quarantine/backend_archive/
- docs/quarantine/backend_backups/

Deleted (safe junk):
- __pycache__/ directories
- .pytest_cache/
- *.log, *.db-wal, *.db-shm
- .DS_Store
- committed venvs: .venv/, backend/venv/, backend/path/to/venv/

Allowlist audit tool:
- tools/audit_used_pyfiles.py (runtime import tracer from backend/main.py)

Additional quarantine (allowlist cleanup):
- docs/quarantine/backend_root_tools/ (see folder for current list)
- docs/quarantine/content_legacy/ (see folder for current list)
- docs/quarantine/db/:
  - ai_usage_ledger.db
  - progress.db
  - backend/ai_usage_ledger.db
  - backend/progress.db
  - backend/contributions.db

SYSTEM STATE: VERIFIED
