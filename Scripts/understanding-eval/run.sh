#!/usr/bin/env bash
# Runs the on-device thought reader (FoundationThoughtReader) over a fixed
# bilingual set of entries and reports category accuracy, whether the gist
# landed in the other language, the theme keys, entities and latency.
# Compiles the shipping ThoughtReading + FoundationThoughtReader sources
# verbatim, so the eval and the app always use the same prompt and schema.
# Runs on this Mac's Apple Intelligence model (macOS 26+); no API key.
#
# Usage:
#   ./run.sh [runs]     # runs per entry, default 1

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

bin="$(mktemp -d -t understanding-eval)/eval"
trap 'rm -rf "$(dirname "$bin")"' EXIT
xcrun swiftc -O -parse-as-library -o "$bin" \
  "$here/eval.swift" \
  "$repo/Shared/Models/Enums.swift" \
  "$repo/Shared/Services/ThoughtReading.swift" \
  "$here/../eval/Fixture.swift" \
  "$here/../../Shared/Services/PictureReading.swift" \
  "$repo/Oryne/Services/FoundationThoughtReader.swift"
"$bin" "${1:-1}"
