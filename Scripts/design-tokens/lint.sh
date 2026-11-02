#!/bin/sh
# Finds raw visual values in views that should come from the tokens
# (design/tokens/oryne.tokens.json via OceanTokens.swift). The design system
# folder itself may hold raw values where a token is built; everything else
# names a role. A text role's leading and tracking are part of the role, and
# faint never sets words, so those checks read the design system too, all but
# the two files that build the roles. Exit 1 when anything is found.
set -e
cd "$(dirname "$0")/../.."

paths="Oryne/Features Oryne/App ShareExtension OceanWidgets OryneWatch OryneWatchWidgets"
# The views and the design system. Checks over it exclude
# OceanTextRole.swift, which sets each role's leading and tracking, and the
# generated OceanTokens.swift.
everywhere="$paths Oryne/DesignSystem"
found=0

# Searches the given paths; any grep options (an --exclude) go before the
# pattern.
report_in() {
    where="$1"; label="$2"; shift 2
    # A line marked `art-directed` is a deliberate exception (see
    # design/tokens/README.md, "What stays expressive").
    hits=$(grep -rnE --include='*.swift' "$@" $where | grep -v 'art-directed' || true)
    if [ -n "$hits" ]; then
        echo "== $label"
        echo "$hits"
        found=1
    fi
}

# Searches the views.
report() {
    label="$1"; shift
    report_in "$paths" "$label" "$@"
}

report "raw white/black opacity (use OceanTheme ink and surface roles)" \
    '(Color\.)?(white|black)\.opacity\('
report "raw corner radius (use OceanRadius)" \
    'cornerRadius: *[0-9]'
report "raw font size (use OceanType)" \
    '\.system\(size: *[0-9]'
report "raw system text style (use OceanType roles)" \
    '\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)'
report "raw animation (use OceanMotion)" \
    '\.(easeOut|easeIn|easeInOut|spring|smooth|snappy|timingCurve)\('
report "raw shadow (use OceanShadow)" \
    '\.shadow\(color:'
report_in "$everywhere" "hand-set leading or tracking (part of the text role: .oceanText)" \
    --exclude='OceanTextRole.swift' --exclude='OceanTokens.swift' \
    '\.(lineSpacing|tracking|kerning)\('
report_in "$everywhere" "faint words (faint is never words or a glyph that means something: use mist)" \
    --exclude='OceanTextRole.swift' --exclude='OceanTokens.swift' \
    'foregroundStyle\(OceanTheme\.faint'
report "a scale floor under 0.9 (reading text never shrinks; a widget's title may, to 0.9)" \
    'minimumScaleFactor\(0\.[0-8]'
report "a face set by hand (New York and monospaced come with a text role: .oceanText)" \
    'design: *\.(serif|monospaced)'

if [ "$found" -eq 1 ]; then
    echo "Raw visual values found. Name a role from OceanTokens.swift, or add one to design/tokens/oryne.tokens.json."
    exit 1
fi
echo "No raw visual values outside the design system, and no hand-set leading, tracking or faint words in it."
