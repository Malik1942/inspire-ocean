#!/usr/bin/env python3 -I
"""Generate Oryne/DesignSystem/OceanTokens.swift from design/tokens/oryne.tokens.json.

The JSON (W3C Design Tokens Community Group format, 2025.10) owns every shared
value and its intent. This script resolves aliases, checks the type scale and
writes the Swift the app reads, one container per token group:

    form.space      -> enum OceanSpacing      (CGFloat)
    form.radius     -> enum OceanRadius       (CGFloat)
    form.size       -> enum OceanSize         (CGFloat)
    form.control    -> enum OceanControlSize  (CGFloat)
    form.type       -> extension OceanType    (OceanTextRole text roles, Font glyphs)
    form.watchType  -> enum OceanWatchType    (OceanTextRole, the watch's own roles)
    material.color  -> extension OceanTheme   (Color, groups flattened)
    material.shadow -> enum OceanShadow       (OceanShadowValue)
    motion          -> enum OceanMotion       (Animation)

A text role is an OceanTextRole literal (Oryne/DesignSystem/OceanTextRole.swift):
its face, size, weight, leading and tracking together, with its size at each of
the twelve iOS text sizes, computed here from Apple's own ramp
(com.oryne.dynamicType). A glyph role (kind glyph) is a plain Font. Every run
checks the scale and fails on a com.oryne.order inversion at any text size, a
com.oryne.step drift, or a curve whose two styles do not bracket its size.
A role carries its own leading and tracking, so no separate *Size, *Leading or
*Tracking constants are written, and the retired scale metrics is refused
(native or curve). com.oryne.steps on a role writes <role>Steps, the weighted
title lengths at which it steps down a size. An ink with com.oryne.contrast
becomes OceanTheme.contrasting(_:increased:), which steps up with Increase
Contrast.

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
    ("form.watchType", "enum", "OceanWatchType", "Form: watch type"),
    ("material.color", "extension", "OceanTheme", "Material: color"),
    ("material.shadow", "enum", "OceanShadow", "Material: shadow"),
    ("motion", "enum", "OceanMotion", "Motion"),
]

# The phone's type group: it carries the Dynamic Type ramp and the scale's checks.
TYPE_GROUP = "form.type"
# The watch's roles use watchOS's own text styles, which the iOS ramp does not
# describe, so they carry no per-size table.
WATCH_TYPE_GROUP = "form.watchType"

WEIGHTS = {300: ".light", 400: ".regular", 500: ".medium", 600: ".semibold", 700: ".bold"}
TEXT_STYLES = {
    "largeTitle": ".largeTitle", "title1": ".title", "title2": ".title2", "title3": ".title3",
    "headline": ".headline", "body": ".body", "callout": ".callout", "subheadline": ".subheadline",
    "footnote": ".footnote", "caption": ".caption", "caption2": ".caption2",
}
DESIGNS = {"default": ".default", "serif": ".serif", "rounded": ".rounded", "monospaced": ".monospaced"}
CURVES = {"easeOut": "easeOut", "easeIn": "easeIn", "easeInOut": "easeInOut", "smooth": "smooth", "snappy": "snappy"}


class TokenError(Exception):
    """A token the generator refuses: the Swift is not written."""


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


class Ramp:
    """Apple's Dynamic Type ramp (com.oryne.dynamicType): each iOS text style's
    point size at every text size, xSmall through accessibility5."""

    def __init__(self, extension):
        self.names = extension["sizes"]
        self.styles = extension["ios"]
        if "large" not in self.names:
            raise TokenError("com.oryne.dynamicType.sizes has no large, the default size")
        self.large = self.names.index("large")
        for style, row in self.styles.items():
            if style not in TEXT_STYLES:
                raise TokenError("com.oryne.dynamicType: unknown text style " + style)
            if len(row) != len(self.names):
                raise TokenError("com.oryne.dynamicType: %s has %d sizes, not %d" % (style, len(row), len(self.names)))

    def row(self, style, role):
        if style not in self.styles:
            raise TokenError("%s: no Dynamic Type row for text style %s" % (role, style))
        return [float(size) for size in self.styles[style]]


class Role:
    """A text role as the checks see it: what it is set in and how it scales."""

    def __init__(self, name, ext, value, sizes):
        self.name = name
        self.design = ext.get("design", "default")
        self.size = float(value["fontSize"]["value"])
        self.weight = int(value["fontWeight"])
        self.italic = bool(ext.get("italic"))
        self.scale = (ext.get("scale", "native"), ext.get("textStyle"),
                      tuple(ext.get("between", ())), ext.get("relativeTo"))
        self.sizes = sizes

    def setting(self):
        """Everything a step must share with its ladder level; leading may differ."""
        return (self.design, self.size, self.weight, self.italic, self.scale, self.sizes)


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


def font_extension(node):
    return node.get("$extensions", {}).get("com.oryne.font", {})


def is_glyph(name, ext):
    kind = ext.get("kind", "text")
    if kind not in ("text", "glyph"):
        raise TokenError("%s: unknown font kind %s (text or glyph)" % (name, kind))
    return kind == "glyph"


def role_sizes(name, ext, value, ramp):
    """The role's point size at every text size, or None when it never scales.

    native takes its text style's row; a curve between two styles keeps the
    role's place between them at every size; a curve relative to one style
    scales in proportion to it. Rounded to 2 decimals.
    """
    scale = ext.get("scale", "native")
    size = float(value["fontSize"]["value"])
    if scale == "native":
        row = ramp.row(ext["textStyle"], name)
        if row[ramp.large] != size:
            raise TokenError("%s: %s is %s pt at large, not the role's %s, so its leading would scale from the wrong size"
                             % (name, ext["textStyle"], number(row[ramp.large]), number(size)))
        return row
    if scale == "curve":
        if "between" in ext:
            low, high = ext["between"]
            a, b = ramp.row(low, name), ramp.row(high, name)
            a_large, b_large = a[ramp.large], b[ramp.large]
            if not (a_large < b_large and a_large <= size <= b_large):
                raise TokenError("%s: between %s (%s) and %s (%s) does not bracket its %s pt at large"
                                 % (name, low, number(a_large), high, number(b_large), number(size)))
            t = (size - a_large) / (b_large - a_large)
            return [round(a[i] + t * (b[i] - a[i]), 2) for i in range(len(ramp.names))]
        if "relativeTo" in ext:
            row = ramp.row(ext["relativeTo"], name)
            return [round(size * row[i] / row[ramp.large], 2) for i in range(len(ramp.names))]
        raise TokenError("%s: a curve is sized between two text styles or relative to one" % name)
    if scale == "fixed":
        return None
    if scale == "metrics":
        raise TokenError("%s: scale metrics is retired: native or curve" % name)
    raise TokenError("%s: unknown font scale %s" % (name, scale))


def glyph(name, node, value, ext):
    scale = ext.get("scale", "native")
    design = DESIGNS[ext.get("design", "default")]
    weight = WEIGHTS[int(value["fontWeight"])]
    size = points(value["fontSize"])
    italic = ".italic()" if ext.get("italic") else ""
    if scale == "native":
        expr = "Font.system(%s, design: %s).weight(%s)%s" % (TEXT_STYLES[ext["textStyle"]], design, weight, italic)
    elif scale == "fixed":
        expr = "Font.system(size: %s, weight: %s, design: %s)%s" % (size, weight, design, italic)
    elif scale in ("curve", "metrics"):
        raise TokenError("%s: a glyph is native or fixed, never %s" % (name, scale))
    else:
        raise TokenError("%s: unknown font scale %s" % (name, scale))
    return doc(node) + "    static var %s: Font { %s }\n" % (name, expr)


def text_role(name, node, value, ext, sizes):
    scale = ext.get("scale", "native")
    if scale == "native":
        scale_expr = ".native(%s)" % TEXT_STYLES[ext["textStyle"]]
    elif scale == "curve":
        scale_expr = ".curve"
    else:
        scale_expr = ".fixed"
    leading = points(value["lineHeight"]) if "lineHeight" in value else "0"
    tracking = points(value["letterSpacing"]) if "letterSpacing" in value else "0"
    table = "nil" if sizes is None else "[%s]" % ", ".join(number(size) for size in sizes)
    out = doc(node) + (
        "    static let %s = OceanTextRole(\n"
        "        size: %s, weight: %s, design: %s, italic: %s,\n"
        "        scale: %s, leading: %s, tracking: %s,\n"
        "        sizes: %s)\n"
    ) % (name, points(value["fontSize"]), WEIGHTS[int(value["fontWeight"])], DESIGNS[ext.get("design", "default")],
         "true" if ext.get("italic") else "false", scale_expr, leading, tracking, table)
    steps = node.get("$extensions", {}).get("com.oryne.steps")
    if steps:
        out += "    /// The weighted lengths past which `%s` steps down a size.\n" % name
        out += "    static let %sSteps = (%s)\n" % (name, ", ".join("%s: %s" % (key, number(limit)) for key, limit in steps.items()))
    return out


def typography(path, name, node, value, ramp):
    ext = font_extension(node)
    if is_glyph(name, ext):
        return glyph(name, node, value, ext)
    if path == WATCH_TYPE_GROUP:
        if ext.get("scale", "native") not in ("native", "fixed"):
            raise TokenError("%s: a watch role is native or fixed (the watch has no ramp here)" % name)
        return text_role(name, node, value, ext, None)
    return text_role(name, node, value, ext, role_sizes(name, ext, value, ramp))


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


def ink(tokens, name, node, value):
    """A color; an ink that steps up with Increase Contrast resolves at run time."""
    contrast = node.get("$extensions", {}).get("com.oryne.contrast")
    if contrast is None:
        return doc(node) + "    static let %s = %s\n" % (name, color(value))
    return doc(node) + "    static let %s = OceanTheme.contrasting(%s, increased: %s)\n" % (
        name, color(value), color(tokens.resolve(contrast)))


def member(tokens, path, name, node, value, ramp):
    kind = node["$type"]
    if kind == "dimension":
        return doc(node) + "    static let %s: CGFloat = %s\n" % (name, points(value))
    if kind == "color":
        return ink(tokens, name, node, value)
    if kind == "typography":
        return typography(path, name, node, value, ramp)
    if kind == "shadow":
        return shadow(name, node, value)
    if kind == "transition":
        return motion(name, node, value)
    raise TokenError("no Swift for token type " + kind)


def check_scale(tokens, ramp):
    """The type scale's promises, on every run: no com.oryne.order chain
    inverts at any text size and each steps down at large; every
    com.oryne.step role is its ladder level in all but leading. (A curve's
    bracket is checked where its sizes are computed.)"""
    roles = {}
    for name, node, value in tokens.tokens(TYPE_GROUP):
        ext = font_extension(node)
        if node["$type"] == "typography" and not is_glyph(name, ext):
            roles[name] = Role(name, ext, value, role_sizes(name, ext, value, ramp))

    extensions = tokens.lookup(TYPE_GROUP).get("$extensions", {})
    for chain in extensions.get("com.oryne.order", []):
        for above, below in zip(chain, chain[1:]):
            for name in (above, below):
                if name not in roles:
                    raise TokenError("com.oryne.order: %s is not a text role" % name)
                if roles[name].sizes is None:
                    raise TokenError("com.oryne.order: %s never scales, so it has no order to keep" % name)
            a, b = roles[above].sizes, roles[below].sizes
            for index, size_name in enumerate(ramp.names):
                if a[index] < b[index]:
                    raise TokenError("com.oryne.order: %s (%s) falls under %s (%s) at %s"
                                     % (above, number(a[index]), below, number(b[index]), size_name))
            if not a[ramp.large] > b[ramp.large]:
                raise TokenError("com.oryne.order: %s must stand above %s at large (%s against %s)"
                                 % (above, below, number(a[ramp.large]), number(b[ramp.large])))

    for name, node, value in tokens.tokens(TYPE_GROUP):
        step = font_extension(node).get("step")
        if not step:
            continue
        if name not in roles or step not in roles:
            raise TokenError("%s: step %s must name a text role, and be one" % (name, step))
        if roles[name].setting() != roles[step].setting():
            raise TokenError("%s: drifted from its step %s (face, size, weight, italic, scale and sizes must match)"
                             % (name, step))


def generate(tokens):
    ramp = Ramp(tokens.lookup(TYPE_GROUP)["$extensions"]["com.oryne.dynamicType"])
    check_scale(tokens, ramp)
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
                raise TokenError("duplicate leaf name %s under %s" % (name, path))
            seen.add(name)
            out.append(member(tokens, path, name, node, value, ramp))
        out.append("}\n")
    return "".join(out)


def main(argv):
    with open(SOURCE, encoding="utf-8") as handle:
        tokens = Tokens(json.load(handle))
    try:
        swift = generate(tokens)
    except TokenError as error:
        sys.stderr.write("design tokens: %s\n" % error)
        return 1
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
