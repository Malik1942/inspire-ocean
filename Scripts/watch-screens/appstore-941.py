#!/usr/bin/env python3
"""Captures the eight App Store watch screenshots with the clock at a real 9:41.

The watch simulator shows the Mac's time and `simctl status_bar` can't
override it on watchOS. Carousel draws that clock, so this sets TZ in the
simulator's launchd to a fixed offset that makes the next whole minute read
9:41, restarts Carousel, and takes every shot inside that minute through the
DEBUG demo seams (WatchCaptureModel.applyDemoEnvironment). Shots that miss the
minute are retaken in another round. TZ is restored at the end.

The recording screen records the Mac's real microphone, so its waveform
follows the room: a quiet room gives flat dots.

Usage: Scripts/watch-screens/appstore-941.py <watch-sim-udid> <out-dir>
Writes <out-dir>/<lang>/<name>.png as RGB (App Store Connect rejects alpha).
The Oryne watch app must already be installed with the microphone granted
(Scripts/watch-screens/run.sh does both).
"""
import datetime as dt
import os
import subprocess
import sys
import time

from PIL import Image

UDID, OUT = sys.argv[1], sys.argv[2]
BUNDLE = "com.inspireocean.app.watchkitapp"
ZH_TITLE = "灯塔咖啡馆"

SHOTS = [  # (language, name, demo environment, seconds before the screenshot)
    ("en", "01-recording", {"ORYNE_WATCH_STAGE": "recording"}, 4.5),
    ("en", "02-caught", {"ORYNE_WATCH_STAGE": "caught"}, 2.5),
    ("en", "03-in-your-ocean", {"ORYNE_WATCH_DEMO": "inOcean"}, 3.0),
    ("en", "04-waiting", {"ORYNE_WATCH_DEMO": "waiting"}, 3.0),
    ("zh-Hans", "01-recording", {"ORYNE_WATCH_STAGE": "recording"}, 4.5),
    ("zh-Hans", "02-caught", {"ORYNE_WATCH_STAGE": "caught"}, 2.5),
    ("zh-Hans", "03-in-your-ocean", {"ORYNE_WATCH_DEMO": "inOcean", "ORYNE_WATCH_DEMO_TITLE": ZH_TITLE}, 3.0),
    ("zh-Hans", "04-waiting", {"ORYNE_WATCH_DEMO": "waiting", "ORYNE_WATCH_DEMO_TITLE": ZH_TITLE}, 3.0),
]


def simctl(*args, env=None):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, env=env)


def utcnow():
    return dt.datetime.now(dt.timezone.utc)


def arm():
    """Sets the clock so the next whole UTC minute at least 15 s away reads 9:41."""
    now = utcnow()
    start = (now + dt.timedelta(seconds=75)).replace(second=0, microsecond=0)
    minutes = (9 * 60 + 41) - (start.hour * 60 + start.minute)
    minutes = (minutes + 12 * 60) % (24 * 60) - 12 * 60  # into -12h..+12h
    sign = "+" if minutes >= 0 else "-"
    tz = f"GMT{sign}{abs(minutes) // 60:02d}:{abs(minutes) % 60:02d}"
    simctl("spawn", UDID, "launchctl", "setenv", "TZ", tz)
    simctl("spawn", UDID, "launchctl", "kickstart", "-k", "system/com.apple.Carousel")
    print(f"TZ={tz}: 9:41 from {start:%H:%M:%S}Z", flush=True)
    return start


os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
pending = list(SHOTS)
try:
    for attempt in range(1, 4):
        if not pending:
            break
        start = arm()
        while utcnow() < start + dt.timedelta(seconds=0.3):
            time.sleep(0.1)
        missed = []
        for lang, name, demo, wait in pending:
            env = dict(os.environ, **{f"SIMCTL_CHILD_{key}": value for key, value in demo.items()})
            simctl("launch", "--terminate-running-process", UDID, BUNDLE, "-AppleLanguages", f"({lang})", env=env)
            time.sleep(wait)
            os.makedirs(f"{OUT}/{lang}", exist_ok=True)
            path = f"{OUT}/{lang}/{name}.png"
            taken = utcnow()
            simctl("io", UDID, "screenshot", path)
            inside = start <= taken and utcnow() < start + dt.timedelta(seconds=60)
            if inside:
                Image.open(path).convert("RGB").save(path)
            else:
                missed.append((lang, name, demo, wait))
            print(f"{lang}/{name}: {'9:41' if inside else 'missed the minute, retaking'}", flush=True)
        pending = missed
finally:
    simctl("spawn", UDID, "launchctl", "unsetenv", "TZ")
    simctl("spawn", UDID, "launchctl", "kickstart", "-k", "system/com.apple.Carousel")
if pending:
    sys.exit("not captured: " + ", ".join(f"{lang}/{name}" for lang, name, _, _ in pending))
