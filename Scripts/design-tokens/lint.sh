#!/bin/sh
# Finds raw visual values in views that should come from the tokens
# (design/tokens/oryne.tokens.json via OceanTokens.swift). The design system
# folder itself may hold raw values where a token is built; everything else
# names a role. Exit 1 when anything is found.
set -e
cd "$(dirname "$0")/../.."

paths="Oryne/Features Oryne/App ShareExtension OceanWidgets OryneWatch OryneWatchWidgets"
found=0

report() {
    label="$1"; shift
    # A line marked `art-directed` is a deliberate exception (see
    # design/tokens/README.md, "What stays expressive").
    hits=$(grep -rnE --include='*.swift' "$@" $paths | grep -v 'art-directed' || true)
    if [ -n "$hits" ]; then
        echo "== $label"
        echo "$hits"
        found=1
    fi
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

if [ "$found" -eq 1 ]; then
    echo "Raw visual values found. Name a role from OceanTokens.swift, or add one to design/tokens/oryne.tokens.json."
    exit 1
fi
echo "No raw visual values outside the design system."
