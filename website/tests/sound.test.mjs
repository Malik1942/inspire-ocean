import { test } from 'node:test';
import assert from 'node:assert/strict';
import { swellCurve } from '../assets/js/sound.js';
import { BREATH_BASE, envelope, wave } from '../assets/js/breath.js';

test('a whole wave swells from quiet to its crest and back', () => {
  const w = wave(3);
  const { begin, end, gains, cutoffs } = swellCurve(w, w.start, 0);
  assert.equal(begin, w.start);
  assert.ok(Math.abs(end - (w.start + w.duration)) < 1e-9);
  assert.equal(gains.length, 48);
  assert.ok(Math.abs(gains[0] - 0.03) < 1e-6);
  assert.ok(Math.abs(gains[47] - 0.03) < 1e-6);
  for (const g of gains) assert.ok(g >= 0.03 - 1e-6 && g <= 0.5 + 1e-6, `gain ${g}`);
  for (const c of cutoffs) assert.ok(c >= 380 - 1e-3 && c <= 1600 + 1e-3, `cutoff ${c}`);
});

test('the loudest moment is the crest the visuals show', () => {
  const w = wave(11);
  const { gains } = swellCurve(w, w.start, 0);
  const loudest = gains.indexOf(Math.max(...gains));
  const crest = Math.round((w.rise / w.duration) * 47);
  assert.ok(Math.abs(loudest - crest) <= 1, `${loudest} vs ${crest}`);
});

test('joining mid-wave picks up where the breath is', () => {
  const w = wave(5);
  const from = w.start + w.duration * 0.3;
  const { begin, gains } = swellCurve(w, from, 0);
  assert.equal(begin, from);
  const lift = (envelope(w, 0.3) - BREATH_BASE) / (1 - BREATH_BASE);
  assert.ok(Math.abs(gains[0] - (0.03 + 0.47 * lift)) < 1e-6);
});

test('deeper water sounds more muffled', () => {
  const w = wave(2);
  const shallow = swellCurve(w, w.start, 0).cutoffs;
  const deep = swellCurve(w, w.start, 1).cutoffs;
  for (let i = 0; i < shallow.length; i++) assert.ok(deep[i] < shallow[i]);
});
