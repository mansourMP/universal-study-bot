#!/usr/bin/env python3
"""Build deterministic HSK1 unit-circle pack from frozen baseline + template.

Outputs:
- docs/specs/hsk1_unit_circle_pack_v1.json
- docs/specs/hsk1_unit_circle_pack_v1.sha256
- docs/reports/build_hsk1_unit_circle_pack_YYYY-MM-DD.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _read_sha(path: Path) -> str:
    if not path.exists():
        return ""
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return ""
    return raw.split()[0]


def _canonical_bytes(payload: Dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def _resolve_path(root: Path, raw: str) -> Path:
    p = Path(raw)
    return p if p.is_absolute() else root / p


def _apply_contract_defaults(args: argparse.Namespace, parser: argparse.ArgumentParser, contract: Dict[str, Any]) -> None:
    sources = contract.get("sources", {}) if isinstance(contract, dict) else {}
    outputs = contract.get("outputs", {}) if isinstance(contract, dict) else {}

    if args.baseline == parser.get_default("baseline") and sources.get("core_baseline"):
        args.baseline = str(sources["core_baseline"])
    if args.baseline_sha == parser.get_default("baseline_sha") and sources.get("core_baseline_sha256"):
        args.baseline_sha = str(sources["core_baseline_sha256"])
    if args.template == parser.get_default("template") and sources.get("circle_template"):
        args.template = str(sources["circle_template"])

    if args.out == parser.get_default("out") and outputs.get("unit_circle_pack"):
        args.out = str(outputs["unit_circle_pack"])
    if args.out_sha == parser.get_default("out_sha") and outputs.get("unit_circle_pack_sha256"):
        args.out_sha = str(outputs["unit_circle_pack_sha256"])
    if args.report_dir == parser.get_default("report_dir") and outputs.get("build_report_dir"):
        args.report_dir = str(outputs["build_report_dir"])


def _pick_new_words(word_ids: List[str], n: int, offset: int) -> List[str]:
    return word_ids[offset : offset + n]


def _circle_ids(template: Dict[str, Any]) -> List[str]:
    return [str(c.get("circle_id") or "") for c in template.get("circle_sequence", []) if str(c.get("circle_id") or "")]


def _template_circle_map(template: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for c in template.get("circle_sequence", []):
        cid = str(c.get("circle_id") or "")
        if cid:
            out[cid] = c
    return out


def _validate_inputs(baseline: Dict[str, Any], template: Dict[str, Any]) -> Tuple[bool, List[str]]:
    errors: List[str] = []
    stats = baseline.get("stats", {}) if isinstance(baseline, dict) else {}
    units = baseline.get("units", []) if isinstance(baseline, dict) else []
    if int(stats.get("core_distinct_words", 0)) != 500:
        errors.append("baseline core_distinct_words must be 500")
    if int(stats.get("units", 0)) != 32:
        errors.append("baseline units must be 32")
    if len(units) != 32:
        errors.append("baseline units array must contain 32 units")
    circle_ids = _circle_ids(template)
    if circle_ids != ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]:
        errors.append("template circle IDs must be exactly C1..C7 in order")
    return (len(errors) == 0, errors)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build HSK1 unit-circle pack from baseline")
    parser.add_argument("--contract", default="", help="Canonical contract JSON (optional)")
    parser.add_argument("--baseline", default="docs/specs/hsk1_core_baseline_v1.json")
    parser.add_argument("--baseline-sha", default="docs/specs/hsk1_core_baseline_v1.sha256")
    parser.add_argument("--template", default="docs/specs/hsk1_circle_template_v1.json")
    parser.add_argument("--out", default="docs/specs/hsk1_unit_circle_pack_v1.json")
    parser.add_argument("--out-sha", default="docs/specs/hsk1_unit_circle_pack_v1.sha256")
    parser.add_argument("--report-dir", default="docs/reports")
    args = parser.parse_args()

    root = _repo_root()
    contract: Dict[str, Any] = {}
    contract_path = _resolve_path(root, args.contract) if str(args.contract).strip() else None
    if contract_path is not None:
        if not contract_path.exists():
            print(json.dumps({"ok": False, "error": f"Contract not found: {contract_path}"}))
            return 1
        contract = _read_json(contract_path)
        if str(contract.get("standard", "")).strip() not in {"", "HSK3.0"}:
            print(json.dumps({"ok": False, "error": "contract standard must be HSK3.0"}))
            return 1
        if str(contract.get("level", "")).strip() not in {"", "HSK1"}:
            print(json.dumps({"ok": False, "error": "contract level must be HSK1"}))
            return 1
        _apply_contract_defaults(args, parser, contract)

    baseline_path = _resolve_path(root, args.baseline)
    baseline_sha_path = _resolve_path(root, args.baseline_sha)
    template_path = _resolve_path(root, args.template)
    out_path = _resolve_path(root, args.out)
    out_sha_path = _resolve_path(root, args.out_sha)
    report_dir = _resolve_path(root, args.report_dir)

    report_dir.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_sha_path.parent.mkdir(parents=True, exist_ok=True)

    if not baseline_path.exists():
        print(json.dumps({"ok": False, "error": f"Baseline not found: {baseline_path}"}))
        return 1
    if not template_path.exists():
        print(json.dumps({"ok": False, "error": f"Template not found: {template_path}"}))
        return 1

    baseline = _read_json(baseline_path)
    template = _read_json(template_path)
    baseline_sha = _read_sha(baseline_sha_path)

    valid, errors = _validate_inputs(baseline, template)
    if not valid:
        print(json.dumps({"ok": False, "error": "invalid_inputs", "details": errors}, ensure_ascii=False))
        return 1

    circle_map = _template_circle_map(template)
    circles_order = ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]
    new_a_n = int(circle_map["C1"].get("new_senses_target", 4))
    new_b_n = int(circle_map["C4"].get("new_senses_target", 4))

    units_in = baseline.get("units", [])
    pack_units: List[Dict[str, Any]] = []
    all_word_ids: List[str] = []
    all_sense_ids: List[str] = []

    for unit in units_in:
        words = unit.get("words", [])
        word_ids = [str(w.get("word_id")) for w in words]
        sense_ids = [str(w.get("sense_id")) for w in words]
        all_word_ids.extend(word_ids)
        all_sense_ids.extend(sense_ids)

        new_a_word_ids = _pick_new_words(word_ids, new_a_n, 0)
        new_b_word_ids = _pick_new_words(word_ids, new_b_n, new_a_n)
        new_a_sense_ids = _pick_new_words(sense_ids, new_a_n, 0)
        new_b_sense_ids = _pick_new_words(sense_ids, new_b_n, new_a_n)

        introduced_word_ids = list(dict.fromkeys(new_a_word_ids + new_b_word_ids))
        introduced_sense_ids = list(dict.fromkeys(new_a_sense_ids + new_b_sense_ids))

        circles: List[Dict[str, Any]] = []
        for cid in circles_order:
            c = circle_map[cid]
            if cid in {"C1", "C2", "C3"}:
                focus_word_ids = new_a_word_ids
                focus_sense_ids = new_a_sense_ids
            elif cid in {"C4", "C5"}:
                focus_word_ids = new_b_word_ids
                focus_sense_ids = new_b_sense_ids
            else:
                # Review and checkpoint must be restricted to introduced content.
                focus_word_ids = introduced_word_ids
                focus_sense_ids = introduced_sense_ids

            mix = c.get("exercise_mix", {}) or {}
            target_exercises = sum(int(v) for v in mix.values())
            target_exercises = min(target_exercises, max(1, len(focus_word_ids)))
            candidate_pool_size = len(focus_word_ids)
            target_word_count = int(c.get("target_word_count") or 0)
            if target_word_count <= 0:
                target_word_count = min(
                    candidate_pool_size,
                    max(4, int(round(candidate_pool_size * 0.6))),
                )
            target_word_count = min(max(1, target_word_count), candidate_pool_size or 1)
            circles.append(
                {
                    "circle_id": cid,
                    "title": c.get("title"),
                    "duration_target_sec": int(c.get("duration_seconds_target", 240)),
                    "exercise_mix": mix,
                    "target_exercise_count": int(target_exercises),
                    "candidate_pool_size": int(candidate_pool_size),
                    "target_word_count": int(target_word_count),
                    "pass_rules": c.get("pass_rules", {}),
                    "on_fail": c.get("on_fail", {}),
                    "focus_word_ids": focus_word_ids,
                    "focus_sense_ids": focus_sense_ids,
                }
            )

        pack_units.append(
            {
                "unit_id": unit.get("unit_id"),
                "unit_number": int(unit.get("unit_number", 0)),
                "title": unit.get("title"),
                "size": int(unit.get("size", len(words))),
                "word_ids": word_ids,
                "sense_ids": sense_ids,
                "circles": circles,
            }
        )

    payload: Dict[str, Any] = {
        "id": "hsk1_unit_circle_pack_v1",
        "version": 1,
        "generated_at_utc": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "standard": "HSK3.0",
        "level": "HSK1",
        "source": {
            "contract_file": str(contract_path) if contract_path is not None else "",
            "contract_id": contract.get("id") if contract else "",
            "contract_version": contract.get("version") if contract else None,
            "baseline_file": str(baseline_path),
            "baseline_sha256": baseline_sha,
            "template_file": str(template_path),
            "template_id": template.get("id"),
            "template_version": template.get("version"),
        },
        "runtime_defaults": template.get("runtime_defaults", {}),
        "retry_policy": template.get("retry_policy", {}),
        "anti_repeat_rules": template.get("anti_repeat_rules", {}),
        "content_quota_per_sense": template.get("content_quota_per_sense", {}),
        "stats": {
            "units": len(pack_units),
            "words_distinct": len(set(all_word_ids)),
            "senses_distinct": len(set(all_sense_ids)),
            "circle_count_per_unit": 7,
            "session_duration_target_sec": int(template.get("runtime_defaults", {}).get("circle_duration_seconds", {}).get("target", 240)),
        },
        "units": pack_units,
    }

    canonical = _canonical_bytes(payload)
    digest = hashlib.sha256(canonical).hexdigest()
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    out_sha_path.write_text(f"{digest}  {out_path.name}\n", encoding="utf-8")

    report = {
        "ok": True,
        "id": payload["id"],
        "sha256": digest,
        "out_json": str(out_path),
        "out_sha": str(out_sha_path),
        "stats": payload["stats"],
    }
    report_path = report_dir / f"build_hsk1_unit_circle_pack_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report["report"] = str(report_path)
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
