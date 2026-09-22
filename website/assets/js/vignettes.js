// The four small visuals on the How it works cards, drawn with the Ocean's own
// large lights: a pale light setting into the water, three pools of light
// gathering, a warm one rising again, and one light with its answer. Nothing
// small, no lines, and every edge fades out. Each runs
// only while its card is on screen, and rests in a still frame when motion is off.

import { now } from './breath.js';
import { drawLamp } from './lamps.js';

const TAU = Math.PI * 2;
const ease = (p) => (p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2);
const easeOut = (p) => 1 - (1 - p) ** 3;
const unit = (v) => Math.min(1, Math.max(0, v));
const mix = (a, b, t) => a + (b - a) * t;

function lamp(ctx, options) {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  drawLamp(ctx, options);
  ctx.restore();
}

/** The waterline: a soft band of light lying on the water, brightest in the middle, never a line. */
function horizon(ctx, w, y, alpha) {
  const g = ctx.createRadialGradient(w / 2, y, 0, w / 2, y, w * 0.5);
  g.addColorStop(0, `rgba(170,190,228,${(0.16 * alpha).toFixed(3)})`);
  g.addColorStop(0.5, `rgba(170,190,228,${(0.05 * alpha).toFixed(3)})`);
  g.addColorStop(1, 'rgba(170,190,228,0)');
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.translate(0, y);
  ctx.scale(1, 0.09);
  ctx.fillStyle = g;
  ctx.fillRect(0, -w * 0.5, w, w);
  ctx.restore();
}

/** Paints only above the waterline: whatever sinks below it is gone from view. */
function aboveWater(ctx, w, line, paint) {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, w, line);
  ctx.clip();
  paint();
  ctx.restore();
}

/** The light's reflection: a soft glow on the water under it, fading every way. */
function reflection(ctx, x, line, r, color, strength) {
  if (strength <= 0.01) return;
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
  g.addColorStop(0, `rgba(${color},${(0.2 * strength).toFixed(3)})`);
  g.addColorStop(0.45, `rgba(${color},${(0.07 * strength).toFixed(3)})`);
  g.addColorStop(1, `rgba(${color},0)`);
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.translate(x, line);
  ctx.scale(0.62, 1.3);
  ctx.fillStyle = g;
  ctx.fillRect(-r, 0, r * 2, r);
  ctx.restore();
}

function bar(ctx, x, y, width, height) {
  ctx.beginPath();
  if (typeof ctx.roundRect === 'function') ctx.roundRect(x, y, width, height, height / 2);
  else ctx.rect(x, y, width, height);
  ctx.fill();
}

/** Fades the scene out toward every edge of its canvas. */
function fadeEdges(ctx, w, h) {
  ctx.save();
  ctx.globalCompositeOperation = 'destination-in';
  for (const [x1, y1] of [[w, 0], [0, h]]) {
    const g = ctx.createLinearGradient(0, 0, x1, y1);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(0.18, 'rgba(0,0,0,1)');
    g.addColorStop(0.82, 'rgba(0,0,0,1)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  }
  ctx.restore();
}

export const SCENES = {
  // A thought is let go: a pale light settles onto the water and sinks, and the water closes over it.
  capture(ctx, w, h, t, still) {
    const line = h * 0.68;
    const r = h * 0.27;
    const x = w * 0.5;
    const cycle = still ? 0.42 : (t % 7.5) / 7.5;
    const fall = ease(unit(cycle / 0.36));
    const sink = ease(unit((cycle - 0.36) / 0.4));
    const y = cycle < 0.36 ? mix(-r * 1.5, line - r * 0.25, fall) : mix(line - r * 0.25, line + r * 1.35, sink);
    horizon(ctx, w, line, 1);
    reflection(ctx, x, line, r, '180,198,238', 0.9 * (1 - sink));
    aboveWater(ctx, w, line, () => lamp(ctx, { x, y, r, alpha: 1, soft: 0.08, palette: 'moon' }));
  },

  // Three pools of light drift together into one current, and loosen again.
  gather(ctx, w, h, t, still) {
    const k = ease(still ? 1 : 0.5 - 0.5 * Math.cos((t / 11) * TAU));
    const r = h * 0.3;
    const lights = [
      { from: [0.16, 0.3], to: [0.42, 0.46], palette: 'dusk' },
      { from: [0.84, 0.26], to: [0.58, 0.44], palette: 'moon' },
      { from: [0.5, 1.02], to: [0.5, 0.62], palette: 'lilac' },
    ];
    for (const light of lights) {
      lamp(ctx, {
        x: mix(light.from[0], light.to[0], k) * w,
        y: mix(light.from[1], light.to[1], k) * h,
        r, alpha: 0.5 + 0.3 * k, soft: 0.85 - 0.45 * k, palette: light.palette,
      });
    }
  },

  // The forgotten one comes back: a warm light rises out of the water and into focus.
  resurface(ctx, w, h, t, still) {
    const line = h * 0.8;
    const r = h * 0.27;
    const x = w * 0.5;
    const cycle = t % 9;
    const rise = ease(still ? 1 : unit(cycle / 5.5));
    const hold = still || cycle < 8.2 ? 1 : 1 - (cycle - 8.2) / 0.8;
    const y = mix(line + r * 1.2, h * 0.42, rise);
    horizon(ctx, w, line, 0.9);
    reflection(ctx, x, line, r, '244,170,128', rise * hold);
    aboveWater(ctx, w, line, () => lamp(ctx, {
      x, y, r, alpha: (0.5 + 0.5 * rise) * hold, soft: 0.7 * (1 - rise), palette: 'dusk',
    }));
  },

  // One light, and its answer writing itself in.
  ask(ctx, w, h, t, still) {
    const cycle = (t % 7) / 7;
    const r = h * 0.24;
    const source = { x: w * 0.3, y: h * 0.5 };
    const end = w * 0.58;
    const out = still || cycle < 0.86 ? 1 : 1 - (cycle - 0.86) / 0.14;
    const rows = [[-15, 0.62], [-1, 0.44], [13, 0.54]];
    ctx.lineWidth = 1;
    rows.forEach(([dy], i) => {
      const g = ctx.createLinearGradient(source.x + r, 0, end, 0);
      g.addColorStop(0, `rgba(200,214,240,${(0.34 * out).toFixed(3)})`);
      g.addColorStop(1, 'rgba(200,214,240,0.04)');
      ctx.strokeStyle = g;
      ctx.beginPath();
      ctx.moveTo(source.x + r * 0.9, source.y + dy * 0.5);
      ctx.quadraticCurveTo((source.x + r + end) / 2, source.y + dy * (0.9 + 0.2 * i), end - 6, source.y + dy);
      ctx.stroke();
    });
    lamp(ctx, { x: source.x, y: source.y, r, alpha: 0.95, soft: 0.08, palette: 'moon' });
    rows.forEach(([dy, length], i) => {
      // Each line fades in as it grows, so a line just starting never shows as a dot.
      const grow = still ? 1 : easeOut(unit((cycle - 0.12 - 0.12 * i) / 0.3));
      ctx.fillStyle = `rgba(255,255,255,${(0.24 * out * grow * grow).toFixed(3)})`;
      bar(ctx, end, source.y + dy - 2.5, Math.max(20, length * w * 0.34 * grow), 5);
    });
  },
};

/** Starts each canvas[data-vignette] while it is on screen. `getPolicy()` returns 'full' or 'still'. */
export function mountVignettes(canvases, getPolicy) {
  const items = [...canvases].map((canvas) => ({
    canvas, draw: SCENES[canvas.dataset.vignette], visible: false, w: 0, h: 0, dpr: 1,
  }));
  if (!items.length) return undefined;
  let raf = 0;

  const size = (item) => {
    item.dpr = Math.min(2, window.devicePixelRatio || 1);
    item.w = item.canvas.clientWidth;
    item.h = item.canvas.clientHeight;
    item.canvas.width = Math.max(1, Math.round(item.w * item.dpr));
    item.canvas.height = Math.max(1, Math.round(item.h * item.dpr));
  };

  const paint = (item, t, still) => {
    const ctx = item.canvas.getContext('2d');
    ctx.setTransform(item.dpr, 0, 0, item.dpr, 0, 0);
    ctx.clearRect(0, 0, item.w, item.h);
    if (!item.draw) return;
    item.draw(ctx, item.w, item.h, t, still);
    fadeEdges(ctx, item.w, item.h);
  };

  const loop = () => {
    raf = 0;
    const still = getPolicy() === 'still';
    const t = now();
    let visible = false;
    for (const item of items) {
      if (!item.visible) continue;
      paint(item, t, still);
      visible = true;
    }
    if (visible && !still && !document.hidden) raf = window.requestAnimationFrame(loop);
  };

  const refresh = () => {
    if (!raf) raf = window.requestAnimationFrame(loop);
  };

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const item = items.find((candidate) => candidate.canvas === entry.target);
      if (item) item.visible = entry.isIntersecting;
    }
    refresh();
  });
  items.forEach((item) => {
    size(item);
    observer.observe(item.canvas);
  });
  window.addEventListener('resize', () => {
    items.forEach(size);
    refresh();
  });
  document.addEventListener('visibilitychange', refresh);
  return { refresh };
}
