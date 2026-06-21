You’re already very close to the “future-proof” shape you want. The big unlock is to make the **black box** (your structural formula) *not* be “a bunch of exercise types”, but a **small set of stable interaction templates** fed by a **content payload that is domain-agnostic** (language, math, history, etc.). Then your TikTok-style feed, Duolingo-style practice, and Khan-style lessons all become *different containers* around the same core objects.

Below are the recommendations I’d implement (or refactor toward) if the goal is: **cross-subject + cross-language + future video/images + scalable generation**.

---

## 1) The most important design change: split “exercise type” into Template vs Variant

Right now your `exercise_type` is doing two jobs at once:

* **(A) UI interaction template**: multiple choice, arrange tokens, match pairs, speak, passage+questions…
* **(B) Pedagogical intent / variant**: meaning_select vs character_select vs pinyin_select (these are “what skill are we testing?”)

To scale across subjects, you want:

### ✅ `template_id` (stable, small set)

This is what your Flutter runner maps to widgets and validators.

Examples:

* `select_one`
* `select_many` (future)
* `arrange`
* `match_pairs`
* `passage_qa`
* `free_text` (future)
* `speak`
* `draw_write` (future)
* `interactive_sim` (future)

### ✅ `variant_id` (infinite, content-driven)

This is what “meaning_select / pinyin_select / dictation_select” becomes.

Examples:

* language variants: `meaning_select`, `character_select`, `pinyin_select`, `dictation_select`
* math variants: `concept_check`, `unit_select`, `graph_select`
* history variants: `cause_effect_select`, `timeline_order`
* science variants: `label_diagram`, `hypothesis_select`

**Why this matters:**
You keep your runner small and stable (templates), while you can invent unlimited “exercise types” as variants without touching UI.

---

## 2) Build a single canonical “ExerciseItem” schema that is multi-modal

You already have “input content item” and “payload”. Take the next step: make the payload a **list of stimulus atoms**, plus a response spec, plus an evaluation spec.

### Recommended canonical shape (ExerciseItem v2)

```json
{
  "id": "ex_123",
  "schema_version": 2,

  "template_id": "select_one",
  "variant_id": "meaning_select",

  "objective": {
    "concept_ids": ["concept:zh:word:你好"],
    "sense_ids": ["sense:zh:你好:1"],
    "skill_tags": ["vocab", "recognition"]
  },

  "stimulus": [
    { "role": "prompt", "type": "text", "lang": "zh-Hans", "text": "你好" },
    { "role": "prompt_audio", "type": "audio", "lang": "zh-Hans", "url": "..." },
    { "role": "hint", "type": "text", "lang": "en", "text": "Greeting" }
  ],

  "interaction": {
    "options": [
      { "id": "A", "stimulus": [{ "type": "text", "lang": "en", "text": "Hello" }] },
      { "id": "B", "stimulus": [{ "type": "text", "lang": "en", "text": "Goodbye" }] },
      { "id": "C", "stimulus": [{ "type": "text", "lang": "en", "text": "Please" }] },
      { "id": "D", "stimulus": [{ "type": "text", "lang": "en", "text": "Thanks" }] }
    ],
    "ui_hints": { "option_density_mode": "auto" }
  },

  "evaluation": {
    "kind": "select_one",
    "correct_option_ids": ["A"]
  },

  "feedback": {
    "why": [
      { "type": "text", "lang": "en", "text": "你好 means 'hello' or 'hi'." }
    ],
    "remediation": {
      "next_suggestion_variant_ids": ["flashcard_reveal", "listening_minimal_pair"]
    }
  },

  "assets_manifest": {
    "prefetch": ["audio:...", "image:..."],
    "required": ["audio:..."]
  },

  "metadata": {
    "difficulty": 0.3,
    "estimated_seconds": 8,
    "source": "generator:v4"
  }
}
```

### What this buys you immediately

* A **video lesson** is just another stimulus atom (`type: "video"`) or another content object that can *contain checkpoint exercises*.
* Images, diagrams, equations become atoms too.
* The same schema works for **any subject** because it’s not “Chinese-specific”; it’s “stimulus + interaction + evaluation”.

---

## 3) Treat “lessons” and “exercises” as the same family: Learning Objects

For the TikTok-for-knowledge part, don’t bolt video onto exercises. Instead introduce a top-level “learning object” concept:

### LearningObject types

* `clip` (TikTok-style micro lesson)
* `lesson` (Khan-style longer form)
* `exercise` (your ExerciseItem)
* `set` (a pack / mission / playlist)
* `explanation_card` (remediation snippet)

A `clip` contains:

* video URL
* transcript + captions
* concept tags
* optional checkpoints: list of `exercise_ids` + timestamps

This means your feed can mix:

* clips → checkpoint → quick practice → next clip
  without inventing a new system.

---

## 4) Strengthen your “Output”: attempt event should be a universal telemetry contract

You already have `is_correct`, latency, selected answer, transcript+score. Expand this slightly so you can:

* debug generators,
* run A/B tests,
* build better scheduling,
* replay user interactions.

### AttemptEvent v2 (recommended)

```json
{
  "attempt_id": "att_789",
  "exercise_id": "ex_123",
  "schema_version": 2,

  "template_id": "select_one",
  "variant_id": "meaning_select",

  "started_at": 1710000000,
  "submitted_at": 1710000007,
  "latency_ms": 7000,

  "response": {
    "selected_option_ids": ["B"],
    "constructed_sequence": null,
    "free_text": null,
    "audio_recording_ref": null
  },

  "evaluation": {
    "is_correct": false,
    "score": 0.0,
    "grade_label": "incorrect",
    "rubric_version": "select_one_v1",
    "details": { "correct_option_ids": ["A"] }
  },

  "trace": [
    { "t": 1200, "event": "option_viewed", "option_id": "A" },
    { "t": 2200, "event": "option_viewed", "option_id": "B" },
    { "t": 6500, "event": "selected", "option_id": "B" }
  ],

  "context": {
    "session_id": "sess_55",
    "mode": "practice",
    "device": "android",
    "locale": "en-US"
  }
}
```

**Key:** keep `response` and `evaluation` **template-driven** so every template yields a predictable shape.

---

## 5) Cross-language design: add language + normalization as first-class concerns

If you want “one structure for any language”, you need to bake in:

### A) Language tags everywhere

Use BCP-47 tags like `zh-Hans`, `zh-Hant`, `en`, `es`, `ar`, `hi`, etc.

### B) Two representations of text

* `display`: what the user sees
* `normalized`: what the evaluator uses

For example, speaking evaluation might normalize:

* punctuation
* casing
* diacritics (optional per language)
* whitespace
* tone marks (only when appropriate)

This allows you to support:

* languages with scripts (Chinese, Arabic)
* languages with diacritics (French, Vietnamese)
* transliterations (pinyin, romaji)

### C) Tokenization as a pluggable service

Your `order_sentence` and cloze need tokenization. Tokenization rules differ hugely:

* English: space-separated tokens mostly
* Chinese: segmentation (word vs character)
* Japanese: needs morphological segmentation
* Arabic: affixes and clitics

So define a **TokenSpec**:

* `token_id`
* `display`
* `normalized`
* optional `audio_timing` or `phonemes`

---

## 6) Make “evaluation” modular and versioned (especially speaking)

### Speaking today: transcript similarity via Levenshtein

That’s a good MVP, but to scale you’ll want:

#### Improvements that preserve your current design

* Accept **multiple correct answers** (`sample_answers[]`) *and score against the best match*
* Use **n-best transcripts** (if available) instead of only the top transcript
* Add **partial credit**: score segments/keywords rather than whole-string match for prompted reply
* Add a language-specific normalization pipeline
* Record the evaluator version in the attempt event (`rubric_version`)

#### Future-safe speaking evaluation structure

Make your evaluator output structured details even if the UI only shows “clean/ok/needsWork”:

* `overall_score`
* `grade_label`
* `missing_keywords[]`
* `pronunciation_flags[]` (future)
* `timing_flags[]` (future)

That lets you upgrade scoring later without breaking your event schema.

---

## 7) Generator safety: add a schema-linter and a “quality gate”

Since you’re going to generate tons of items (AI + pipelines), you want a strict gate:

### Generator pipeline

1. Generate candidate ExerciseItem
2. **Validate schema** (required fields per template)
3. **Validate content constraints**

   * no duplicate options
   * answer exists in options
   * option count limits
   * audio/image URLs valid (or placeholder allowed)
4. **Run golden tests** for evaluators
5. Only then store/publish

This is the difference between “cool demos” and “production content factory”.

---

## 8) Your current template set is excellent — here’s how I’d map your missing Phase C types

You listed not implemented yet:

* `reverse_recall`
* `error_correction`
* `conversation_simulation`
* `character_writing`
* `read_and_select_in_passage`
* `flashcard` as full runner type

Here’s how to design them so they *fit your template-first architecture*:

### A) `reverse_recall`

Template: `free_text` (or `speak` if spoken recall)
Evaluation: fuzzy matching + synonyms + keyword rubric

### B) `error_correction`

Template: `select_in_text` (new)
Stimulus: passage with token IDs
Response: select span(s)
Evaluation: correct span IDs

### C) `conversation_simulation`

Template: `dialog_tree` (new) or `chat_roleplay` (new)
This can still be deterministic if you start with:

* predefined turns
* multiple-choice replies (your existing `select_one`)
  Then later upgrade to free-text with LLM scoring.

### D) `character_writing`

Template: `draw_write` (new)
Response: strokes/bitmap
Evaluation: initially “self-check + reveal + compare”, later ML scoring.

### E) `flashcard`

Template: `reveal` (simple)
Output event still matters: “reveal_time”, “self-rated”, “knew_it”

**This is important:** flashcards are *not* “an exercise type” in the same sense; they are a learning object with a different evaluation style (self report + timing).

---

## 9) How to make the TikTok feed actually *teach*, not just entertain

A feed is a distribution system. Learning requires **checkpoints + scheduling**.

### Recommended feed loop

* show `clip`
* after clip (or mid-clip), inject a **1-item checkpoint exercise** (same engine)
* based on attempt, do one of:

  * move on
  * show a 10–20s remediation clip
  * schedule follow-up practice later (spaced repetition)

### Practical rule

Every clip should declare:

* `concept_ids[]`
* `difficulty`
* `checkpoint_exercise_ids[]` (optional, but strongly recommended)

Then your “brain” can do:

* interest-based recommendation (TikTok)
* mastery-based scheduling (Duolingo)
* structured progress paths (Khan)

All using the same attempt events.

---

## 10) Concrete refactor plan that matches your current code structure

You already have:

* backend brain router
* frontend runner switch
* `PilotExercisePack` model
* `/brain/submit` pipeline

I would do this in layers:

### Step 1 — Introduce `template_id` without breaking anything

Keep `exercise_type` for now, but derive:

* `template_id = map(exercise_type)`
* `variant_id = exercise_type` (temporarily)

Then update the runner to switch on `template_id` (not `exercise_type`).

### Step 2 — Convert exercise payloads to “stimulus atoms”

Wrap existing prompt/audio/image fields into `stimulus[]`.

### Step 3 — Version schemas

Add `schema_version` and `rubric_version` now, before content explodes.

### Step 4 — Unify DB naming mismatches

You currently have `sentence_fill` and `cloze_select` representing very similar things. Normalize naming so your generator + analytics aren’t fragmented.

### Step 5 — Build a registry

Have a single registry that defines per template:

* required input fields
* response schema
* evaluator
* UI renderer
* output event shape

That registry becomes the heart of your “structural formula” black box.

---

## The “Structural Formula” you’re drawing, expressed as a stable contract

Here is the black box in one line:

**ExerciseItem (stimulus + interaction + evaluation spec) → Template Renderer → Response Capture → Evaluator → AttemptEvent → Brain Update + Next Selection**

That’s it.

Everything else (subjects, languages, video, pictures, conversation) is just:

* more stimulus atoms
* more variants
* a few new templates over time

---

## If you want one “north star” principle

Design every new feature so that it fits this rule:

> If a new exercise can be expressed as *stimulus atoms + a response type + an evaluation spec*, it belongs in the engine.
> If it cannot, it’s a separate learning object (lesson/clip/sim) that may contain checkpoints.

That keeps your engine clean and reusable forever.

---