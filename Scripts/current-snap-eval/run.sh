#!/usr/bin/env bash
# Measures the on-device current pick (FoundationCurrentPicker) against a fixed
# Ocean: how often clearly related thoughts join their current, and how often
# unrelated or near-miss thoughts are wrongly merged into one. Compiles the
# shipping CurrentSnap + FoundationCurrentPicker sources verbatim, so the eval
# and the app always use the same prompt and schema. Runs on this Mac's
# Apple Intelligence model (macOS 26+); no API key.
#
# Usage:
#   ./run.sh [runs]     # runs per case, default 3

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

bin="$(mktemp -d -t current-snap-eval)/eval"
trap 'rm -rf "$(dirname "$bin")"' EXIT
xcrun swiftc -O -parse-as-library -o "$bin" \
  "$here/eval.swift" \
  "$repo/Shared/Services/CurrentSnap.swift" \
  "$repo/Oryne/Services/FoundationCurrentPicker.swift"
"$bin" "${1:-3}"
