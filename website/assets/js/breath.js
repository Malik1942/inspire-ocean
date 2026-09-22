// One breathing clock for the whole site. The ring, the wave lines, and the
// ambient sound rise and fall on the same waves, so what you see and what you
// hear always agree. Deterministic: a wave's length, height, and pan come from
// its index, so any moment can be asked about at any time.

export const BREATH_BASE = 0.08;   // the water never goes completely flat

const starts = [0];                // start time of wave i, grown on demand

function unit(index, salt) {
  let h = Math.imul(index + 1, 0x27d4eb2d) ^ Math.imul(salt, 0x165667b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

function durationOf(index) {
  return 8.5 + 2.5 * unit(index, 1);
}

function startOf(index) {
  while (starts.length <= index) {
    const last = starts.length - 1;
    starts.push(starts[last] + durationOf(last));
  }
  return starts[index];
}

function indexAt(t) {
  const time = Math.max(0, t);
  while (starts[starts.length - 1] <= time) startOf(starts.length);
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= time) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/** The shape of wave `index`, in seconds. */
export function wave(index) {
  const duration = durationOf(index);
  return {
    index,
    start: startOf(index),
    duration,
    rise: duration * (0.36 + 0.08 * unit(index, 2)),
    peak: 0.75 + 0.25 * unit(index, 3),
    pan: (unit(index, 4) - 0.5) * 0.6,
  };
}

/** Wave height at `phase` (0..1) through it: an easy rise, a long fall back. */
export function envelope(w, phase) {
  const r = w.rise / w.duration;
  const p = Math.min(1, Math.max(0, phase));
  const lift = p < r
    ? 0.5 - 0.5 * Math.cos(Math.PI * (p / r))
    : 0.5 + 0.5 * Math.cos(Math.PI * ((p - r) / (1 - r)));
  return BREATH_BASE + (w.peak - BREATH_BASE) * lift;
}

/** The breath at `t` seconds: level BREATH_BASE..1, the wave, and its phase. */
export function breathAt(t) {
  const index = indexAt(t);
  const w = wave(index);
  const phase = Math.min(1, Math.max(0, (t - w.start) / w.duration));
  return { level: envelope(w, phase), index, phase };
}

/** Waves that begin in [t0, t1), for scheduling sound ahead of the clock. */
export function wavesBetween(t0, t1) {
  const out = [];
  let i = indexAt(t0);
  if (startOf(i) < t0) i += 1;
  for (; startOf(i) < t1; i++) out.push(wave(i));
  return out;
}

/** Seconds since the page started: the one clock sight and sound share. */
export function now() {
  return performance.now() / 1000;
}
