# Oryne 2.0: App Store text

## What's New in This Version

Oryne 2.0. A calmer phone app, built around one gesture.

Hold to speak, let go, and it's caught. A capture bar sits at the bottom of Tide and the Library: tap it to type, or hold its button and talk. Slide up to keep listening without holding on. Your thought is saved the moment you let go, with a quiet sound, a gentle haptic, and ten seconds to undo.

New: Oryne on Apple Watch. Press the Action Button on Apple Watch Ultra, tap the complication, or say "Whisper to Oryne", and speak. Your whisper reaches your iPhone on its own and drifts into the Ocean with a title, in the current it belongs to.

• Tide is the new home: the thought that came back today, what just drifted in, and your currents. Nearby shows what sits close to it. Let it rest sends it back under.
• Ask is one question and one grounded answer, and every answer lists the thoughts it was drawn from. Summarize reads a whole current, a search, or a thought's neighbors in one tap.
• The Library keeps search, Recent and Related, and every filter in one menu.
• A thought's page puts your words first, then its themes and what drifts nearby.
• New York titles, Liquid Glass controls, and a still background that is easy on the battery.
• Titles now stay in your thought's own language.

## Promotional Text (170 characters at most; can change without a new version)

Hold to speak, let go, and it's caught. Now on Apple Watch too: catch a whisper from your wrist, and it lands in your Ocean on its own.

## Screenshots (6.9-inch, 1320x2868, in this order)

01-tide.png: Catch ideas before / they drift away.
02-capture.png: Tap to type. / Hold to speak.
03-fast-capture.png: One press. / Already listening.
04-current.png: Your ideas / organize themselves.
05-ask.png: Ask your ideas / anything.
06-library.png: Everything, in order, / when you want it.
07-detail.png: Grow an idea without / losing the original.
08-watch.png: Catch a whisper / from your wrist.

## Apple Watch screenshots (422x514, Ultra 3)

App Store Connect takes one watch size across all localizations. English files are in `watch/en/`, Simplified Chinese in `watch/zh-Hans/`, with the same names.

01-recording.png: Listening, the waveform, and the timer.
02-caught.png: Caught, with Undo.
03-in-your-ocean.png: In your Ocean, with the last thought's title.
04-waiting.png: 2 waiting for iPhone, with the last thought's title.

The phone shots are made by `design/appstore/make_screenshots.py` from the website's captures (recipe in `website/README.md`). 08-watch is made by the same script from `watch/en/03-in-your-ocean.png`. The watch captures are native Ultra 3 simulator screenshots from the DEBUG demo seams, taken with the system clock at a real 9:41 by `Scripts/watch-screens/appstore-941.py`; the Chinese set names the last thought 灯塔咖啡馆. The two 01-recording shots keep the livelier waveform of an earlier capture (the recorder hears the Mac's microphone), with the clock area, which holds nothing else, taken from the 9:41 run.
