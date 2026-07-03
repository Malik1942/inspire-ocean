#!/usr/bin/env python3
"""Extract each non-archived node's searchable text from an Oryne SwiftData
store, so the floor sweep can score real fragments the same way the app does.

The output mirrors Node.searchableText (Shared/Models/Node.swift): title, text,
and conceptual themes joined by spaces. Themes are stored as an NSKeyedArchiver
blob, so they are decoded with plistlib. Prints a JSON array of
{pk, title, searchable} to stdout.

Usage: extract.py <path-to-InspireOcean.store>
"""
import json
import plistlib
import sqlite3
import sys


def themes(blob):
    """Decode the NSKeyedArchiver [String] blob into plain theme strings."""
    if not blob:
        return []
    try:
        obj = plistlib.loads(blob)
    except Exception:
        return []
    objects = obj.get("$objects", [])
    return [
        o for o in objects
        if isinstance(o, str)
        and o != "$null"
        and not o.startswith("NS")
        and "Archiver" not in o
        and len(o) > 1
    ]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: extract.py <path-to-InspireOcean.store>")
    store = sys.argv[1]
    con = sqlite3.connect(store)
    rows = con.execute(
        "SELECT Z_PK, ZTITLE, ZTEXT, ZTHEMES FROM ZNODE "
        "WHERE ZISARCHIVED = 0 OR ZISARCHIVED IS NULL "
        "ORDER BY ZCREATEDAT"
    ).fetchall()

    out = []
    for pk, title, text, theme_blob in rows:
        parts = [p for p in (title or "", text or "", " ".join(themes(theme_blob))) if p]
        out.append({"pk": pk, "title": title or "", "searchable": " ".join(parts)})

    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
