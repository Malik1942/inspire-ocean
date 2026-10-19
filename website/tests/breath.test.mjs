import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BREATH_BASE, breathAt, envelope, wave, wavesBetween } from '../assets/js/breath.js';

test('waves last 8.5 to 11 seconds and peak between 0.75 and 1', () => {
  for (let i = 0; i < 500; i++) {
    const w = wave(i);
    assert.ok(w.duration >= 8.5 && w.duration <= 11, `duration ${w.duration}`);
    assert.ok(w.peak >= 0.75 && w.peak <= 1, `peak ${w.peak}`);
    assert.ok(w.rise > 0 && w.rise < w.duration);
    assert.ok(Math.abs(w.pan) <= 0.3);
  }
});

test('waves follow each other without gaps', () => {
  for (let i = 0; i < 200; i++) {
    const a = wave(i);
    const b = wave(i + 1);
    assert.ok(Math.abs(a.start + a.duration - b.start) < 1e-9);
  }
});

test('the breath is deterministic', () => {
  const first = breathAt(123.456);
  breathAt(9999);
  assert.deepEqual(breathAt(123.456), first);
});

test('the level stays between the base and 1', () => {
  for (let t = 0; t < 900; t += 0.37) {
    const { level } = breathAt(t);
    assert.ok(level >= BREATH_BASE - 1e-9 && level <= 1 + 1e-9, `level ${level} at ${t}`);
  }
});

test('the level is continuous, including across wave boundaries', () => {
  for (let t = 0; t < 600; t += 0.05) {
    const jump = Math.abs(breathAt(t + 0.01).level - breathAt(t).level);
    assert.ok(jump < 0.02, `jump ${jump} at ${t}`);
  }
  for (let i = 1; i < 50; i++) {
    const s = wave(i).start;
    assert.ok(Math.abs(breathAt(s - 1e-6).level - breathAt(s + 1e-6).level) < 1e-3);
  }
});

test('each wave reaches its peak at the crest', () => {
  const w = wave(7);
  assert.ok(Math.abs(envelope(w, w.rise / w.duration) - w.peak) < 1e-9);
});

test('wavesBetween lists the waves that begin inside the window, in order', () => {
  const list = wavesBetween(10, 70);
  assert.ok(list.length >= 5 && list.length <= 8, `${list.length} waves`);
  for (const w of list) assert.ok(w.start >= 10 && w.start < 70);
  for (let i = 1; i < list.length; i++) assert.ok(list[i].start > list[i - 1].start);
});

test('negative time is treated as the first moment', () => {
  assert.deepEqual(breathAt(-5), breathAt(0));
});
