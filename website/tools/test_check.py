"""Tests for tools/check.py.

Run: python3 -m unittest discover -s website/tools -p 'test_*.py' -v
"""

import tempfile
import unittest
from pathlib import Path

import check

PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<link rel="alternate" hreflang="en" href="{en}">
<link rel="alternate" hreflang="zh-Hans" href="{zh}">
<link rel="alternate" hreflang="x-default" href="{en}">
<link rel="stylesheet" href="{prefix}assets/site.css">
</head>
<body>
<section id="top" data-chapter="top">
<p>{copy}</p>
<a href="privacy.html">Privacy</a>
<a href="#faq">FAQ</a>
<a href="https://apps.apple.com/app/id123">App Store</a>
<a href="{switch}" data-lang-switch="{other}">{other}</a>
</section>
{extra}
</body>
</html>
"""


def build(root, en_copy="Catch ideas.", zh_copy="留住灵感。", zh_extra=""):
    (root / "assets").mkdir()
    (root / "assets" / "site.css").write_text("", encoding="utf-8")
    (root / "zh").mkdir()
    for name in check.PAGES:
        (root / name).write_text(PAGE.format(
            lang="en", en="./", zh="zh/", prefix="", copy=en_copy,
            switch="zh/", other="zh-Hans", extra=""), encoding="utf-8")
        (root / "zh" / name).write_text(PAGE.format(
            lang="zh-Hans", en="../", zh="./", prefix="../", copy=zh_copy,
            switch="../", other="en", extra=zh_extra), encoding="utf-8")


class CheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_clean_site_passes(self):
        build(self.root)
        errors, warnings = check.run(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])

    def test_an_em_dash_in_copy_is_an_error(self):
        build(self.root, en_copy="Catch ideas — now.")
        errors, _ = check.run(self.root)
        self.assertTrue(any("em dash" in e for e in errors), errors)

    def test_an_en_dash_in_copy_is_an_error(self):
        build(self.root, zh_copy="iOS 18–26")
        errors, _ = check.run(self.root)
        self.assertTrue(any("en dash" in e for e in errors), errors)

    def test_a_missing_asset_is_an_error(self):
        build(self.root)
        (self.root / "assets" / "site.css").unlink()
        errors, _ = check.run(self.root)
        self.assertTrue(any("missing file" in e and "site.css" in e for e in errors), errors)

    def test_host_served_paths_are_not_missing_files(self):
        build(self.root)
        for page in list(check.PAGES) + [f"zh/{name}" for name in check.PAGES]:
            path = self.root / page
            path.write_text(path.read_text(encoding="utf-8").replace(
                "</head>", '<script defer src="/_vercel/insights/script.js"></script></head>'), encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_structural_drift_between_languages_is_an_error(self):
        build(self.root, zh_extra='<section id="extra" data-chapter="deep"></section>')
        errors, _ = check.run(self.root)
        self.assertTrue(any("differ in ids" in e for e in errors), errors)
        self.assertTrue(any("differ in data-chapter" in e for e in errors), errors)

    def test_language_switches_are_not_compared(self):
        build(self.root)  # the switches point in opposite directions by design
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_localized_assets_are_not_compared(self):
        build(self.root)
        (self.root / "assets" / "badge-en.svg").write_text("<svg/>", encoding="utf-8")
        (self.root / "assets" / "badge-zh.svg").write_text("<svg/>", encoding="utf-8")
        for name in check.PAGES:
            for page, badge in ((self.root / name, "assets/badge-en.svg"),
                                (self.root / "zh" / name, "../assets/badge-zh.svg")):
                html = page.read_text(encoding="utf-8").replace(
                    "</section>", f'<img src="{badge}" data-lang-asset alt=""></section>', 1)
                page.write_text(html, encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_placeholders_warn_but_do_not_fail(self):
        build(self.root, en_copy="Get it at id0000000000 or write support@example.com")
        errors, warnings = check.run(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 2 * len(check.PAGES), warnings)

    def test_only_skips_parity(self):
        build(self.root, zh_extra='<section id="extra" data-chapter="deep"></section>')
        errors, _ = check.run(self.root, only="en")
        self.assertEqual(errors, [])

    def test_missing_alternates_are_an_error(self):
        build(self.root)
        page = self.root / "index.html"
        page.write_text(page.read_text(encoding="utf-8").replace(
            'hreflang="x-default"', 'hreflang="fr"'), encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertTrue(any("x-default" in e for e in errors), errors)

    def test_canonical_links_may_differ_per_language(self):
        build(self.root)
        for name, url in (("index.html", "https://example.com/"),
                          ("zh/index.html", "https://example.com/zh/")):
            page = self.root / name
            page.write_text(page.read_text(encoding="utf-8").replace(
                "</head>", f'<link rel="canonical" href="{url}">\n</head>'), encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_a_missing_counterpart_page_is_an_error(self):
        build(self.root)
        (self.root / "zh" / "support.html").unlink()
        errors, _ = check.run(self.root)
        self.assertTrue(any("zh/support.html" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
