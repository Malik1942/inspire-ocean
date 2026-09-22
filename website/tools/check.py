#!/usr/bin/env python3
"""Static checks for the Oryne website. Standard library only.

    python3 website/tools/check.py            # both languages, with parity
    python3 website/tools/check.py --only en  # one tree, no parity

Errors fail the run (exit 1):
  - an em or en dash anywhere in a page (house rule: none in UI copy)
  - a relative link or asset that does not resolve to a file
  - <html lang> missing, or hreflang alternates for en, zh-Hans, x-default missing
  - a page missing from either language tree
  - an English page and its Chinese counterpart differing in structure:
    element ids (in order), the data-chapter sequence, or links and assets
    (language switches, per-language assets, hreflang alternates, and the
    canonical link excluded)
Warnings do not fail the run:
  - placeholders still in place (App Store URL, support email)
"""

import argparse
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SITE = Path(__file__).resolve().parent.parent
PAGES = ("index.html", "privacy.html", "support.html")
DASHES = {"—": "em dash", "–": "en dash"}
PLACEHOLDERS = {
    "id0000000000": "the App Store URL is still the placeholder",
    "support@example.com": "the support email is still the placeholder",
}
REF_ATTRS = {"a": "href", "link": "href", "img": "src", "script": "src", "source": "srcset"}


class PageScan(HTMLParser):
    """Collects what the checks compare: lang, alternates, ids, chapters, refs."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.hreflangs = set()
        self.ids = []
        self.chapters = []
        self.refs = []  # (tag, url, excluded_from_parity)

    def handle_starttag(self, tag, attrs):
        a = {name: value or "" for name, value in attrs}
        if tag == "html":
            self.lang = a.get("lang")
        alternate = tag == "link" and a.get("rel") == "alternate" and "hreflang" in a
        canonical = tag == "link" and a.get("rel") == "canonical"
        if alternate:
            self.hreflangs.add(a["hreflang"])
        if a.get("id"):
            self.ids.append(a["id"])
        if "data-chapter" in a:
            self.chapters.append(a["data-chapter"])
        attr = REF_ATTRS.get(tag)
        if attr and a.get(attr):
            excluded = alternate or canonical or "data-lang-switch" in a or "data-lang-asset" in a
            if attr == "srcset":
                urls = [part.strip().split(" ")[0] for part in a[attr].split(",")]
            else:
                urls = [a[attr]]
            self.refs.extend((tag, url, excluded) for url in urls if url)


# Paths the host serves itself, not files in this folder: Vercel's analytics script.
HOST_PATHS = ("/_vercel/",)


def is_local(url):
    parts = urlsplit(url)
    if not parts.scheme and not parts.netloc and parts.path.startswith(HOST_PATHS):
        return False
    return not parts.scheme and not parts.netloc and bool(parts.path)


def resolve(page, url):
    path = urlsplit(url).path
    target = (page.parent / path).resolve()
    if path.endswith("/") or target.is_dir():
        target = target / "index.html"
    return target


def scan_page(site, page, errors, warnings):
    text = page.read_text(encoding="utf-8")
    rel = page.relative_to(site).as_posix()
    for lineno, line in enumerate(text.splitlines(), 1):
        for char, name in DASHES.items():
            if char in line:
                errors.append(f"{rel}:{lineno}: {name} (copy rule: use a comma, colon, or period)")
    for token, message in PLACEHOLDERS.items():
        if token in text:
            warnings.append(f"{rel}: {message}")
    scan = PageScan()
    scan.feed(text)
    if scan.lang not in ("en", "zh-Hans"):
        errors.append(f"{rel}: <html lang> must be en or zh-Hans, found {scan.lang!r}")
    missing = {"en", "zh-Hans", "x-default"} - scan.hreflangs
    if missing:
        errors.append(f"{rel}: missing hreflang alternates: {', '.join(sorted(missing))}")
    for tag, url, _ in scan.refs:
        if is_local(url) and not resolve(page, url).exists():
            errors.append(f"{rel}: <{tag}> points at a missing file: {url}")
    return scan


def structure_refs(site, page, scan, strip_zh):
    """Links and assets in order, normalized so both language trees compare equal."""
    out = []
    for tag, url, excluded in scan.refs:
        if excluded:
            continue
        if not is_local(url):
            out.append((tag, url))
            continue
        try:
            key = resolve(page, url).relative_to(site).as_posix()
        except ValueError:
            key = f"outside-site:{url}"
        if strip_zh and key.startswith("zh/"):
            key = key[len("zh/"):]
        fragment = urlsplit(url).fragment
        out.append((tag, key + (f"#{fragment}" if fragment else "")))
    return out


def first_difference(a, b):
    for index, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return f"item {index}: {x!r} vs {y!r}"
    return f"lengths {len(a)} vs {len(b)}"


def run(site, only=None):
    site = Path(site).resolve()
    errors, warnings = [], []
    trees = {"en": site, "zh": site / "zh"}
    found = {}
    for lang in ([only] if only else ["en", "zh"]):
        for name in PAGES:
            page = trees[lang] / name
            if not page.exists():
                errors.append(f"missing page: {page.relative_to(site).as_posix()}")
                continue
            scan = scan_page(site, page, errors, warnings)
            found[(lang, name)] = {
                "ids": scan.ids,
                "data-chapter": scan.chapters,
                "links and assets": structure_refs(site, page, scan, strip_zh=(lang == "zh")),
            }
    if not only:
        for name in PAGES:
            en, zh = found.get(("en", name)), found.get(("zh", name))
            if not (en and zh):
                continue
            for label in ("ids", "data-chapter", "links and assets"):
                if en[label] != zh[label]:
                    errors.append(f"{name}: English and Chinese differ in {label}: "
                                  f"{first_difference(en[label], zh[label])}")
    return errors, warnings


def main(argv=None):
    parser = argparse.ArgumentParser(description="Static checks for the Oryne website.")
    parser.add_argument("--only", choices=("en", "zh"), help="check one language tree and skip parity")
    parser.add_argument("--site", type=Path, default=SITE, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    errors, warnings = run(args.site, args.only)
    for warning in warnings:
        print(f"warning: {warning}")
    for error in errors:
        print(f"error: {error}")
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
