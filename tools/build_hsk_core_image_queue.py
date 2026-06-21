#!/usr/bin/env python3
"""Build full HSK core image-generation queue files from learning_path.db.

Outputs four CSV files used by existing image tools:
  1) catalog CSV (prompt + metadata)
  2) naming CSV (recommended filename)
  3) word map CSV (word_public_id -> word_id)
  4) links CSV (image_id -> word_public_id)

By default, this covers HSK1..HSK7 core (HSK7 == HSK7-9 bucket in current DB).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import sqlite3
from pathlib import Path


DEFAULT_DB = Path("backend/learning_path.db")
DEFAULT_OUT_DIR = Path("docs/reports")

ALLOWED_LEVELS = {"HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"}

PROMPT_TEMPLATE = (
    'A clear visual for "{name}", flat vector style. '
    "The style is a digital painting with smooth brushstrokes, clean vector shapes, "
    "controlled low-saturation color palette, soft studio lighting, and a neutral background. "
    "High quality concept art, balanced contrast, reduced color intensity. "
    "No text inside the image. output size 1024x1024"
)


def slugify(value: str) -> str:
    text = (value or "").strip().lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    text = text.replace("_", " ")
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"_+", "_", text)
    text = text.strip("_")
    return text or "concept"


def parse_levels(raw: str) -> list[str]:
    parts = [p.strip().upper() for p in raw.split(",") if p.strip()]
    if not parts:
        return ["HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"]
    for p in parts:
        if p not in ALLOWED_LEVELS:
            raise SystemExit(f"Unsupported level: {p}. Allowed: {sorted(ALLOWED_LEVELS)}")
    return parts


def fetch_rows(conn: sqlite3.Connection, level: str) -> list[sqlite3.Row]:
    return conn.execute(
        """
        WITH ids AS (
            SELECT concept_id
            FROM concept_curriculum_map
            WHERE standard='HSK3.0' AND level=? AND band='core'
            GROUP BY concept_id
            ORDER BY concept_id
        )
        SELECT
            c.id AS word_id,
            c.text AS word,
            COALESCE(c.pinyin, '') AS pinyin,
            COALESCE(
                (
                    SELECT cl.meaning
                    FROM concept_localizations cl
                    WHERE cl.concept_id = c.id
                      AND cl.language_code = 'en'
                    ORDER BY cl.rowid DESC
                    LIMIT 1
                ),
                c.meaning,
                ''
            ) AS meaning
        FROM ids i
        JOIN concepts c ON c.id = i.concept_id
        ORDER BY c.id
        """,
        (level,),
    ).fetchall()


def build_files(db: Path, out_dir: Path, levels: list[str], prefix: str) -> dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    today = dt.date.today().isoformat()

    catalog_path = out_dir / f"{prefix}_catalog_{today}.csv"
    naming_path = out_dir / f"{prefix}_naming_{today}.csv"
    links_path = out_dir / f"{prefix}_links_{today}.csv"
    word_map_path = out_dir / f"{prefix}_word_map_{today}.csv"

    conn = sqlite3.connect(str(db))
    conn.row_factory = sqlite3.Row
    try:
        catalog_rows: list[dict[str, str]] = []
        naming_rows: list[dict[str, str]] = []
        links_rows: list[dict[str, str]] = []
        word_map_rows: list[dict[str, str]] = []

        for level in levels:
            rows = fetch_rows(conn, level)
            for idx, row in enumerate(rows, start=1):
                word_id = str(row["word_id"] or "").strip()
                word = str(row["word"] or "").strip()
                pinyin = str(row["pinyin"] or "").strip()
                meaning = str(row["meaning"] or "").strip()
                if not word_id:
                    continue

                word_public_id = f"{level}-W-{idx:04d}"
                image_id = f"IMG_{level}_W_{idx:04d}"
                concept_slug = slugify(meaning or word)
                concept_key = f"{level.lower()}_{word_id.lower()}_{concept_slug}"
                recommended_filename = (
                    f"object_{level.lower()}_{idx:04d}_{concept_slug}_centered_001.webp"
                )
                prompt = PROMPT_TEMPLATE.format(name=(meaning or word or "concept"))

                catalog_rows.append(
                    {
                        "image_id": image_id,
                        "concept_key": concept_key,
                        "name_en": (meaning or word),
                        "category": "object_scene",
                        "cultural_context": "universal",
                        "filename": f"img__{image_id.lower()}__v1.webp",
                        "image_size": "1024x1024",
                        "style": "digital_painting_vector_hybrid_v7_muted",
                        "background_style": "neutral studio background",
                        "prompt_en": prompt,
                        "reusable_for": (
                            "language_learning|cross_language_vocabulary|"
                            "reading_comprehension|listening_comprehension"
                        ),
                        "linked_sense_count": "1",
                        "prompt_template_version": "v7_vector_painting_muted",
                        "hsk_level": level,
                        "word_public_id": word_public_id,
                        "word_id": word_id,
                    }
                )

                naming_rows.append(
                    {
                        "image_id": image_id,
                        "category": "object_scene",
                        "concept_key": concept_key,
                        "name_en": (meaning or word),
                        "current_filename": f"img__{image_id.lower()}__v1.webp",
                        "recommended_filename": recommended_filename,
                        "semantic_category": "object",
                        "semantic_subcategory": "general",
                        "semantic_concept": concept_slug,
                        "semantic_variant": "centered",
                        "rename_action": "create",
                        "hsk_level": level,
                    }
                )

                word_map_rows.append(
                    {
                        "word_public_id": word_public_id,
                        "word_id": word_id,
                        "word": word,
                        "pinyin": pinyin,
                        "meaning": meaning,
                        "unit_id": "",
                        "unit_sequence": "",
                        "hsk_level": level,
                    }
                )

                links_rows.append(
                    {
                        "link_id": f"LNK_{level}_{idx:04d}",
                        "sense_public_id": f"{level}-S-{idx:04d}",
                        "word_public_id": word_public_id,
                        "image_id": image_id,
                        "concept_key": concept_key,
                        "relevance": "primary",
                        "usage_context": (
                            "flashcard|meaning_select|character_select|audio_select|reading_micro"
                        ),
                        "language_scope": "multilingual",
                        "status": "active",
                        "hsk_level": level,
                    }
                )

        def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
            if not rows:
                raise SystemExit(f"No rows for {path.name}")
            with path.open("w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
                writer.writeheader()
                writer.writerows(rows)

        write_csv(catalog_path, catalog_rows)
        write_csv(naming_path, naming_rows)
        write_csv(links_path, links_rows)
        write_csv(word_map_path, word_map_rows)
    finally:
        conn.close()

    return {
        "catalog": catalog_path,
        "naming": naming_path,
        "links": links_path,
        "word_map": word_map_path,
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--db", default=str(DEFAULT_DB), help="Path to learning_path.db")
    p.add_argument(
        "--out-dir",
        default=str(DEFAULT_OUT_DIR),
        help="Output directory for generated CSV files",
    )
    p.add_argument(
        "--levels",
        default="HSK1,HSK2,HSK3,HSK4,HSK5,HSK6,HSK7",
        help="Comma-separated levels to include (HSK7 is current 7-9 bucket)",
    )
    p.add_argument(
        "--prefix",
        default="hsk_core_images_queue_v1",
        help="Output filename prefix",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    paths = build_files(
        db=Path(args.db),
        out_dir=Path(args.out_dir),
        levels=parse_levels(args.levels),
        prefix=args.prefix,
    )
    print('{"ok": true, "catalog": "%s", "naming": "%s", "links": "%s", "word_map": "%s"}'
          % (
              paths["catalog"].resolve(),
              paths["naming"].resolve(),
              paths["links"].resolve(),
              paths["word_map"].resolve(),
          ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
