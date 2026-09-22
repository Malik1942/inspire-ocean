import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createNoise2D } from '../assets/js/noise.js';

test('the same seed gives the same water', () => {
  const a = createNoise2D(7);
  const b = createNoise2D(7);
  for (let i = 0; i < 200; i++) assert.equal(a(i * 0.37, i * 0.11), b(i * 0.37, i * 0.11));
});

test('different seeds give different water', () => {
  const a = createNoise2D(7);
  const b = createNoise2D(8);
  let same = 0;
  for (let i = 0; i < 200; i++) if (a(i * 0.37, 1.5) === b(i * 0.37, 1.5)) same++;
  assert.ok(same < 20, `${same} identical samples`);
});

test('values stay within -1..1 and actually vary', () => {
  const n = createNoise2D();
  let sum = 0;
  let squares = 0;
  let count = 0;
  for (let x = -20; x < 20; x += 0.173) {
    for (let y = -3; y < 3; y += 0.61) {
      const v = n(x, y);
      assert.ok(v >= -1 && v <= 1, `out of range: ${v}`);
      sum += v;
      squares += v * v;
      count++;
    }
  }
  const sd = Math.sqrt(squares / count - (sum / count) ** 2);
  assert.ok(sd > 0.1, `too flat: sd ${sd}`);
});

test('the field is smooth', () => {
  const n = createNoise2D();
  for (let x = 0; x < 30; x += 0.05) {
    assert.ok(Math.abs(n(x + 0.001, 2.2) - n(x, 2.2)) < 0.02);
  }
});
