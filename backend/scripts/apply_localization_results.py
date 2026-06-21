#!/usr/bin/env python3
"""Apply external localization worker outputs into the learning DB.

Expected worker result format (JSON file):
{
  "items": [
    {
      "concept_id": "W123456",
      "translations": {"en": "to eat", "uz": "yemoq", ...}
    }
  ]
}

Or JSONL lines with the same item structure.

Rules enforced:
- one primary meaning per language (separator-trim to first segment)
- upsert into concept_localizations
- optional update of concepts.meaning from EN
- optional bootstrap primary sense if absent
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List, Sequence


DEFAULT_TARGET_LANGS = [
    "en",
    "uz",
    "es",
    "fr",
    "ru",
    "ar",
    "pt",
    "de",
    "it",
    "ja",
    "ko",
    "hi",
    "ur",
    "bn",
    "tr",
    "pl",
    "nl",
    "fa",
    "id",
    "vi",
    "th",
    "ms",
    "tl",
    "sw",
    "uk",
    "ro",
    "cs",
    "hu",
    "sv",
    "da",
    "no",
    "el",
    "he",
    "pa",
    "ta",
    "zh",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _split_csv(raw: str, fallback: Sequence[str]) -> List[str]:
    values = [v.strip() for v in str(raw or "").split(",") if v.strip()]
    if not values:
        return list(fallback)
    out: List[str] = []
    seen = set()
    for value in values:
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(value)
    return out


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS concept_localizations (
            concept_id TEXT NOT NULL,
            language_code TEXT NOT NULL,
            meaning TEXT,
            context_translation TEXT,
            source_pack TEXT,
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (concept_id, language_code)
        );
        CREATE INDEX IF NOT EXISTS idx_cl_concept ON concept_localizations(concept_id);
        CREATE INDEX IF NOT EXISTS idx_cl_lang ON concept_localizations(language_code);

        CREATE TABLE IF NOT EXISTS concept_senses (
            sense_id TEXT PRIMARY KEY,
            concept_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL DEFAULT 1,
            gloss TEXT NOT NULL,
            pos TEXT,
            register TEXT,
            example_zh TEXT,
            example_en TEXT,
            is_primary INTEGER NOT NULL DEFAULT 0 CHECK(is_primary IN (0, 1)),
            source TEXT DEFAULT 'bootstrap',
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(concept_id, ordinal),
            UNIQUE(concept_id, gloss)
        );
        CREATE INDEX IF NOT EXISTS idx_cs_concept ON concept_senses(concept_id);
        """
    )


def _normalize_single_gloss(text: str) -> str:
    value = str(text or "").strip()
    if not value:
        return ""
    value = value.replace("```", "").strip()
    value = re.sub(r"\s+", " ", value)

    # keep one meaning only
    separators = [";", "；", "/", "\n", "、", "|"]
    for sep in separators:
        if sep in value:
            value = value.split(sep, 1)[0].strip()
    if "," in value:
        parts = [p.strip() for p in value.split(",") if p.strip()]
        if len(parts) > 1:
            value = parts[0]

    value = value.strip(" .;，、；:：")
    if len(value) > 120:
        value = value[:120].strip()
    return value


def _iter_items_from_file(path: Path) -> Iterable[dict]:
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        for line in path.read_text(encoding="utf-8").splitlines():
            raw = line.strip()
            if not raw:
                continue
            try:
                item = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                yield item
        return

    if suffix == ".json":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return
        if isinstance(data, dict):
            if isinstance(data.get("items"), list):
                for item in data["items"]:
                    if isinstance(item, dict):
                        yield item
                return
            if isinstance(data.get("results"), list):
                for item in data["results"]:
                    if isinstance(item, dict):
                        yield item
                return
            if "concept_id" in data and "translations" in data:
                yield data
                return
            if isinstance(data.get("jobs"), list):
                # shard input (not yet translated) is ignored
                return
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    yield item


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply localization results from worker output files")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument(
        "--input-glob",
        required=True,
        help="Glob for result files, e.g. docs/translation_results/*.json",
    )
    parser.add_argument("--target-langs", default=",".join(DEFAULT_TARGET_LANGS))
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--overwrite-concepts-meaning", action="store_true")
    parser.add_argument(
        "--overwrite-primary-sense",
        action="store_true",
        help="When EN gloss is present, update existing primary sense gloss to match.",
    )
    parser.add_argument("--source-tag", default="external_worker_import")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    report_dir = root / args.report_dir if not Path(args.report_dir).is_absolute() else Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    target_langs = set(x.lower() for x in _split_csv(args.target_langs, DEFAULT_TARGET_LANGS))
    files = sorted(Path(p) for p in glob.glob(str(root / args.input_glob)))

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not files:
        print(f"No input files for glob: {args.input_glob}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    _ensure_schema(conn)

    stats = {
        "files": len(files),
        "items_seen": 0,
        "items_with_translations": 0,
        "concept_missing": 0,
        "rows_written": 0,
        "rows_skipped_existing": 0,
        "rows_skipped_invalid_lang": 0,
        "rows_skipped_empty": 0,
        "concepts_meaning_updated": 0,
        "primary_senses_inserted": 0,
        "primary_senses_updated": 0,
    }

    known_concepts = {
        str(r[0]) for r in conn.execute("SELECT id FROM concepts").fetchall()
    }

    for file_path in files:
        for item in _iter_items_from_file(file_path):
            stats["items_seen"] += 1
            concept_id = str(item.get("concept_id") or "").strip()
            if not concept_id or concept_id not in known_concepts:
                stats["concept_missing"] += 1
                continue
            translations = item.get("translations")
            if not isinstance(translations, dict):
                continue
            stats["items_with_translations"] += 1

            normalized: Dict[str, str] = {}
            for lang, text in translations.items():
                lang_code = str(lang or "").strip().lower()
                if lang_code not in target_langs:
                    stats["rows_skipped_invalid_lang"] += 1
                    continue
                gloss = _normalize_single_gloss(str(text or ""))
                if not gloss:
                    stats["rows_skipped_empty"] += 1
                    continue
                normalized[lang_code] = gloss

            if not normalized:
                continue

            if args.apply:
                for lang_code, gloss in normalized.items():
                    existing = conn.execute(
                        """
                        SELECT meaning FROM concept_localizations
                        WHERE concept_id = ? AND language_code = ?
                        LIMIT 1
                        """,
                        (concept_id, lang_code),
                    ).fetchone()
                    existing_text = str(existing[0] or "").strip() if existing else ""
                    if existing_text and not args.overwrite:
                        stats["rows_skipped_existing"] += 1
                        continue

                    conn.execute(
                        """
                        INSERT INTO concept_localizations
                            (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
                        VALUES (?, ?, ?, '', ?, datetime('now'))
                        ON CONFLICT(concept_id, language_code) DO UPDATE SET
                            meaning = excluded.meaning,
                            source_pack = excluded.source_pack,
                            updated_at = datetime('now')
                        """,
                        (concept_id, lang_code, gloss, args.source_tag),
                    )
                    stats["rows_written"] += 1

                en_gloss = normalized.get("en", "")
                if en_gloss:
                    row = conn.execute(
                        "SELECT COALESCE(meaning, '') FROM concepts WHERE id = ?",
                        (concept_id,),
                    ).fetchone()
                    current_meaning = str(row[0] or "").strip() if row else ""
                    if args.overwrite_concepts_meaning or not current_meaning:
                        conn.execute(
                            "UPDATE concepts SET meaning = ? WHERE id = ?",
                            (en_gloss, concept_id),
                        )
                        stats["concepts_meaning_updated"] += 1

                    has_sense = conn.execute(
                        "SELECT 1 FROM concept_senses WHERE concept_id = ? LIMIT 1",
                        (concept_id,),
                    ).fetchone()
                    if not has_sense:
                        conn.execute(
                            """
                            INSERT OR IGNORE INTO concept_senses
                                (sense_id, concept_id, ordinal, gloss, is_primary, source)
                            VALUES (?, ?, 1, ?, 1, 'external_worker_import')
                            """,
                            (f"{concept_id}::s01", concept_id, en_gloss),
                        )
                        stats["primary_senses_inserted"] += 1
                    elif args.overwrite_primary_sense:
                        target_gloss = en_gloss
                        same_gloss_row = conn.execute(
                            """
                            SELECT sense_id
                            FROM concept_senses
                            WHERE concept_id = ? AND gloss = ?
                            ORDER BY is_primary DESC, ordinal ASC, sense_id ASC
                            LIMIT 1
                            """,
                            (concept_id, target_gloss),
                        ).fetchone()
                        if same_gloss_row is not None:
                            sid = str(same_gloss_row[0])
                            conn.execute(
                                "UPDATE concept_senses SET is_primary = 0 WHERE concept_id = ?",
                                (concept_id,),
                            )
                            conn.execute(
                                """
                                UPDATE concept_senses
                                SET is_primary = 1, source = ?
                                WHERE sense_id = ?
                                """,
                                (args.source_tag, sid),
                            )
                            stats["primary_senses_updated"] += 1
                            continue

                        primary_row = conn.execute(
                            """
                            SELECT sense_id
                            FROM concept_senses
                            WHERE concept_id = ? AND is_primary = 1
                            ORDER BY ordinal ASC, sense_id ASC
                            LIMIT 1
                            """,
                            (concept_id,),
                        ).fetchone()
                        if primary_row is not None:
                            conn.execute(
                                """
                                UPDATE concept_senses
                                SET gloss = ?, source = ?, created_at = created_at
                                WHERE sense_id = ?
                                """,
                                (target_gloss, args.source_tag, str(primary_row[0])),
                            )
                            stats["primary_senses_updated"] += 1
                        else:
                            fallback_row = conn.execute(
                                """
                                SELECT sense_id
                                FROM concept_senses
                                WHERE concept_id = ?
                                ORDER BY ordinal ASC, sense_id ASC
                                LIMIT 1
                                """,
                                (concept_id,),
                            ).fetchone()
                            if fallback_row is not None:
                                sid = str(fallback_row[0])
                                conn.execute(
                                    "UPDATE concept_senses SET is_primary = 0 WHERE concept_id = ?",
                                    (concept_id,),
                                )
                                conn.execute(
                                    """
                                    UPDATE concept_senses
                                    SET gloss = ?, is_primary = 1, source = ?
                                    WHERE sense_id = ?
                                    """,
                                    (target_gloss, args.source_tag, sid),
                                )
                                stats["primary_senses_updated"] += 1

    if args.apply:
        conn.commit()

    conn.close()

    stamp = dt.date.today().isoformat()
    report = {
        "date": stamp,
        "db": str(db_path),
        "input_glob": args.input_glob,
        "target_langs_count": len(target_langs),
        "apply": args.apply,
        "overwrite": args.overwrite,
        "overwrite_concepts_meaning": args.overwrite_concepts_meaning,
        **stats,
    }
    report_path = report_dir / f"apply_localization_results_{stamp}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(report, ensure_ascii=False))
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
