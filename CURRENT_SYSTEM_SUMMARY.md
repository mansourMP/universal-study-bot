# CURRENT SYSTEM SUMMARY (TRUTH FROM CODE)

Scope read for this summary:
- `backend/api/v2/path.py`
- `backend/learning_path/router_brain.py`
- `backend/learning_path/schema.py`
- `backend/learning_path/brain_selector.py`
- `dragon_chinese/lib/features/course/widgets/exercises/speaking_exercise.dart`
- `dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart`
- `dragon_chinese/lib/features/course/services/brain_service.dart`
- `dragon_chinese/lib/features/course/controllers/brain_exercise_controller.dart`
- `dragon_chinese/lib/features/course/services/speaking_evaluator.dart`
- `dragon_chinese/lib/features/course/services/speaking_recorder.dart`

## 1) Actual API Endpoints + Request/Response Structures

### `/api/v2/path/*`
- `GET /api/v2/path/config/{subject_id}` returns subject config JSON loaded from `backend/subjects/*.json` (`backend/api/v2/path.py:307`, `backend/api/v2/path.py:319`).
- `GET /api/v2/path/journey` returns `{ "nodes": [...] }` built from DB `units` + `unit_concepts` and gate status from selector (`backend/api/v2/path.py:325`, `backend/api/v2/path.py:345`, `backend/api/v2/path.py:379`, `backend/api/v2/path.py:586`).
- `GET /api/v2/path/unit/{unit_id}/passage` returns passage JSON from file (`backend/api/v2/path.py:596`, `backend/api/v2/path.py:607`).
- `GET /api/v2/path/activities/{node_id}` returns deprecated message payload (`backend/api/v2/path.py:612`).
- `GET /api/v2/path/gate/{unit_id}` returns selector gate check (`backend/api/v2/path.py:625`, `backend/api/v2/path.py:634`).
- `GET /api/v2/path/units/list` returns `{ "units": [...] }` with unlocked/progress/word counts (`backend/api/v2/path.py:639`, `backend/api/v2/path.py:714`).

### `/api/v2/brain/*`
- Mission request model: `MissionRequest` with fields `language_code`, `intent`, `limit`, `forced_ids`, `node_id`, `unit_id`, `focus_dimension`, `daily_new_target`, `target_min_seconds`, `target_max_seconds` (`backend/learning_path/router_brain.py:76`).
- Mission response model: `ExercisesResponse` with `mission_id`, `exercises[]`, `policy_version`, `metadata` (`backend/learning_path/router_brain.py:106`).
- Submit request model: `SubmitRequest` with `user_id`, `language_code`, `mission_id`, `exercise_id`, `word_id`, `sense_id`, `plan_slot_id`, `is_correct`, `latency_ms`, `idempotency_key` (`backend/learning_path/router_brain.py:113`).
- Submit response model: `SubmitResponse` includes `accepted`, idempotency/state/slot fields and `feedback_flags`; `mastery_state` coerced to string via validator (`backend/learning_path/router_brain.py:126`, `backend/learning_path/router_brain.py:142`).
- `POST /api/v2/brain/mission` implemented at `backend/learning_path/router_brain.py:1829`.
- `POST /api/v2/brain/submit` implemented at `backend/learning_path/router_brain.py:2452`.
- `GET /api/v2/brain/summary` implemented at `backend/learning_path/router_brain.py:2380`.

## 2) Learning Path Logic As Implemented
- Journey is DB-driven from `units` and `unit_concepts`, level-normalized by `_normalize_level_key` (`backend/api/v2/path.py:74`, `backend/api/v2/path.py:345`, `backend/api/v2/path.py:387`).
- Unit gate/unlock checks use `BrainSelector.get_batch_unit_status` (`backend/api/v2/path.py:380`).
- For HSK1, path lessons can be overridden by `docs/specs/hsk1_unit_001_gold_v1.json` for `UNIT_HSK1_001`, else by `docs/specs/hsk1_unit_circle_pack_v1.json` (`backend/api/v2/path.py:201`, `backend/api/v2/path.py:247`, `backend/api/v2/path.py:461`).
- HSK1 lesson status in current unit is set to `review_due` for current and future circles in pilot behavior (not strict lockstep) (`backend/api/v2/path.py:517`, `backend/api/v2/path.py:524`).
- Journey node payload includes `metadata.word_ids`, `metadata.circle_id`, and `metadata.exercise_mix` (`backend/api/v2/path.py:569`, `backend/api/v2/path.py:580`).

## 3) Brain Mission Selection Behavior
- Mission flow uses `BrainSelector` candidate selection and per-word exercise building (`backend/learning_path/router_brain.py:1841`, `backend/learning_path/router_brain.py:2029`, `backend/learning_path/router_brain.py:2060`).
- For `intent=learn` + `zh`, node/unit can resolve to HSK1 circle pack focus words and locked sense IDs (`backend/learning_path/router_brain.py:1866`, `backend/learning_path/router_brain.py:1888`, `backend/learning_path/router_brain.py:1890`).
- Effective mission size (`effective_limit`) is adapted by circle settings and learning signal (`backend/learning_path/router_brain.py:1899`, `backend/learning_path/router_brain.py:1901`).
- Adaptive budget policy is applied (daily/review/drill/learn branches) (`backend/learning_path/router_brain.py:1919`, `backend/learning_path/router_brain.py:1947`, `backend/learning_path/router_brain.py:1960`).
- For `learn`, exercises include full sequence per forced word; non-learn uses one primary + overflow (`backend/learning_path/router_brain.py:2072`, `backend/learning_path/router_brain.py:2081`).
- Duration targeting/top-up/trim logic runs for learn missions (`backend/learning_path/router_brain.py:2143`, `backend/learning_path/router_brain.py:2188`, `backend/learning_path/router_brain.py:2221`).
- Mix enforcement and ring slots are included in response metadata (`backend/learning_path/router_brain.py:2241`, `backend/learning_path/router_brain.py:2285`, `backend/learning_path/router_brain.py:2310`).

## 4) Speaking Evaluation Logic (Implemented)
- Speaking exercise types recognized: `speak_read_aloud`, `speak_prompted_reply`, `speaking` (`dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart:1167`).
- Recorder service uses hybrid strategy: on-device STT first, then local fallback recorder (`dragon_chinese/lib/features/course/services/speaking_recorder.dart:42`, `dragon_chinese/lib/features/course/services/speaking_recorder.dart:69`).
- On-device recorder calls `speech_to_text` plugin initialize/listen (`dragon_chinese/lib/features/course/services/speaking_recorder.dart:100`, `dragon_chinese/lib/features/course/services/speaking_recorder.dart:140`).
- Missing plugin is caught and returns denied (`dragon_chinese/lib/features/course/services/speaking_recorder.dart:106`).
- Local fallback creates silent WAV and returns empty transcript (`dragon_chinese/lib/features/course/services/speaking_recorder.dart:221`, `dragon_chinese/lib/features/course/services/speaking_recorder.dart:223`).
- Evaluation compares normalized transcript against expected answers, selecting best similarity (`dragon_chinese/lib/features/course/services/speaking_evaluator.dart:11`, `dragon_chinese/lib/features/course/services/speaking_evaluator.dart:35`).
- For short targets (`<=4` chars), similarity is exact-only (`dragon_chinese/lib/features/course/services/speaking_evaluator.dart:57`, `dragon_chinese/lib/features/course/services/speaking_evaluator.dart:60`).
- Rating thresholds: `clean >= 0.95`, `ok >= 0.85`, else `needsWork` (`dragon_chinese/lib/features/course/services/speaking_evaluator.dart:41`).
- Runner computes expected answers from payload `sample_answers`, prompt hanzi, or payload answer (`dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart:1245`).
- Runner submits speaking result as correct when rating is not `needsWork` (`dragon_chinese/lib/features/course/screens/brain_exercise_runner_screen.dart:377`).

## 5) Provable Inconsistencies / Edge Cases
- `BrainService.getExercises` comment says compatibility; method delegates to `startMission` and ignores `wordIds` + `missionSeed` parameters (`dragon_chinese/lib/features/course/services/brain_service.dart:125`, `dragon_chinese/lib/features/course/services/brain_service.dart:134`).
- `BrainService.submitExercise` sends both `latency_ms` and `responseTimeMs`; backend request model defines `latency_ms` only. `responseTimeMs` is extra payload (`dragon_chinese/lib/features/course/services/brain_service.dart:188`, `backend/learning_path/router_brain.py:113`).
- Frontend model comment says `/api/v2/brain/exercises` but service calls `/api/v2/brain/mission` (`dragon_chinese/lib/features/course/models/brain_models.dart:121`, `dragon_chinese/lib/features/course/services/brain_service.dart:117`).
- If on-device STT plugin is unavailable, fallback recorder can still produce duration but empty transcript; evaluator then returns `needsWork` unless manual rating override is used (`dragon_chinese/lib/features/course/services/speaking_recorder.dart:175`, `dragon_chinese/lib/features/course/services/speaking_evaluator.dart:17`).
- Schema runtime migration adds `sentences.hanzi` for backward compatibility; without executing migration against active DB, codepaths expecting `hanzi` can fail. Active migration code exists in schema initializer (`backend/learning_path/schema.py:460`).

## UNKNOWN
- Exact production deployment startup path ensuring `init_database()` always runs before all read/write routes: UNKNOWN (not fully verified in this audit).
- Any external service-side STT validation beyond local evaluator logic: UNKNOWN.
