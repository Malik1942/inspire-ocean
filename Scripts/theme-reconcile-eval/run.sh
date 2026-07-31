#!/usr/bin/env bash
# Co-location eval for the interpret/grouping system (the "burger bug").
# Compiles and runs eval.swift, which calls the real Anthropic Messages API
# twice over eval-set.json — the shipping prompt (OLD) vs Fix C (NEW) — and
# prints red -> green co-location scores. See README.md.
#
# Key, in order of preference:
#   1. a keyfile at ~/.config/oryne/anthropic.key (one line, just the key) —
#      set it up once with:  mkdir -p ~/.config/oryne && pbpaste > ~/.config/oryne/anthropic.key
#      (copy the key from console.anthropic.com first; file lives outside any repo)
#   2. the ANTHROPIC_API_KEY environment variable
#
# Optional env: OCEAN_CLOUD_MODEL (default claude-opus-4-8), OCEAN_CLOUD_BASE_URL
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

keyfile="$HOME/.config/oryne/anthropic.key"
if [[ -z "${ANTHROPIC_API_KEY:-}" && -f "$keyfile" ]]; then
  # tr strips the stray newline/whitespace that a paste or `echo >` leaves in —
  # the exact thing that makes the API reject an otherwise-valid key.
  ANTHROPIC_API_KEY="$(tr -d '[:space:]' < "$keyfile")"
  export ANTHROPIC_API_KEY
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "No API key found. Either drop it in a keyfile (once):" >&2
  echo "  mkdir -p ~/.config/oryne && pbpaste > ~/.config/oryne/anthropic.key" >&2
  echo "(with the key on your clipboard from console.anthropic.com), or:" >&2
  echo "  export ANTHROPIC_API_KEY=<your key>" >&2
  exit 2
fi

bin="$(mktemp -d)/eval"
swiftc -O "$here/eval.swift" -o "$bin"
exec "$bin"
