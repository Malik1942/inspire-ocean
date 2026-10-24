#!/usr/bin/env bash
# Runs the Ask agent (AskAgent: the on-device model with findThoughts,
# listThoughts and readThought over a fixed bilingual Ocean) on a set of
# questions and reports which thoughts it cited, whether it answered in the
# question's language, and how long it took. Compiles the shipping sources
# verbatim. Runs on this Mac's Apple Intelligence model (macOS 26+).
#
# Usage:
#   ./run.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

bin="$(mktemp -d -t ask-agent-eval)/eval"
trap 'rm -rf "$(dirname "$bin")"' EXIT
xcrun swiftc -O -parse-as-library -o "$bin" \
  "$here/eval.swift" \
  "$repo/Shared/Models/Enums.swift" \
  "$repo/Shared/Services/ThoughtReading.swift" \
  "$here/../eval/Fixture.swift" \
  "$here/../../Shared/Services/PictureReading.swift" \
  "$repo/Shared/Services/CurrentSnap.swift" \
  "$repo/Shared/Services/TitleDistiller.swift" \
  "$repo/Shared/Services/ThemeDetector.swift" \
  "$repo/Shared/Services/SemanticThemes.swift" \
  "$repo/Shared/Services/EmbeddingService.swift" \
  "$repo/Shared/Services/AnswerMarkdown.swift" \
  "$repo/Shared/Services/AskReferences.swift" \
  "$repo/Shared/Models/MemoryRecord.swift" \
  "$repo/Shared/Services/MemoryRules.swift" \
  "$repo/Oryne/Services/FoundationThoughtReader.swift" \
  "$repo/Oryne/Services/AskAgent.swift"
"$bin"
