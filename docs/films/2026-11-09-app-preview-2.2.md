# Oryne 2.2: App Store app preview

**Date:** 2026-11-09 · **Status:** approved with the calm piano, delivered and submitted with 2.2. See the gap audit below.

```
FILM: Oryne 2.2 app preview, one cut for iPhone and one for iPad
SURFACE: iOS app, Debug build of main at 0423b2a, throwaway iPhone 17 Pro and iPad Pro 13-inch simulators,
  English, OCEAN_SCREENSHOT_SEED=1, status bar 9:41
PLACEMENT: App Store product page, where it autoplays muted, then with sound if the viewer taps
CANVAS: iPhone 886x1920, iPad 1200x1600, both 30 fps (Apple's maximum)
TARGET LENGTH: ~24s (Apple's window is 15 to 30s)
VIBE: calm, warm, unhurried, like reading by a lamp
  biggest moment: the Golden hour stage, which also holds through 5s, Apple's default poster frame
  avoid: launch-ad punchiness, fast montage, cross-dissolves, side-pushes, camera drift

OPENING: none, the first frame is the app
SCENES:
1. Tide: the thought that came back stands in its own picture
   start: Tide at launch, resurfacing "Golden hour on the walk home"
   interaction: none until 5.5s, the stage holds
   payoff: title, the user's words, Nearby and Let it rest, readable and still
   data: seed, relaunch until Tide picks Golden hour   ~6s
2. Catch in words: type a thought and let it go
   start: the same Tide
   interaction: tap the bar, type "The light on the ferry railings, gold for a minute and then gone", tap send
   payoff: the card closes and "Carried into the sea" appears, held 2s
   data: typed live   ~7s
3. Catch by voice: the ring listens
   start: the same Tide
   interaction: tap the disc, the ring turns warm and blue, tap Stop
   payoff: the ring moving, held 2s
   data: the simulator hears no speech, so the bar reads "Words will follow." where a real take shows words   ~4s
4. Currents: thoughts gather on their own
   start: the Library in Currents
   interaction: tap Light and Color
   payoff: the sheet with its four thoughts, held 2s
   data: seed   ~3s
5. Ask: one answer that shows where it came from
   start: the Light and Color sheet
   interaction: tap Summarize
   payoff: the on-device answer and its "Drawn from" list, held 3s
   data: seed, the answer is the model's own output, retaken if it reads poorly   ~4s
TITLE CARDS: none
END CARD: none. A preview is meant to be footage of the app, and the screenshots beside it carry the captions.
BRAND: dark, as the app looks. Full-bleed capture with no device frame, overriding the usual mobile path,
  because a preview shows the app itself. Soft touch dot on each tap so the viewer sees what was pressed.
SOUND: Apple requires a stereo AAC track at 256 kbps. Sampled piano at a calm pace, one texture throughout,
  with the app's real landed note on the send in scene 2. Salamander piano is CC BY 3.0, attribute if credited.
```

## Technical limits, from Apple's app preview specifications

- H.264, .mp4 or .mov, 10 to 12 Mbps, progressive, up to High Profile Level 4.0, under 500 MB.
- Stereo AAC at 256 kbps, 44.1 or 48 kHz, all tracks enabled.
- Up to three previews per device size and language. The 886x1920 file also serves the 6.5-inch and 6.3-inch slots.
- iPhone captures are 1206x2622, slightly narrower than 886x1920, so about 6 px is cropped from the height after scaling. Nothing sits that close to the edges except the status bar's clearance.

## Gap audit (delivered 2026-11-09)

Status: approved by Malik with the calm piano. Graded from frames of the delivered files.

| Scene | iPhone (27.9s) | iPad (28.3s) | Note |
|---|---|---|---|
| 1. Tide stage, held through 5s | MET | MET | Golden hour is on screen at 4.9s |
| 2. Type a thought and let it go | MET | MET | "Carried into the sea" held about 3s |
| 3. The ring listens | DEVIATES | DEVIATES | Shown, ended with the cancel control rather than Stop, so no empty whisper is saved |
| 4. Currents gather | DEVIATES | DEVIATES | Light and Color shows five thoughts, not four: the typed thought joined it by itself |
| 5. Ask, with sources | MET | MET | iPad's answer lands on the take's last frame, which is held about 4s |

Capture gap: the simulator hears no speech, so scene 3 reads "Words will follow." A real device take would show the words.
