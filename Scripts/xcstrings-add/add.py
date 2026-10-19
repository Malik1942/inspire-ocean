#!/usr/bin/env python3
"""Add keys with zh-Hans values to an Xcode string catalog (.xcstrings).

Value-as-key catalogs (the English text is the key): each pair becomes a key
whose zh-Hans stringUnit is marked needs_review, the way the app's existing
Chinese entries are flagged. Existing keys are left untouched, and a missing
catalog is created. The file is written back in Xcode's own formatting
(2-space indent, " : " separators, empty objects spread over a blank line,
no trailing newline), so a diff shows only the new keys. Round-tripping
Oryne/Resources/Localizable.xcstrings with no pairs is byte-identical.

Usage: add.py <catalog.xcstrings> <pairs.json>
  pairs.json: {"English text": "中文", ...}
"""
import json
import re
import sys
from pathlib import Path


def write_xcode_json(path: Path, data: dict) -> None:
    out = json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : "))
    out = re.sub(
        r"(?m)^(\s*)(.*) : \{\}(,?)$",
        lambda m: f"{m.group(1)}{m.group(2)} : {{\n\n{m.group(1)}}}{m.group(3)}",
        out,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(out, encoding="utf-8")


def main(catalog_path: str, pairs_path: str) -> None:
    catalog = Path(catalog_path)
    if catalog.exists():
        data = json.loads(catalog.read_text(encoding="utf-8"))
    else:
        data = {"sourceLanguage": "en", "strings": {}, "version": "1.1"}
    pairs = json.loads(Path(pairs_path).read_text(encoding="utf-8"))
    added = 0
    for key, zh in pairs.items():
        if key in data["strings"]:
            continue
        data["strings"][key] = {
            "localizations": {"zh-Hans": {"stringUnit": {"state": "needs_review", "value": zh}}}
        }
        added += 1
    write_xcode_json(catalog, data)
    print(f"{catalog}: added {added}, skipped {len(pairs) - added}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
