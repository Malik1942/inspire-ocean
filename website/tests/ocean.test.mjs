import { test } from 'node:test';
import assert from 'node:assert/strict';
import { breathing, springStep, wanderOffset } from '../assets/js/ocean.js';
import { PALETTES, mixPalette } from '../assets/js/lamps.js';

test('the spring arrives without overshooting', () => {
  let x = 0;
  let v = 0;
  let peak = 0;
  for (let i = 0; i < 600; i++) {
    [x, v] = springStep(x, v, 100, 1 / 60);
    peak = Math.max(peak, x);
  }
  assert.ok(peak <= 100 + 1e-9, `overshoot to ${peak}`);
  assert.ok(Math.abs(x - 100) < 0.05, `ended at ${x}`);
});

test('the spring stays calm through long frames', () => {
  let x = 0;
  let v = 0;
  for (let i = 0; i < 100; i++) [x, v] = springStep(x, v, 100, 0.05);
  assert.ok(x > 99 && x <= 100 + 1e-9, `ended at ${x}`);
});

test('wander stays within its amplitude and is deterministic', () => {
  for (let t = 0; t < 120; t += 0.7) {
    const [x, y] = wanderOffset(0.37, t, 4);
    assert.ok(Math.abs(x) <= 4 && Math.abs(y) <= 4);
    assert.deepEqual(wanderOffset(0.37, t, 4), [x, y]);
  }
});

test('wander is smooth from frame to frame', () => {
  for (let t = 0; t < 60; t += 0.1) {
    const [a] = wanderOffset(0.8, t, 4);
    const [b] = wanderOffset(0.8, t + 1 / 60, 4);
    assert.ok(Math.abs(a - b) < 0.1);
  }
});

test('breathing stays within its depth', () => {
  for (let t = 0; t < 60; t += 0.3) {
    const s = breathing(0.42, t, 0.02);
    assert.ok(s >= 0.98 - 1e-9 && s <= 1.02 + 1e-9);
  }
});

test('warmth leans any lamp toward dusk, and only that far', () => {
  assert.deepEqual(mixPalette(PALETTES.moon, PALETTES.dusk, 0), PALETTES.moon);
  assert.deepEqual(mixPalette(PALETTES.moon, PALETTES.dusk, 1), PALETTES.dusk);
  assert.deepEqual(mixPalette(PALETTES.moon, PALETTES.dusk, 7), PALETTES.dusk);
  const half = mixPalette(PALETTES.moon, PALETTES.dusk, 0.5);
  half.core.forEach((c, i) => {
    const [a, b] = [PALETTES.moon.core[i], PALETTES.dusk.core[i]];
    assert.ok(c >= Math.min(a, b) && c <= Math.max(a, b));
  });
});
