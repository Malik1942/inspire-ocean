#!/usr/bin/env bash
# Re-derive the Ask dialogue relevance floor (EmbeddingService.dialogueRetrievalFloor).
# Extracts the searchable text of every non-archived node from an Oryne store,
# then scores the documented corridor anchors with the same NLEmbedding math the
# app uses. Run this whenever Apple revises NLEmbedding, to confirm the floor
# still sits between the noise ceiling and the paraphrase target.
#
# Usage:
#   ./run.sh [path-to-InspireOcean.store]
# With no argument it locates the store of the currently booted simulator.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

store="${1:-}"
if [[ -z "$store" ]]; then
  booted="$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime in data.get("devices", {}).values():
    for device in runtime:
        if device.get("state") == "Booted":
            print(device["udid"]); raise SystemExit
' || true)"
  if [[ -z "$booted" ]]; then
    echo "No booted simulator found. Pass a store path explicitly:" >&2
    echo "  ./run.sh /path/to/InspireOcean.store" >&2
    exit 1
  fi
  store="$(find "$HOME/Library/Developer/CoreSimulator/Devices/$booted/data/Containers/Shared/AppGroup" \
    -name "InspireOcean.store" 2>/dev/null | head -1)"
fi

if [[ -z "$store" || ! -f "$store" ]]; then
  echo "Store not found: ${store:-<empty>}" >&2
  exit 1
fi

echo "Store: $store"
nodes="$(mktemp -t floor-sweep-nodes).json"
trap 'rm -f "$nodes"' EXIT
python3 "$here/extract.py" "$store" > "$nodes"
swift "$here/sweep.swift" "$nodes"
