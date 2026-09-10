#!/usr/bin/env python3
"""
Fuzzy-match a user-supplied project keyword against the HAP 项目档案 JSON.

Usage:
    python match_project.py <projects_full.json> <keyword> [--top N]

Input JSON expected structure:
    {"data": {"rows": [{"rowid": "...", "<name_controlId>": "项目名", ...}, ...]}}

Output (stdout): JSON array of {rowid, name, score, reason}, sorted by score desc.
Exit code: 0 always (the agent decides what to do with empty / low-score results).

Score bands:
    100  exact substring (keyword ⊆ name OR name ⊆ keyword)
    70~99  every keyword token appears in name (in order)
    40~69  char overlap >= 60% of shorter side, no full-token match
    <40   filtered out by default

Pure stdlib. No external deps.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


NAME_CONTROL_IDS = (
    "65e57b98af2cbab9cc8bb162",  # 项目档案 name controlId
    "name",
    "title",
)


def load_projects(path: Path) -> list[dict]:
    """Load the 项目档案 JSON and extract [{rowid, name}, ...] rows."""
    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    rows: list[dict]
    if isinstance(data, dict) and isinstance(data.get("data"), dict):
        rows = data["data"].get("rows") or []
    elif isinstance(data, list):
        rows = data
    else:
        rows = data.get("rows") if isinstance(data, dict) else []

    cleaned: list[dict] = []
    for r in rows:
        if not isinstance(r, dict) or not r.get("rowid"):
            continue
        name = ""
        for k in NAME_CONTROL_IDS:
            if k in r and isinstance(r[k], str) and r[k].strip():
                name = r[k].strip()
                break
        if name:
            cleaned.append({"rowid": r["rowid"], "name": name})
    return cleaned


def tokenize(text: str) -> list[str]:
    """Split on non-CJK boundaries; CJK chars are kept whole, ASCII words split."""
    text = text.lower().strip()
    # Latin words
    parts = re.findall(r"[a-z0-9]+", text)
    # CJK chars individually (1-gram)
    cjk = re.findall(r"[\u4e00-\u9fff]", text)
    return parts + cjk


def char_set(text: str) -> set[str]:
    return set(text.lower())


def score_pair(keyword: str, name: str) -> tuple[int, str]:
    """Return (score, reason) for keyword against project name."""
    if not keyword or not name:
        return (0, "empty")
    kw = keyword.lower().strip()
    nm = name.lower().strip()

    # 1. Exact substring match
    if kw in nm or nm in kw:
        return (100, f"exact substring ({kw} ↔ {nm})")

    kw_tokens = tokenize(keyword)
    nm_tokens = tokenize(name)

    # 2. Every keyword token appears in name (in any order)
    if kw_tokens:
        hits = [t for t in kw_tokens if t in nm_tokens]
        if hits and len(hits) == len(kw_tokens):
            ratio = sum(len(t) for t in hits) / max(len(kw), 1)
            base = 70 + min(29, int(ratio * 30))
            return (base, f"all tokens matched ({hits})")

    # 3. Char-set Jaccard / overlap
    kw_set, nm_set = char_set(keyword), char_set(name)
    if not kw_set or not nm_set:
        return (0, "no char overlap")
    overlap = len(kw_set & nm_set)
    ratio = overlap / min(len(kw_set), len(nm_set))
    if ratio >= 0.6:
        base = 40 + min(29, int((ratio - 0.6) * 73))  # 0.6→40, 1.0→69
        return (base, f"char overlap {ratio:.0%}")

    return (0, f"weak match (overlap {ratio:.0%})")


def match(projects: list[dict], keyword: str, top: int) -> list[dict]:
    scored: list[dict] = []
    for p in projects:
        s, reason = score_pair(keyword, p["name"])
        if s <= 0:
            continue
        scored.append({"rowid": p["rowid"], "name": p["name"], "score": s, "reason": reason})
    scored.sort(key=lambda x: (-x["score"], len(x["name"])))
    return scored[:top]


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("projects_json", type=Path, help="Path to projects_full.json")
    parser.add_argument("keyword", type=str, help="User-supplied project keyword")
    parser.add_argument("--top", type=int, default=5, help="Max results to return (default 5)")
    parser.add_argument("--min-score", type=int, default=0, help="Drop results below this score (default 0 = show all positive)")
    args = parser.parse_args(argv)

    if not args.projects_json.exists():
        print(json.dumps({"error": f"file not found: {args.projects_json}"}, ensure_ascii=False), file=sys.stdout)
        return 1

    try:
        projects = load_projects(args.projects_json)
    except (json.JSONDecodeError, KeyError, UnicodeDecodeError) as e:
        print(json.dumps({"error": f"parse failed: {e}"}, ensure_ascii=False), file=sys.stdout)
        return 1

    results = match(projects, args.keyword, args.top)
    results = [r for r in results if r["score"] >= args.min_score]

    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())