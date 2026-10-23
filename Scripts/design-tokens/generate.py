#!/usr/bin/env python3 -I
"""Generate Oryne/DesignSystem/OceanTokens.swift from design/tokens/oryne.tokens.json.

The JSON (W3C Design Tokens Community Group format, 2025.10) owns every shared
value and its intent. This script resolves aliases and writes the Swift the app
reads, one container per token group:

    form.space      -> enum OceanSpacing      (CGFloat)
    form.radius     -> enum OceanRadius       (CGFloat)
    form.size       -> enum OceanSize         (CGFloat)
    form.control    -> enum OceanControlSize  (CGFloat)
    form.type       -> extension OceanType    (Font, plus leading and tracking)
    material.color  -> extension OceanTheme   (Color, groups flattened)
    material.shadow -> enum OceanShadow       (OceanShadowValue)
    motion          -> enum OceanMotion       (Animation)

Usage:  python3 -I Scripts/design-tokens/generate.py [--check]
--check writes nothing and exits 1 when the committed Swift is out of date.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "design", "tokens", "oryne.tokens.json")
TARGET = os.path.join(ROOT, "Oryne", "DesignSystem", "OceanTokens.swift")

CONTAINERS = [
    ("form.space", "enum", "OceanSpacing", "Form: space"),
    ("form.radius", "enum", "OceanRadius", "Form: radius"),
    ("form.size", "enum", "OceanSize", "Form: size"),
    ("form.control", "enum", "OceanControlSize", "Form: control"),
    ("form.type", "extension", "OceanType", "Form: type"),
    ("material.color", "extension", "OceanTheme", "Material: color"),
    ("material.shadow", "enum", "OceanShadow", "Material: shadow"),
    ("motion", "enum", "OceanMotion", "Motion"),
]

WEIGHTS = {300: ".light", 400: ".regular", 500: ".medium", 600: ".semibold", 700: ".bold"}
TEXT_STYLES = {
    "largeTitle": ".largeTitle", "title1": ".title", "title2": ".title2", "title3": ".title3",
    "headline": ".headline", "body": ".body", "callout": ".callout", "subheadline": ".subheadline",
    "footnote": ".footnote", "caption": ".caption", "caption2": ".caption2",
}
DESIGNS = {"default": ".default", "serif": ".serif", "rounded": ".rounded", "monospaced": ".monospaced"}
CURVES = {"easeOut": "easeOut", "easeIn": "easeIn", "easeInOut": "easeInOut", "smooth": "smooth", "snappy": "snappy"}


class Tokens:
    def __init__(self, tree):
        self.tree = tree
        self.cache = {}

    def lookup(self, path):
        node = self.tree
        for part in path.split("."):
            if part not in node:
                raise KeyError("no token at " + path)
            node = node[part]
        return node

    def resolve(self, value):
        """Replace every alias ("{a.b.c}") inside a value with the token's resolved $value."""
        if isinstance(value, str):
            match = re.fullmatch(r"\{([^}]+)\}", value)
            if match:
                return self.value(match.group(1))
            return value
        if isinstance(value, dict):
            return {key: self.resolve(item) for key, item in value.items()}
        if isinstance(value, list):
            return [self.resolve(item) for item in value]
        return value

    def value(self, path):
        if path not in self.cache:
            self.cache[path] = self.resolve(self.lookup(path)["$value"])
        return self.cache[path]

    def tokens(self, group_path):
        """Every token under a group, depth first, as (name, node, resolved value)."""
        found = []

        def walk(node, name):
            for key, item in node.items():
                if key.startswith("$"):
                    continue
                if "$value" in item:
                    found.append((key, item, self.resolve(item["$value"])))
                else:
                    walk(item, key)

        walk(self.lookup(group_path), group_path)
        return found


def number(x):
    text = ("%.6f" % float(x)).rstrip("0").rstrip(".")
    return text if text else "0"


def points(dimension):
    assert dimension["unit"] == "px", "dimensions are in points, written as px"
    return number(dimension["value"])


def seconds(duration):
    assert duration["unit"] == "ms"
    return number(float(duration["value"]) / 1000)


def color(value):
    r, g, b = value["components"]
    return "Color(.sRGB, red: %s, green: %s, blue: %s, opacity: %s)" % (
        number(r), number(g), number(b), number(value.get("alpha", 1)))


def doc(node, indent="    "):
    text = node.get("$description")
    if not text:
        return ""
    return "".join("%s/// %s\n" % (indent, line) for line in wrap(text))


def wrap(text, width=76):
    words, lines, line = text.split(), [], ""
    for word in words:
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = word
        else:
            line = (line + " " + word).strip()
    if line:
        lines.append(line)
    return lines


def font(name, node, value):
    ext = node.get("$extensions", {}).get("com.oryne.font", {})
    scale = ext.get("scale", "native")
    design = DESIGNS[ext.get("design", "default")]
    weight = WEIGHTS[int(value["fontWeight"])]
    size = points(value["fontSize"])
    italic = ".italic()" if ext.get("italic") else ""
    lines = []
    if scale == "native":
        style = TEXT_STYLES[ext["textStyle"]]
        expr = "Font.system(%s, design: %s).weight(%s)%s" % (style, design, weight, italic)
    elif scale == "metrics":
        style = TEXT_STYLES[ext["textStyle"]]
        expr = "OceanFont.metrics(size: %s, weight: %s, design: %s, italic: %s, relativeTo: %s)" % (
            size, weight, design, "true" if ext.get("italic") else "false", style)
        lines.append("    /// The point size `%s` is built from, for UIKit appearances.\n    static let %sSize: CGFloat = %s\n" % (
            name, name, size))
    elif scale == "fixed":
        expr = "Font.system(size: %s, weight: %s, design: %s)%s" % (size, weight, design, italic)
    else:
        raise ValueError("unknown font scale " + scale)
    lines.append(doc(node) + "    static var %s: Font { %s }\n" % (name, expr))
    if "lineHeight" in value:
        lines.append("    /// Extra leading between lines of `%s`.\n    static let %sLeading: CGFloat = %s\n" % (
            name, name, points(value["lineHeight"])))
    if "letterSpacing" in value:
        lines.append("    /// Tracking for `%s`.\n    static let %sTracking: CGFloat = %s\n" % (
            name, name, points(value["letterSpacing"])))
    return "".join(lines)


def shadow(name, node, value):
    return doc(node) + "    static let %s = OceanShadowValue(color: %s, radius: %s, x: %s, y: %s)\n" % (
        name, color(value["color"]), points(value["blur"]), points(value["offsetX"]), points(value["offsetY"]))


def motion(name, node, value):
    ext = node.get("$extensions", {})
    curve = ext.get("com.oryne.curve")
    duration = seconds(value["duration"])
    if curve == "spring":
        spring = ext["com.oryne.spring"]
        expr = "Animation.spring(response: %s, dampingFraction: %s)" % (
            number(spring["response"]), number(spring["dampingFraction"]))
    elif curve in CURVES:
        expr = "Animation.%s(duration: %s)" % (CURVES[curve], duration)
    else:
        x1, y1, x2, y2 = value["timingFunction"]
        expr = "Animation.timingCurve(%s, %s, %s, %s, duration: %s)" % (
            number(x1), number(y1), number(x2), number(y2), duration)
    return doc(node) + "    static let %s = %s\n" % (name, expr)


def member(name, node, value):
    kind = node["$type"]
    if kind == "dimension":
        return doc(node) + "    static let %s: CGFloat = %s\n" % (name, points(value))
    if kind == "color":
        return doc(node) + "    static let %s = %s\n" % (name, color(value))
    if kind == "typography":
        return font(name, node, value)
    if kind == "shadow":
        return shadow(name, node, value)
    if kind == "transition":
        return motion(name, node, value)
    raise ValueError("no Swift for token type " + kind)


def generate(tokens):
    out = [
        "// OceanTokens.swift\n",
        "//\n",
        "// GENERATED by Scripts/design-tokens/generate.py from design/tokens/oryne.tokens.json.\n",
        "// Do not edit: change the JSON and run the script. Every value here is a role;\n",
        "// the JSON's $description says what the role is for.\n",
        "//\n",
        "// Compiled into the app, the share extension, the widgets and the watch,\n",
        "// so it imports SwiftUI only.\n",
        "\n",
        "import SwiftUI\n",
    ]
    for path, kind, swift_name, title in CONTAINERS:
        group = tokens.lookup(path)
        out.append("\n// MARK: - %s\n\n" % title)
        out.append(doc(group, ""))
        out.append("%s %s {\n" % (kind, swift_name))
        seen = set()
        for name, node, value in tokens.tokens(path):
            if name in seen:
                raise ValueError("duplicate leaf name %s under %s" % (name, path))
            seen.add(name)
            out.append(member(name, node, value))
        out.append("}\n")
    return "".join(out)


def main(argv):
    with open(SOURCE, encoding="utf-8") as handle:
        tokens = Tokens(json.load(handle))
    swift = generate(tokens)
    if "--check" in argv:
        current = open(TARGET, encoding="utf-8").read() if os.path.exists(TARGET) else ""
        if current != swift:
            sys.stderr.write("OceanTokens.swift is out of date: run Scripts/design-tokens/generate.py\n")
            return 1
        print("OceanTokens.swift matches design/tokens/oryne.tokens.json")
        return 0
    with open(TARGET, "w", encoding="utf-8") as handle:
        handle.write(swift)
    print("wrote " + os.path.relpath(TARGET, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
