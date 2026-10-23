#!/usr/bin/env bash
# The harness: every eval, on the one fixture (Fixture.swift), several runs,
# against thresholds. Each eval prints one `RESULT <eval> k=v …` line per run;
# this compiles each once, runs it N times, and reports the worst run and the
# mean per metric with PASS or FAIL. Exit status is the verdict.
#
#   Scripts/eval/run.sh [runs]        default 3
#   Scripts/eval/run.sh 1 ask         one eval only (understanding|snap|ask|memory)

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
runs="${1:-3}"
only="${2:-}"
out="$(mktemp -d -t oryne-eval)"

compile() {  # name, sources…
  local name="$1"; shift
  xcrun swiftc -O -parse-as-library -o "$out/$name" "$@" 2>&1 | grep -E 'error' && return 1
  return 0
}

shared=("$repo/Shared/Models/Enums.swift" "$repo/Shared/Services/ThoughtReading.swift" "$repo/Shared/Services/PictureReading.swift" "$here/Fixture.swift")

# macOS ships bash 3: no associative arrays, so a function maps names to sources.
sources_for() {
  case "$1" in
    understanding) echo "$repo/Scripts/understanding-eval/eval.swift $repo/Oryne/Services/FoundationThoughtReader.swift" ;;
    snap) echo "$repo/Scripts/current-snap-eval/eval.swift $repo/Shared/Services/CurrentSnap.swift $repo/Shared/Services/EmbeddingService.swift $repo/Oryne/Services/FoundationCurrentPicker.swift" ;;
    ask) echo "$repo/Scripts/ask-agent-eval/eval.swift $repo/Shared/Services/CurrentSnap.swift $repo/Shared/Services/TitleDistiller.swift $repo/Shared/Services/ThemeDetector.swift $repo/Shared/Services/SemanticThemes.swift $repo/Shared/Services/EmbeddingService.swift $repo/Shared/Services/AnswerMarkdown.swift $repo/Shared/Services/AskReferences.swift $repo/Oryne/Services/FoundationThoughtReader.swift $repo/Oryne/Services/AskAgent.swift" ;;
    memory) echo "$repo/Scripts/memory-eval/eval.swift $repo/Shared/Models/MemoryRecord.swift $repo/Shared/Services/MemoryRules.swift $repo/Shared/Services/ThemeDetector.swift $repo/Shared/Services/AnswerMarkdown.swift $repo/Oryne/Services/FoundationMemoryExtractor.swift" ;;
  esac
}

results="$out/results.txt"; : > "$results"
for name in understanding snap ask memory; do
  [ -n "$only" ] && [ "$only" != "$name" ] && continue
  # shellcheck disable=SC2086
  if ! compile "$name" $(sources_for "$name") "${shared[@]}"; then echo "compile failed: $name"; exit 2; fi
  for ((i = 1; i <= runs; i++)); do
    "$out/$name" > "$out/$name-$i.log" 2>&1
    grep '^RESULT ' "$out/$name-$i.log" | tail -1 >> "$results" || echo "RESULT $name failed=1" >> "$results"
  done
done

python3 "$here/report.py" "$results" "$runs" "$out"
