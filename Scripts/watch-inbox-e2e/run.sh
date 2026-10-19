#!/usr/bin/env bash
# End-to-end check of the phone's wrist-take import on a simulator. Drops a
# synthetic take (spoken by `say`, back-dated by an hour) into the App Group
# WatchInbox folder the way WatchConnectivity or the iCloud inbox would, and
# launches Oryne. Four checks:
#   1. exactly one voice thought with the take's ID lands in the store;
#   2. the watch's createdAt carried over onto the thought;
#   3. the same take dropped again is refused, not imported twice;
#   4. a thought the user deleted stays deleted when the take arrives again.
#
# Usage: Scripts/watch-inbox-e2e/run.sh <iphone-sim-udid> [path/to/Oryne.app]
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
UDID=${1:?iPhone simulator UDID}
APP=${2:-build/DerivedData/Build/Products/Debug-iphonesimulator/Oryne.app}
BUNDLE=com.inspireocean.app
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
GROUP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" groups | awk '/group.com.inspireocean.shared/ {print $2}')
[ -n "$GROUP" ] || { echo "FAIL: no App Group container for $BUNDLE"; exit 1; }
INBOX="$GROUP/WatchInbox"
STORE="$GROUP/InspireOcean.store"
mkdir -p "$INBOX"

say -o "$WORK/take.aiff" "A lighthouse cafe with a reading room upstairs"
afconvert -f m4af -d aac -c 1 "$WORK/take.aiff" "$WORK/take.m4a"
ID=$(uuidgen)
HEX=$(echo "$ID" | tr -d '-' | tr 'a-f' 'A-F')
# WatchTake's JSON: Date encodes as seconds since 2001-01-01.
CREATED=$(python3 -I -c 'import time; print(time.time() - 978307200 - 3600)')

drop_take() {
  cp "$WORK/take.m4a" "$INBOX/$ID.m4a"
  printf '{"id":"%s","createdAt":%s,"duration":3.0,"version":1}' "$ID" "$CREATED" > "$INBOX/$ID.json"
}

launch_and_wait_for_import() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  for _ in $(seq 1 30); do
    [ ! -e "$INBOX/$ID.json" ] && break
    sleep 1
  done
  [ ! -e "$INBOX/$ID.json" ] || { echo "FAIL: take still waiting in the inbox after 30 s"; exit 1; }
  sleep 2   # let the save settle before reading the store
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
}

count_nodes() {
  sqlite3 "$STORE" "SELECT count(*) FROM ZNODE WHERE hex(ZID)='$HEX' AND ZKINDRAW='voice';"
}

drop_take
launch_and_wait_for_import
COUNT=$(count_nodes)
[ "$COUNT" = 1 ] || { echo "FAIL: expected 1 voice thought for $ID, found $COUNT"; exit 1; }
echo "PASS: imported $ID as one voice thought"
echo "  title/transcript (empty until speech recognition is allowed):"
sqlite3 "$STORE" "SELECT '  ' || ZTITLE || ' | ' || substr(ifnull(ZTRANSCRIPTION,''),1,60) FROM ZNODE WHERE hex(ZID)='$HEX';"
ok=$(sqlite3 "$STORE" "SELECT abs(ZCREATEDAT - $CREATED) < 1 FROM ZNODE WHERE hex(ZID)='$HEX';")
[ "$ok" = 1 ] || { echo "FAIL: createdAt did not carry over"; exit 1; }
echo "PASS: the watch's createdAt carried over"

drop_take
launch_and_wait_for_import
COUNT=$(count_nodes)
[ "$COUNT" = 1 ] || { echo "FAIL: second copy imported again ($COUNT thoughts)"; exit 1; }
echo "PASS: a second copy of $ID was refused"

# The user deletes the thought (the app is terminated now); the take arrives
# once more. The ledger remembers it, so the thought must not come back.
sqlite3 "$STORE" "DELETE FROM ZNODE WHERE hex(ZID)='$HEX';"
drop_take
launch_and_wait_for_import
COUNT=$(count_nodes)
[ "$COUNT" = 0 ] || { echo "FAIL: a deleted thought came back"; exit 1; }
echo "PASS: a deleted thought stayed deleted"
