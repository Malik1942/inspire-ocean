// Seeded 2D simplex noise, after Stefan Gustavson's public-domain reference.
// The Ocean samples one shared field, so every mote moves as part of one body
// of water instead of jittering on its own (the app's DriftField, in small).

const F2 = 0.5 * (Math.sqrt(3) - 1);
const G2 = (3 - Math.sqrt(3)) / 6;
const GRADIENTS = [
  [1, 1], [-1, 1], [1, -1], [-1, -1],
  [1, 0], [-1, 0], [0, 1], [0, -1],
];

function permutation(seed) {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  let s = seed >>> 0 || 1;
  for (let i = 255; i > 0; i--) {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    const j = s % (i + 1);
    const swap = p[i];
    p[i] = p[j];
    p[j] = swap;
  }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  return perm;
}

function corner(gradient, x, y) {
  let t = 0.5 - x * x - y * y;
  if (t < 0) return 0;
  const g = GRADIENTS[gradient & 7];
  t *= t;
  return t * t * (g[0] * x + g[1] * y);
}

/** A smooth field in -1..1. The same seed always gives the same water. */
export function createNoise2D(seed = 0x0cea) {
  const perm = permutation(seed);
  return function noise2D(xin, yin) {
    const s = (xin + yin) * F2;
    const i = Math.floor(xin + s);
    const j = Math.floor(yin + s);
    const t = (i + j) * G2;
    const x0 = xin - (i - t);
    const y0 = yin - (j - t);
    const i1 = x0 > y0 ? 1 : 0;
    const j1 = x0 > y0 ? 0 : 1;
    const x1 = x0 - i1 + G2;
    const y1 = y0 - j1 + G2;
    const x2 = x0 - 1 + 2 * G2;
    const y2 = y0 - 1 + 2 * G2;
    const ii = i & 255;
    const jj = j & 255;
    const n = corner(perm[ii + perm[jj]], x0, y0)
      + corner(perm[ii + i1 + perm[jj + j1]], x1, y1)
      + corner(perm[ii + 1 + perm[jj + 1]], x2, y2);
    return Math.max(-1, Math.min(1, 70 * n));
  };
}
