"""
Learning Path 2.0 - Package Init
Technical Memo v1.1
"""

from .schema import (
    init_database,
    get_schema_sql,
    SCHEMA_VERSION,
    MASTERY_THRESHOLD,
    PRODUCTION_MIN,
    DELAYED_RECALL_HOURS,
    STATE_UNKNOWN,
    STATE_LEARNING,
    STATE_PRACTICING,
    STATE_MASTERED_PENDING,
    STATE_MASTERED,
    SRS_INTERVALS_HOURS,
)

from .srs_plan import (
    MasteryVector,
    get_srs_plan,
    SKILL_TO_TYPES,
    FOCUS_TO_SKILL,
    make_slot_key,
    make_plan_slot_id,
    parse_plan_slot_id,
    get_interval_hours,
)

from .skill_updates import (
    compute_skill_delta,
    update_skill_score,
    is_mastery_criteria_met,
    can_transition_to_mastered,
    compute_next_state,
    get_mastery_vector,
)

from .stage_completion import (
    create_review_instance,
    get_active_review_instance,
    record_slot_attempt,
    process_exercise_submit,
)

from .router_brain import router as brain_router

from .brain_selector import BrainSelector, SelectedExercise, create_selector


__all__ = [
    # Schema
    'init_database',
    'get_schema_sql',
    'SCHEMA_VERSION',
    'MASTERY_THRESHOLD',
    'PRODUCTION_MIN',
    'DELAYED_RECALL_HOURS',
    'STATE_UNKNOWN',
    'STATE_LEARNING',
    'STATE_PRACTICING',
    'STATE_MASTERED_PENDING',
    'STATE_MASTERED',
    'SRS_INTERVALS_HOURS',
    # SRS Plan
    'MasteryVector',
    'get_srs_plan',
    'SKILL_TO_TYPES',
    'FOCUS_TO_SKILL',
    'make_slot_key',
    'make_plan_slot_id',
    'parse_plan_slot_id',
    'get_interval_hours',
    # Skill Updates
    'compute_skill_delta',
    'update_skill_score',
    'is_mastery_criteria_met',
    'can_transition_to_mastered',
    'compute_next_state',
    'get_mastery_vector',
    # Stage Completion
    'create_review_instance',
    'get_active_review_instance',
    'record_slot_attempt',
    'process_exercise_submit',
]
