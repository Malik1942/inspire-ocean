#!/usr/bin/env bash
# Screenshots every wrist screen on a watch simulator, in English and
# Chinese, through the DEBUG seams in WatchCaptureModel.applyDemoEnvironment.
# Read the PNGs: each screen must match spec §1 (flat disc, honest status
# line, no dashes in copy).
#
# Usage: Scripts/watch-screens/run.sh <watch-sim-udid> <out-dir> [path/to/OryneWatch.app]
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
UDID=${1:?watch simulator UDID}
OUT=${2:?output directory}
APP=${3:-build/DerivedData/Build/Products/Debug-watchsimulator/OryneWatch.app}
BUNDLE=com.inspireocean.app.watchkitapp
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE"

shot() {   # shot <name> <language> [SIMCTL_CHILD_KEY=value ...]
  local name=$1 lang=$2
  shift 2
  env "$@" xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -AppleLanguages "($lang)" >/dev/null
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/$name-$lang.png" >/dev/null
}

for lang in en zh-Hans; do
  shot idle-empty     "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=empty
  shot idle-waiting   "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=waiting
  shot idle-onItsWay  "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=onItsWay
  shot idle-inOcean   "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=inOcean
  shot recording      "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=recording
  shot caught         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=caught
  # The denied screen only holds while the microphone really is denied:
  # the model returns to idle on activation once access is back.
  xcrun simctl privacy "$UDID" revoke microphone "$BUNDLE"
  shot denied         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=denied
  xcrun simctl privacy "$UDID" grant microphone "$BUNDLE"
  shot failed         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=failed
  shot nothing        "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=nothing
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
# The recording shot leaves a real .m4a; launch recovery would queue it as a
# take, so start clean.
xcrun simctl uninstall "$UDID" "$BUNDLE"
xcrun simctl install "$UDID" "$APP"
echo "Screens written to $OUT"
