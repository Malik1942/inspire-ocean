# Oryne's capture sound

`Oryne/Resources/OceanReceived.caf` plays when a thought is saved (`Oryne/Services/CaptureFeedback.swift`),
together with the swell haptic. It is rendered by `render_capture.py`, never edited by hand.

- **Chosen 2026-10-19, by ear, after many listening rounds:** a landed note on E4 over a quiet bed of a real
  wave. 450 ms, peak −15.7 dBFS, phone-speaker level −31 dB (300 Hz to 6 kHz).
  - **The note says "captured":** Locant's Tock instrument (`Locant/design/sound/render.swift`). It is a
    harmonic series whose upper harmonics die at once, with two voices 1.5 cents apart, a small settling
    glide and a 6 ms rise. It never strikes.
  - **The wave says "into the sea":** an even bed, 17 dB under the note, cut from a real recording. Its fizz
    of draining water is pulled down so the roll of the wave carries it.
- **Source:** "Waves On The Beach (Sand Wash)" by ralph.whitehead, Freesound
  [470648](https://freesound.org/people/ralph.whitehead/sounds/470648/), CC0, recorded with two Sennheiser
  MKH 416 at Gylly Beach, UK. Cut at 7:39.9. The 214 MB WAV is not in the repo; download it to re-render.
- **What the rounds taught, worth keeping:**
  - Synthesized water and synthesized waves read as fake or as wind, every time. Only a recording sounded real.
  - A wave alone is ambient: it has no moment, so it cannot say "captured". The note is what marks the moment.
  - High tones hurt (anything starting around 1.5 kHz). A struck bar reads as sharp, because a strike begins
    with a contact (Locant learned the same). Two rising notes read as a Windows chime.
  - Bass is lost on a phone speaker and overplayed on AirPods, so level by the phone band and cut the rumble.
  - The sea belongs under the note: quiet, even, and only as long as the note.

```bash
# from the repo root, with the source WAV downloaded
python3 design/sound/render_capture.py ~/Downloads/470648__ralphwhitehead__waves-on-the-beach-sand-wash.wav
```

It needs numpy, scipy, ffmpeg and afconvert. Every parameter is a constant at the top of the script.
