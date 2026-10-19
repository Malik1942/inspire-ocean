// Lamps: the few large lights in the Ocean, drawn like a sunset lamp's
// projection on a wall: a flat disc of light, warmest and brightest in its
// middle, a soft edge, and a halo glowing around that edge. Only large
// circles; the page never scatters small dots. Depth melts a lamp's edge into
// its halo instead of shrinking it.

const TAU = Math.PI * 2;

/** Palettes as core, edge, and halo colors. Warm dusk is the resurfacing light. */
export const PALETTES = {
  moon: { core: [236, 241, 252], edge: [160, 180, 226], halo: [140, 162, 214] },
  dusk: { core: [255, 222, 176], edge: [246, 144, 104], halo: [240, 128, 100] },
  lilac: { core: [236, 230, 252], edge: [170, 156, 222], halo: [150, 134, 210] },
  amber: { core: [255, 236, 200], edge: [230, 170, 104], halo: [226, 160, 96] },
};

const lerp = (a, b, t) => a + (b - a) * t;
const unit = (v) => Math.max(0, Math.min(1, v));

/** A palette `t` of the way toward another (t in 0..1). */
export function mixPalette(a, b, t) {
  const k = unit(t);
  const channel = (x, y) => x.map((v, i) => Math.round(lerp(v, y[i], k)));
  return { core: channel(a.core, b.core), edge: channel(a.edge, b.edge), halo: channel(a.halo, b.halo) };
}

const rgba = ([r, g, b], a) => `rgba(${r},${g},${b},${unit(a).toFixed(3)})`;

// A gaussian falloff, sampled: offset along the radius, then strength.
const GAUSS = [[0, 1], [0.18, 0.85], [0.36, 0.53], [0.55, 0.24], [0.73, 0.077], [0.91, 0.018], [1, 0]];

/**
 * Draws one lamp on a 2D context. `soft` 0 is in focus: a disc of flat light
 * with a soft edge and a halo glowing around that edge. `soft` 1 is far out of
 * focus: only a pool of light, brightest in the middle, with no edge and no
 * ring. In between, one melts into the other. `warmth` leans any palette toward
 * dusk. Draw with `globalCompositeOperation = 'lighter'` so lights add up.
 */
export function drawLamp(ctx, { x, y, r, alpha, soft = 0, palette = 'moon', warmth = 0, scale = 1 }) {
  if (alpha <= 0.004 || r <= 0) return;
  const p = mixPalette(PALETTES[palette] ?? PALETTES.moon, PALETTES.dusk, warmth);
  const R = r * scale;
  const s = unit(soft);
  const tint = (a, b, t) => a.map((v, i) => Math.round(lerp(v, b[i], t)));

  if (s > 0.01) {
    const reach = R * 2.4;
    const pool = ctx.createRadialGradient(x, y, 0, x, y, reach);
    const center = tint(p.core, p.edge, 0.6);
    for (const [offset, strength] of GAUSS) {
      pool.addColorStop(offset, rgba(tint(center, p.halo, offset), 0.4 * alpha * s * strength));
    }
    ctx.fillStyle = pool;
    ctx.beginPath();
    ctx.arc(x, y, reach, 0, TAU);
    ctx.fill();
  }

  const focus = 1 - s;
  if (focus <= 0.01) return;

  // The halo: a band of light hugging the edge and spilling outward.
  const haloR = R * 2.1;
  const at = (d) => unit(d / haloR);
  const halo = ctx.createRadialGradient(x, y, 0, x, y, haloR);
  halo.addColorStop(0, rgba(p.halo, 0));
  halo.addColorStop(at(R * 0.7), rgba(p.halo, 0));
  halo.addColorStop(at(R), rgba(p.halo, 0.3 * alpha * focus));
  halo.addColorStop(at(R * 1.25), rgba(p.halo, 0.11 * alpha * focus));
  halo.addColorStop(at(R * 1.6), rgba(p.halo, 0.03 * alpha * focus));
  halo.addColorStop(1, rgba(p.halo, 0));
  ctx.fillStyle = halo;
  ctx.beginPath();
  ctx.arc(x, y, haloR, 0, TAU);
  ctx.fill();

  // The disc: flat light, warm in the middle and deepening in color toward a soft edge.
  const blur = R * (0.06 + 0.3 * s);
  const outer = R + blur;
  const rim = (R - blur) / outer;
  const disc = ctx.createRadialGradient(x, y, 0, x, y, outer);
  disc.addColorStop(0, rgba(p.core, 0.6 * alpha * focus));
  disc.addColorStop(rim * 0.55, rgba(tint(p.core, p.edge, 0.55), 0.48 * alpha * focus));
  disc.addColorStop(rim, rgba(p.edge, 0.44 * alpha * focus));
  disc.addColorStop(1, rgba(p.edge, 0));
  ctx.fillStyle = disc;
  ctx.beginPath();
  ctx.arc(x, y, outer, 0, TAU);
  ctx.fill();
}
