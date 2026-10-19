// Choreography: where each light wants to be at a given moment of the page.
// Pure functions of (chapter, progress, viewport, anchors): no DOM, no clock.
// The water holds only a few large lights, drawn like a sunset lamp's
// projection, and a few huge blurred glows behind them; it never scatters
// small dots. The renderer eases toward these targets, so scrolling either way
// plays the story either way. Motion is atmosphere: everything the water shows
// is also written on the page (PHILOSOPHY §4).

export const CHAPTERS = ['top', 'how', 'capture', 'fast', 'currents', 'resurface', 'ask', 'grow', 'ambient', 'deep'];

/** How lively the water is per chapter; wander and breathing scale with it. */
export const ENERGY = {
  top: 1, how: 0.9, capture: 0.9, fast: 0.95, currents: 0.8, resurface: 0.8,
  ask: 0.7, grow: 0.5, ambient: 0.6, deep: 0.25,
};

/** The smallest a visible light may be, in points. */
export const MIN_LAMP = 60;

const EDGE = 8;

export const mix = (a, b, t) => a + (b - a) * t;
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

export function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

const center = (rect) => ({ x: rect.x + rect.w / 2, y: rect.y + rect.h / 2 });

function inside(point, rect, pad) {
  return point.x > rect.x - pad && point.x < rect.x + rect.w + pad
    && point.y > rect.y - pad && point.y < rect.y + rect.h + pad;
}

/** The whole cast: four currents, always far out of focus, and the one warm thought that resurfaces. */
export function createLamps() {
  return [
    { id: 'c0', role: 'current', index: 0, palette: 'dusk', size: 150, seed: 0.13 },
    { id: 'c1', role: 'current', index: 1, palette: 'moon', size: 130, seed: 0.41 },
    { id: 'c2', role: 'current', index: 2, palette: 'amber', size: 118, seed: 0.67 },
    { id: 'c3', role: 'current', index: 3, palette: 'lilac', size: 140, seed: 0.89 },
    { id: 'warm', role: 'warm', index: 0, palette: 'dusk', size: 120, seed: 0.27 },
  ];
}

/** Lights scale with the screen, down to a floor that keeps them large on phones. */
function scaleFor(ctx) {
  return clamp(Math.min(ctx.vw, ctx.vh) / 900, 0.62, 1);
}

/** Resting low in the water and invisible: where a light waits between its moments. */
function hidden(l, ctx) {
  return { x: (0.15 + 0.7 * l.seed) * ctx.vw, y: ctx.vh * 0.9, r: l.size * scaleFor(ctx), alpha: 0, soft: 1, warmth: 0 };
}

/** The currents drifting apart: pools of colored light toward the corners. */
const BOKEH = [[0.1, 0.28], [0.9, 0.2], [0.18, 0.84], [0.84, 0.74]];
function bokeh(l, ctx, alpha) {
  const [u, v] = BOKEH[l.index];
  return { ...hidden(l, ctx), x: u * ctx.vw, y: v * ctx.vh, alpha };
}

/** Where the currents gather: around the phone, in phone widths and heights from its center. */
const AROUND = [[-0.42, -0.2], [0.44, -0.3], [-0.4, 0.28], [0.43, 0.14]];

const LAYOUTS = {
  top: (l, ctx) => hidden(l, ctx),

  how: (l, ctx) => (l.role === 'current' ? bokeh(l, ctx, 0.24) : hidden(l, ctx)),

  capture: (l, ctx) => (l.role === 'current' ? bokeh(l, ctx, 0.16) : hidden(l, ctx)),

  // Fast Capture: the pools pull back and the water brightens, so the one press has the stage.
  fast: (l, ctx) => (l.role === 'current' ? bokeh(l, ctx, 0.1) : hidden(l, ctx)),

  // Related ideas drift together: the pools tuck in behind the phone and glow past its edges.
  currents(l, ctx) {
    if (l.role !== 'current') return hidden(l, ctx);
    const from = bokeh(l, ctx, 0.16);
    const phone = ctx.anchors['currents-phone'];
    if (!phone) return from;
    const gather = smoothstep(0.05, 0.45, ctx.progress);
    const c = center(phone);
    const [u, v] = AROUND[l.index];
    return {
      ...from,
      x: mix(from.x, c.x + u * phone.w, gather),
      y: mix(from.y, c.y + v * phone.h, gather),
      alpha: mix(0.16, 0.9, gather),
    };
  },

  // A forgotten thought comes back like the sun: out of the depth, into focus,
  // half of it clearing the widgets' top edge and the rest glowing behind them.
  resurface(l, ctx) {
    if (l.role === 'current') return bokeh(l, ctx, 0.12);
    const widget = ctx.anchors['resurface-widget'];
    if (!widget) return hidden(l, ctx);
    const rise = smoothstep(0.05, 0.5, ctx.progress);
    const r = l.size * scaleFor(ctx);
    return {
      ...hidden(l, ctx),
      x: widget.x + widget.w / 2,
      y: mix(ctx.vh + r, widget.y + 0.1 * r, rise),
      r: mix(1.2 * r, r, rise),
      alpha: mix(0.35, 1, rise),
      soft: 1 - rise,
      warmth: 1,
    };
  },

  ask: (l, ctx) => (l.role === 'current' ? bokeh(l, ctx, 0.1) : hidden(l, ctx)),

  grow: (l, ctx) => (l.role === 'current' ? bokeh(l, ctx, 0.08) : hidden(l, ctx)),

  ambient: (l, ctx) => hidden(l, ctx),

  deep: (l, ctx) => hidden(l, ctx),
};

function blendTargets(a, b, t) {
  return {
    x: mix(a.x, b.x, t), y: mix(a.y, b.y, t), r: mix(a.r, b.r, t),
    alpha: mix(a.alpha, b.alpha, t), soft: mix(a.soft, b.soft, t), warmth: mix(a.warmth, b.warmth, t),
  };
}

function finish(t, ctx) {
  t.x = clamp(t.x, EDGE, ctx.vw - EDGE);
  t.y = clamp(t.y, EDGE, ctx.vh - EDGE);
  t.alpha = clamp(t.alpha, 0, 1);
  t.soft = clamp(t.soft, 0, 1);
  t.warmth = clamp(t.warmth, 0, 1);
  // Text wins: over a block of copy a light only whispers.
  for (const rect of ctx.calm) {
    if (inside(t, rect, 10)) t.alpha *= 0.25;
  }
  return t;
}

/** Targets for every light. Near a chapter's end, `next` and `blend` hand over to the next one. */
export function layout(state, lamps, view) {
  const ctx = { vw: view.vw, vh: view.vh, anchors: view.anchors ?? {}, calm: view.calm ?? [] };
  const first = LAYOUTS[state.chapter] ?? LAYOUTS.ambient;
  const second = state.next ? (LAYOUTS[state.next] ?? LAYOUTS.ambient) : null;
  const blend = second ? clamp(state.blend ?? 0, 0, 1) : 0;
  const here = { ...ctx, progress: clamp(state.progress ?? 0, 0, 1) };
  const ahead = { ...ctx, progress: 0 };
  return lamps.map((l) => {
    const a = first(l, here);
    return finish(blend > 0 ? blendTargets(a, second(l, ahead), blend) : a, ctx);
  });
}

// ------------------------------------------------------------------ glows

/** Glow colors, as the halos of the lamp palettes. */
export const GLOW_COLORS = {
  moon: [140, 162, 210], dusk: [236, 142, 112], lilac: [146, 134, 200], amber: [222, 172, 112],
};

/** Per chapter: four glows as [x, y] in viewport fractions, radius as a fraction of the larger side, color, strength. */
const GLOWS = {
  top: [[0.16, 0.12, 0.55, 'moon', 0.16], [0.86, 0.95, 0.6, 'dusk', 0.12], [0.74, 0.36, 0.42, 'lilac', 0.07], [0.3, 0.82, 0.45, 'moon', 0.05]],
  how: [[0.82, 0.16, 0.5, 'moon', 0.12], [0.1, 0.88, 0.55, 'dusk', 0.08], [0.46, 0.5, 0.45, 'lilac', 0.05], [0.92, 0.9, 0.4, 'moon', 0.04]],
  capture: [[0.76, 0.36, 0.5, 'moon', 0.12], [0.14, 0.92, 0.5, 'dusk', 0.07], [0.3, 0.18, 0.42, 'lilac', 0.05], [0.95, 0.86, 0.4, 'moon', 0.04]],
  fast: [[0.3, 0.4, 0.6, 'amber', 0.16], [0.82, 0.24, 0.5, 'moon', 0.1], [0.14, 0.9, 0.45, 'dusk', 0.06], [0.9, 0.9, 0.4, 'lilac', 0.04]],
  currents: [[0.72, 0.5, 0.55, 'moon', 0.1], [0.18, 0.2, 0.45, 'dusk', 0.06], [0.1, 0.82, 0.42, 'lilac', 0.06], [0.92, 0.1, 0.4, 'amber', 0.04]],
  resurface: [[0.62, 1.15, 0.7, 'dusk', 0.2], [0.18, 0.2, 0.45, 'moon', 0.07], [0.9, 0.28, 0.4, 'lilac', 0.05], [0.4, 0.62, 0.42, 'amber', 0.05]],
  ask: [[0.7, 0.45, 0.55, 'moon', 0.12], [0.15, 0.86, 0.45, 'lilac', 0.06], [0.1, 0.14, 0.4, 'dusk', 0.05], [0.95, 0.9, 0.4, 'moon', 0.04]],
  grow: [[0.3, 0.5, 0.5, 'moon', 0.08], [0.76, 0.56, 0.5, 'lilac', 0.07], [0.5, 1.02, 0.5, 'dusk', 0.05], [0.9, 0.1, 0.4, 'moon', 0.03]],
  ambient: [[0.8, 0.2, 0.5, 'moon', 0.07], [0.15, 0.7, 0.5, 'lilac', 0.05], [0.5, 1.02, 0.5, 'dusk', 0.04], [0.3, 0.1, 0.4, 'moon', 0.03]],
  deep: [[0.5, 1.05, 0.6, 'dusk', 0.08], [0.2, 0.3, 0.45, 'moon', 0.04], [0.85, 0.4, 0.4, 'lilac', 0.03], [0.5, 0.5, 0.4, 'moon', 0.02]],
};

function glowPreset(chapter, ctx, progress) {
  const size = Math.max(ctx.vw, ctx.vh);
  return (GLOWS[chapter] ?? GLOWS.ambient).map(([u, v, r, color, alpha], i) => {
    // Resurfacing: its dusk glow rises like the sun as the chapter plays.
    const y = chapter === 'resurface' && i === 0 ? v - 0.3 * smoothstep(0, 1, progress) : v;
    return { x: u * ctx.vw, y: y * ctx.vh, r: r * size, color: [...GLOW_COLORS[color]], alpha };
  });
}

/** The four background glows for this moment, blended across chapter handovers. */
export function glowsFor(state, view) {
  const ctx = { vw: view.vw, vh: view.vh };
  const a = glowPreset(state.chapter, ctx, clamp(state.progress ?? 0, 0, 1));
  if (!state.next) return a;
  const b = glowPreset(state.next, ctx, 0);
  const t = clamp(state.blend ?? 0, 0, 1);
  return a.map((g, i) => ({
    x: mix(g.x, b[i].x, t),
    y: mix(g.y, b[i].y, t),
    r: mix(g.r, b[i].r, t),
    alpha: mix(g.alpha, b[i].alpha, t),
    color: g.color.map((c, j) => mix(c, b[i].color[j], t)),
  }));
}

export function energyFor(state) {
  const a = ENERGY[state.chapter] ?? ENERGY.ambient;
  if (!state.next) return a;
  return mix(a, ENERGY[state.next] ?? ENERGY.ambient, clamp(state.blend ?? 0, 0, 1));
}

/** The portal ring's radius: the phone stands inside it (diameter 0.95 of its height). */
export function ringRadius(rect) {
  return rect.h * 0.475;
}

/** Rings around the hero phone (full) and the final stage (faint), while on screen. */
export function ringsFor(view) {
  const rings = [];
  for (const [name, alpha] of [['hero-phone', 1], ['final-phone', 0.45]]) {
    const rect = view.anchors?.[name];
    if (!rect) continue;
    const R = ringRadius(rect);
    const c = center(rect);
    if (c.y + R * 1.3 < 0 || c.y - R * 1.3 > view.vh) continue;
    rings.push({ x: c.x, y: c.y, R, alpha });
  }
  return rings;
}
