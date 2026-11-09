# Oryne 2.2: App Store text

Draft for review. Sources: PRs #35 to #38, `design/identity-2.1.md`, and the whisper transcription fix (`651f0bf`). The app has only an English (U.S.) localization, so there is no Chinese What's New. App Store Connect rejects ✕ and other dingbats in this field; bullets are fine.

## What's New in This Version

Oryne 2.2. A new look, built around the thought that comes back.

• A new Tide. The thought that came back today stands in its own picture at the top of the screen, with what just drifted in below it.
• One warm light. Tide, Ask, the Library and every thought you open now share it.
• Your words, in a serif. What you wrote or said is set apart from what Oryne wrote for you.
• A new ring on the capture disc. Blue at rest, warm and blue while it listens.
• Easier to read. Type and spacing were reworked on every page, the widgets and Apple Watch, and the largest accessibility sizes no longer clip.
• Long whispers keep every paragraph. Transcribing a recording again, or switching its language, no longer leaves only the last sentence.

## Promotional Text (170 characters at most; can change without a new version)

A new look for Oryne. The thought that comes back today now stands in its own picture on Tide, in one warm light across every page.

## Description

Carry over the 2.1 Description unchanged, except this paragraph:

Start the day on Tide. The thought that came back today stands in its own picture at the top, with what just drifted in and your currents below it. Nearby shows what sits close to it. Let it rest sends it back under.

## Screenshots

- `01` to `08`: iPhone 6.9 inch, 1320x2868.
- `iphone-6.3/`: the same set at 1206x2622, which review also asks for.
- `ipad/`: iPad 13 inch, 2064x2752.
- `creative/universal-hero.png`: product page header and search results, 5244x2950.

Captured from main at `c788b01` (the iPad set with the whisper fix applied, which changes no screen) on throwaway simulators with `OCEAN_SCREENSHOT_SEED=1`. The simulator hears no speech, so `03-fast-capture` shows "Words will follow." where a real take shows the words.

## Changed from 2.1

- `02-capture` said "Hold to speak". The caption is now "Tap the disc to speak", since a tap starts a take.
- Every phone and iPad screen is new. The 2.0 screens predate the stage, the warm light and the ring.
- `08-watch` is recaptured for the type changes on the wrist.
