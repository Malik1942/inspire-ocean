import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CHAPTERS, MIN_LAMP, createLamps, energyFor, glowsFor, layout, ringRadius, ringsFor,
} from '../assets/js/choreo.js';

const DESKTOP = { vw: 1440, vh: 900 };
const PHONE_D = { x: 900, y: 140, w: 300, h: 652 };
const WIDGETS_D = { x: 757, y: 210, w: 512, h: 158 };
const MOBILE = { vw: 390, vh: 844 };
const PHONE_M = { x: 65, y: 300, w: 260, h: 565 };
const WIDGETS_M = { x: 24, y: 420, w: 342, h: 332 };

function viewFor(size, phone, widgets) {
  return {
    ...size,
    anchors: {
      'hero-phone': phone,
      'currents-phone': phone,
      'ask-phone': phone,
      'final-phone': phone,
      'resurface-widget': widgets,
    },
  };
}

const CASES = [
  { name: 'desktop', view: viewFor(DESKTOP, PHONE_D, WIDGETS_D), phone: PHONE_D, widgets: WIDGETS_D },
  { name: 'mobile', view: viewFor(MOBILE, PHONE_M, WIDGETS_M), phone: PHONE_M, widgets: WIDGETS_M },
];
const lamps = createLamps();
const NUMERIC = ['x', 'y', 'r', 'alpha', 'soft', 'warmth'];
const PROGRESS = [0, 0.25, 0.5, 0.75, 1];
const currentsOf = (targets) => targets.filter((_, i) => lamps[i].role === 'current');
const warmOf = (targets) => targets[lamps.findIndex((l) => l.role === 'warm')];

test('the cast: four currents and one warm thought, nothing else', () => {
  assert.deepEqual(createLamps(), lamps);
  assert.deepEqual(lamps.filter((l) => l.role === 'current').map((l) => l.index), [0, 1, 2, 3]);
  assert.equal(lamps.filter((l) => l.role === 'warm').length, 1);
  assert.equal(lamps.length, 5);
});

test('every chapter gives one finite, on-screen target per lamp', () => {
  for (const { name, view } of CASES) {
    for (const chapter of CHAPTERS) {
      for (const progress of PROGRESS) {
        const targets = layout({ chapter, progress }, lamps, view);
        assert.equal(targets.length, lamps.length);
        for (const t of targets) {
          for (const key of NUMERIC) assert.ok(Number.isFinite(t[key]), `${name} ${chapter} ${key}`);
          assert.ok(t.x >= 0 && t.x <= view.vw && t.y >= 0 && t.y <= view.vh, `${name} ${chapter} off screen`);
          assert.ok(t.alpha >= 0 && t.alpha <= 1 && t.soft >= 0 && t.soft <= 1);
        }
      }
    }
  }
});

test('no small dots: every visible light is large', () => {
  assert.ok(MIN_LAMP >= 60);
  for (const { name, view } of CASES) {
    for (const chapter of CHAPTERS) {
      for (const progress of PROGRESS) {
        for (const t of layout({ chapter, progress }, lamps, view)) {
          if (t.alpha > 0.02) assert.ok(t.r >= MIN_LAMP, `${name} ${chapter}: a visible light of radius ${t.r}`);
        }
      }
    }
  }
});

test('chapters hand over without a jump', () => {
  for (const { name, view } of CASES) {
    for (let i = 0; i < CHAPTERS.length - 1; i++) {
      const [a, b] = [CHAPTERS[i], CHAPTERS[i + 1]];
      const end = layout({ chapter: a, progress: 1, next: b, blend: 1 }, lamps, view);
      const start = layout({ chapter: b, progress: 0 }, lamps, view);
      end.forEach((t, k) => {
        for (const key of NUMERIC) assert.ok(Math.abs(t[key] - start[k][key]) < 1e-9, `${name} ${a}→${b} ${key}`);
      });
      const g1 = glowsFor({ chapter: a, progress: 1, next: b, blend: 1 }, view);
      const g2 = glowsFor({ chapter: b, progress: 0 }, view);
      g1.forEach((g, k) => {
        for (const key of ['x', 'y', 'r', 'alpha']) assert.ok(Math.abs(g[key] - g2[k][key]) < 1e-9, `${name} glow ${a}→${b} ${key}`);
        g.color.forEach((c, j) => assert.ok(Math.abs(c - g2[k].color[j]) < 1e-9));
      });
    }
  }
});

test('the hero leaves the stage to the ring', () => {
  for (const { view } of CASES) {
    for (const t of layout({ chapter: 'top', progress: 0.5 }, lamps, view)) assert.equal(t.alpha, 0);
  }
});

test('lights over text dim to a whisper', () => {
  const { view } = CASES[0];
  const text = { x: 160, y: 120, w: 520, h: 640 };
  const inside = (t) => t.x > text.x - 10 && t.x < text.x + text.w + 10 && t.y > text.y - 10 && t.y < text.y + text.h + 10;
  let checked = 0;
  for (const chapter of CHAPTERS) {
    const plain = layout({ chapter, progress: 0.6 }, lamps, view);
    const calm = layout({ chapter, progress: 0.6 }, lamps, { ...view, calm: [text] });
    calm.forEach((t, i) => {
      if (!inside(t)) return;
      checked += 1;
      assert.ok(t.alpha <= plain[i].alpha * 0.25 + 1e-9, `${chapter}: light ${i} not dimmed over text`);
    });
  }
  assert.ok(checked > 0, 'no light ever crossed the text block');
});

test('currents stay out of focus and gather around the phone', () => {
  for (const { name, view, phone } of CASES) {
    const cx = phone.x + phone.w / 2;
    const cy = phone.y + phone.h / 2;
    const distance = (t) => Math.hypot(t.x - cx, t.y - cy);
    const spread = (targets) => targets.reduce((sum, t) => sum + distance(t), 0) / targets.length;
    const before = currentsOf(layout({ chapter: 'currents', progress: 0 }, lamps, view));
    const after = currentsOf(layout({ chapter: 'currents', progress: 1 }, lamps, view));
    assert.ok(spread(after) < spread(before) * 0.8, `${name}: the currents did not gather`);
    after.forEach((t, i) => {
      assert.equal(t.soft, 1, `${name}: current ${i} came into focus`);
      assert.ok(t.alpha > before[i].alpha, `${name}: current ${i} did not brighten`);
      assert.ok(distance(t) < phone.h * 0.6, `${name}: current ${i} is ${distance(t).toFixed(0)}px from the phone`);
    });
  }
});

test('the warm thought rises like the sun behind the widgets', () => {
  for (const { name, view, widgets } of CASES) {
    const before = warmOf(layout({ chapter: 'resurface', progress: 0 }, lamps, view));
    const after = warmOf(layout({ chapter: 'resurface', progress: 1 }, lamps, view));
    assert.ok(after.y < before.y - 150, `${name}: ${before.y} → ${after.y}`);
    assert.equal(before.soft, 1);
    assert.equal(after.soft, 0);
    assert.equal(after.alpha, 1);
    assert.equal(after.warmth, 1);
    assert.ok(Math.abs(after.x - (widgets.x + widgets.w / 2)) < 1e-9, `${name}: not centred on the widgets`);
    // Half of it clears the widgets' top edge; the rest glows behind them.
    assert.ok(after.y >= widgets.y && after.y <= widgets.y + after.r * 0.5, `${name}: sun at ${after.y}`);
  }
});

test('glows: four huge, soft pools of light in every chapter', () => {
  for (const { name, view } of CASES) {
    for (const chapter of CHAPTERS) {
      const glows = glowsFor({ chapter, progress: 0.5 }, view);
      assert.equal(glows.length, 4, `${name} ${chapter}`);
      for (const g of glows) {
        assert.ok(g.r >= 0.35 * Math.max(view.vw, view.vh), `${name} ${chapter}: a glow of radius ${g.r} is too small`);
        assert.ok(g.alpha > 0 && g.alpha <= 0.25);
        assert.equal(g.color.length, 3);
      }
    }
  }
});

test('rings follow the hero and final phones, and leave when they scroll away', () => {
  const rings = ringsFor({ ...DESKTOP, anchors: { 'hero-phone': PHONE_D } });
  assert.equal(rings.length, 1);
  assert.equal(rings[0].R, ringRadius(PHONE_D));
  assert.equal(rings[0].x, PHONE_D.x + PHONE_D.w / 2);
  assert.equal(rings[0].alpha, 1);
  const away = ringsFor({ ...DESKTOP, anchors: { 'hero-phone': { ...PHONE_D, y: -3000 } } });
  assert.equal(away.length, 0);
  const final = ringsFor({ ...DESKTOP, anchors: { 'final-phone': PHONE_D } });
  assert.equal(final[0].alpha, 0.45);
});

test('energy blends between chapters', () => {
  assert.equal(energyFor({ chapter: 'deep' }), 0.25);
  assert.ok(Math.abs(energyFor({ chapter: 'top', next: 'how', blend: 0.5 }) - 0.95) < 1e-9);
});
