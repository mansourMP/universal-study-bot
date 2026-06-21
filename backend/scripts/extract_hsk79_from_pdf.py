#!/usr/bin/env python3
"""Extract HSK (7-9) vocabulary candidates from official PDF syllabus.

Outputs:
- docs/reports/hsk79_vocab_raw_<date>.csv
- docs/reports/hsk79_vocab_raw_<date>.json
- docs/reports/hsk79_pdf_text_<date>.txt (optional, default on)

Notes:
- Uses macOS `textutil` for PDF -> text conversion (no extra Python deps).
- Extraction is heuristic because official PDF formatting may vary.
- Result should be reviewed before curriculum lock/import.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import subprocess
import tempfile
import urllib.request
import zlib
from pathlib import Path
from typing import List, Sequence


DEFAULT_HSK79_URL = (
    "https://hsk.cn-bj.ufileos.com/3.0/%E6%96%B0%E7%89%88HSK%E8%80%83%E8%AF%95%E5%A4%A7%E7%BA%B21219.pdf"
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _looks_like_hanzi_token(token: str) -> bool:
    if not token:
        return False
    if len(token) > 10:
        return False
    if not re.search(r"[\u3400-\u4dbf\u4e00-\u9fff]", token):
        return False
    if re.search(r"[A-Za-z0-9@#%]", token):
        return False
    # Ignore common section-level words.
    if token in {"词汇", "大纲", "级", "第", "附录", "目录", "说明", "样题", "考试"}:
        return False
    return True


def _normalize_line(line: str) -> str:
    line = line.replace("\u3000", " ").replace("\ufeff", "")
    line = re.sub(r"\s+", " ", line).strip()
    return line


def _find_hsk79_window(lines: Sequence[str]) -> tuple[int, int]:
    start_patterns = [
        re.compile(r"HSK\s*[（(]?\s*七[-—–至到]九"),
        re.compile(r"七[-—–至到]九级"),
        re.compile(r"七[-—–至到]九.*词汇"),
        re.compile(r"词汇.*七[-—–至到]九"),
    ]
    end_patterns = [
        re.compile(r"语法"),
        re.compile(r"汉字"),
        re.compile(r"听力"),
        re.compile(r"阅读"),
        re.compile(r"写作"),
        re.compile(r"样题"),
    ]

    start = 0
    for i, line in enumerate(lines):
        if any(p.search(line) for p in start_patterns):
            start = max(0, i - 5)
            break

    end = len(lines)
    for i in range(start + 10, len(lines)):
        if any(p.search(lines[i]) for p in end_patterns):
            end = i
            break
    return start, end


def _extract_tokens(lines: Sequence[str]) -> List[str]:
    words: List[str] = []
    seen = set()
    for raw in lines:
        line = _normalize_line(raw)
        if not line:
            continue
        # Remove list numbering prefixes.
        line = re.sub(r"^\(?\d{1,4}[)\].、.．]\s*", "", line)
        line = re.sub(r"^第\s*\d+\s*[条章节部分]\s*", "", line)

        # Replace common separators with space.
        line = re.sub(r"[，,；;、/|·•\t]+", " ", line)
        parts = [p.strip() for p in line.split(" ") if p.strip()]

        for token in parts:
            # If token contains brackets, split further.
            subs = re.split(r"[()（）【】\[\]“”\"'<>《》:：]", token)
            for sub in subs:
                sub = sub.strip()
                if not _looks_like_hanzi_token(sub):
                    continue
                if sub in seen:
                    continue
                seen.add(sub)
                words.append(sub)
    return words


def _download_pdf(url: str, dst_path: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    dst_path.write_bytes(data)


def _pdf_to_text(pdf_path: Path) -> str:
    textutil_bin = "/usr/bin/textutil"
    proc = subprocess.run(
        [textutil_bin, "-convert", "txt", "-stdout", str(pdf_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() or "textutil failed"
        raise RuntimeError(stderr)
    return proc.stdout


def _decode_hex_candidate(hex_text: str) -> str:
    # Keep hex clean.
    h = re.sub(r"[^0-9A-Fa-f]", "", hex_text)
    if len(h) < 4 or len(h) % 2 != 0:
        return ""

    candidates: List[str] = []
    try:
        candidates.append(bytes.fromhex(h).decode("utf-16-be", errors="ignore"))
    except Exception:
        pass

    if len(h) % 4 == 0:
        try:
            chars = []
            for i in range(0, len(h), 4):
                cp = int(h[i : i + 4], 16)
                if cp <= 0:
                    continue
                chars.append(chr(cp))
            candidates.append("".join(chars))
        except Exception:
            pass

    def cjk_score(s: str) -> int:
        return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]", s))

    best = ""
    best_score = -1
    for cand in candidates:
        score = cjk_score(cand)
        if score > best_score:
            best = cand
            best_score = score
    return best


def _extract_words_from_pdf_binary(pdf_path: Path) -> List[str]:
    """Fallback parser: inspect PDF streams and decode hex text snippets."""
    raw = pdf_path.read_bytes()
    seen = set()
    out: List[str] = []

    # 1) Parse compressed streams.
    stream_re = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)
    blocks: List[bytes] = []
    for m in stream_re.finditer(raw):
        block = m.group(1)
        blocks.append(block)

    decoded_chunks: List[str] = []
    for block in blocks:
        # Try zlib first (most common for Flate streams).
        tried = False
        for payload in (block, block.strip()):
            if not payload:
                continue
            try:
                txt = zlib.decompress(payload)
                decoded_chunks.append(txt.decode("latin1", errors="ignore"))
                tried = True
                break
            except Exception:
                continue
        if not tried:
            # Keep raw latin1 in case stream is not compressed.
            decoded_chunks.append(block.decode("latin1", errors="ignore"))

    # 2) Extract hex encoded text candidates.
    for chunk in decoded_chunks:
        # Prefer hex strings near text operators.
        for m in re.finditer(r"<([0-9A-Fa-f]{4,})>\s*T[Jj]", chunk):
            decoded = _decode_hex_candidate(m.group(1))
            if not decoded:
                continue
            for token in re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]{1,10}", decoded):
                if token in seen:
                    continue
                seen.add(token)
                out.append(token)

        # Also scan generic hex chunks; useful when operators are packed.
        for m in re.finditer(r"<([0-9A-Fa-f]{4,})>", chunk):
            decoded = _decode_hex_candidate(m.group(1))
            if not decoded:
                continue
            for token in re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]{1,10}", decoded):
                if token in seen:
                    continue
                seen.add(token)
                out.append(token)

    # 3) Filter out obvious non-vocab control labels.
    blacklist = {"说明", "目录", "附录", "词汇", "语法", "样题", "考试", "等级", "标准"}
    out = [w for w in out if w not in blacklist]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract HSK7-9 vocab from official PDF")
    parser.add_argument("--pdf", default="", help="Local PDF path")
    parser.add_argument("--url", default="", help="Remote PDF URL")
    parser.add_argument("--out-dir", default="docs/reports")
    parser.add_argument("--keep-text", action="store_true", default=True)
    parser.add_argument("--source-name", default="hsk79_official_pdf")
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Exit 0 even if no tokens were extracted",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.date.today().isoformat()

    pdf_path: Path
    tmp_dir_obj = None
    if args.pdf:
        pdf_path = (repo_root / args.pdf) if not Path(args.pdf).is_absolute() else Path(args.pdf)
        if not pdf_path.exists():
            print(f"PDF not found: {pdf_path}")
            return 1
    else:
        url = args.url.strip() or DEFAULT_HSK79_URL
        try:
            tmp_dir_obj = tempfile.TemporaryDirectory(prefix="hsk79_pdf_")
            pdf_path = Path(tmp_dir_obj.name) / "hsk79.pdf"
            _download_pdf(url, pdf_path)
        except Exception as e:
            print(f"Failed to download PDF from URL: {url}")
            print(f"Error: {type(e).__name__}: {e}")
            print("Tip: download the file manually and rerun with --pdf /path/to/file.pdf")
            return 2

    text = ""
    lines: List[str] = []
    start = 0
    end = 0
    words: List[str] = []
    extraction_method = "textutil_window"
    try:
        text = _pdf_to_text(pdf_path)
        lines = [_normalize_line(line) for line in text.splitlines()]
        lines = [line for line in lines if line]
        start, end = _find_hsk79_window(lines)
        window = lines[start:end]
        words = _extract_tokens(window)
    except Exception:
        pass

    # Fallback for PDFs where textutil emits mostly raw binary text.
    if not words:
        extraction_method = "binary_stream_fallback"
        try:
            words = _extract_words_from_pdf_binary(pdf_path)
        except Exception as e:
            print(f"Failed to parse PDF via fallback: {type(e).__name__}: {e}")
            return 3

    if tmp_dir_obj is not None:
        tmp_dir_obj.cleanup()

    csv_path = out_dir / f"hsk79_vocab_raw_{stamp}.csv"
    json_path = out_dir / f"hsk79_vocab_raw_{stamp}.json"
    text_path = out_dir / f"hsk79_pdf_text_{stamp}.txt"

    with csv_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "hanzi",
                "pinyin",
                "meaning_en",
                "source_level",
                "source_name",
            ],
        )
        writer.writeheader()
        for word in words:
            writer.writerow(
                {
                    "hanzi": word,
                    "pinyin": "",
                    "meaning_en": "",
                    "source_level": "HSK7-9",
                    "source_name": args.source_name,
                }
            )

    summary = {
        "date": stamp,
        "source_name": args.source_name,
        "pdf_source": args.pdf if args.pdf else (args.url.strip() or DEFAULT_HSK79_URL),
        "extraction_method": extraction_method,
        "lines_total": len(lines),
        "window_start": start,
        "window_end": end,
        "window_lines": (end - start) if end >= start else 0,
        "extracted_count": len(words),
        "sample": words[:50],
        "output_csv": str(csv_path),
    }
    json_path.write_text(
        json.dumps(
            {
                "summary": summary,
                "words": words,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    if args.keep_text:
        text_path.write_text(text, encoding="utf-8")

    print("HSK7-9 extraction complete")
    print(f"CSV: {csv_path}")
    print(f"JSON: {json_path}")
    if args.keep_text:
        print(f"TEXT: {text_path}")
    print(f"Extracted words: {len(words)}")
    if not words and not args.allow_empty:
        print("ERROR: extracted 0 words from PDF. Provide a machine-readable source or run OCR first.")
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
