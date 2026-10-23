#!/usr/bin/env bash
# Runs the memory extractor (FoundationMemoryExtractor) over a fixed set of
# recent thoughts and prints what it proposes to remember about the person,
# with the thoughts each observation rests on. Compiles the shipping sources
# verbatim. Runs on this Mac's Apple Intelligence model (macOS 26+).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
bin="$(mktemp -d -t memory-eval)/eval"
trap 'rm -rf "$(dirname "$bin")"' EXIT
xcrun swiftc -O -parse-as-library -o "$bin" \
  "$here/eval.swift" \
  "$repo/Shared/Models/MemoryRecord.swift" \
  "$repo/Shared/Services/MemoryRules.swift" \
  "$repo/Shared/Services/ThemeDetector.swift" \
  "$repo/Shared/Services/AnswerMarkdown.swift" \
  "$repo/Oryne/Services/FoundationMemoryExtractor.swift"
"$bin"
