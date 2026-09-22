// The Ocean behind every page. A WebGL water body after the app's
// OceanBackground (near-black, lit toward the upper centre) with a few huge,
// blurred glows drifting in it, and above it a 2D layer for the large lights
// only: the portal from the app icon lit like a sunset lamp and a handful of
// lamps. No lines, no dots. No small dots anywhere. It knows nothing about
// scrolling or language: site.js hands it a scene, and it eases the water
// toward it.

import { breathAt, now } from './breath.js';
import { createNoise2D } from './noise.js';
import { drawLamp } from './lamps.js';

const TAU = Math.PI * 2;
const noise = createNoise2D(0x0cea);
// Released words are set like the headlines: Instrument Serif italic, or Songti upright for Chinese.
const WORDS_FONT = 'italic 400 21px "Instrument Serif", Georgia, serif';
const WORDS_FONT_ZH = '400 18px "Songti SC", "STSong", "Noto Serif CJK SC", "Source Han Serif SC", serif';

function fract(v) {
  return v - Math.floor(v);
}

// ------------------------------------------------------------ pure helpers

/** One exact step of a critically damped spring: a calm arrival that never overshoots from rest. */
export function springStep(position, velocity, target, dt, omega = 2.2) {
  const offset = position - target;
  const carry = (velocity + omega * offset) * dt;
  const decay = Math.exp(-omega * dt);
  return [target + (offset + carry) * decay, (velocity - omega * carry) * decay];
}

/** A light's wander on the shared field, in points: 8 to 15 s a cycle, as in the app. */
export function wanderOffset(seed, t, amplitude) {
  const progress = t / (8 + 7 * seed);
  return [
    noise(progress + seed * 16, seed * 7.3) * amplitude,
    noise(progress + 5.2 + seed * 11, seed * 3.1 + 9) * amplitude,
  ];
}

/** Breathing scale around 1: 6 to 10 s a breath, never in step with a neighbour. */
export function breathing(seed, t, depth) {
  const period = 6 + 4 * fract(seed * 7.919);
  return 1 + depth * Math.sin((t * TAU) / period + seed * TAU);
}

// ------------------------------------------------------------------ water

const VERTEX = `
attribute vec2 aPosition;
void main() { gl_Position = vec4(aPosition, 0.0, 1.0); }
`;

const FRAGMENT = `
precision mediump float;
uniform vec2 uResolution;
uniform vec2 uView;
uniform float uTime;
uniform float uDepth;
uniform float uBreath;
uniform vec4 uGlow[4];
uniform vec3 uGlowColor[4];

const vec3 ABYSS = vec3(0.020, 0.020, 0.030);
const vec3 DEEP = vec3(0.050, 0.055, 0.065);
const vec3 MID = vec3(0.090, 0.095, 0.110);
const vec3 CURRENT = vec3(0.150, 0.155, 0.175);

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * valueNoise(p);
    p = p * 2.03 + 11.7;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = gl_FragCoord.xy / uResolution;
  float aspect = uResolution.x / uResolution.y;
  vec2 p = vec2(uv.x * aspect, uv.y);
  float t = uTime;

  // The lit region roams like light through water (OceanBackground's centre wander).
  vec2 light = vec2((0.5 + 0.10 * sin(t * 0.037)) * aspect, 0.64 + 0.08 * cos(t * 0.032));
  vec2 q = vec2(fbm(p * 1.4 + vec2(0.0, t * 0.020)), fbm(p * 1.4 + vec2(5.2, -t * 0.017)));
  float caustic = fbm(p * 2.2 + 1.8 * q + vec2(t * 0.012, 0.0));
  float lit = (1.0 - smoothstep(0.0, 1.05, distance(p, light))) * (0.72 + 0.28 * caustic);
  lit *= (1.0 - 0.78 * uDepth) * (0.93 + 0.07 * uBreath);

  vec3 color = mix(ABYSS, DEEP, smoothstep(0.0, 1.0, uv.y) * (1.0 - 0.6 * uDepth));
  color = mix(color, MID, clamp(lit, 0.0, 1.0) * 0.8);
  color = mix(color, CURRENT, clamp(lit * lit, 0.0, 1.0) * 0.6);

  // The glows: a few huge, soft pools of light, each drifting on its own slow orbit.
  vec2 px = vec2(uv.x, 1.0 - uv.y) * uView;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    vec2 drift = vec2(sin(t * 0.05 + fi * 1.7), cos(t * 0.041 + fi * 2.3)) * uGlow[i].z * 0.08;
    float d = length(px - uGlow[i].xy - drift) / max(uGlow[i].z, 1.0);
    color += uGlowColor[i] * uGlow[i].w * exp(-d * d * 2.2) * (0.9 + 0.1 * uBreath);
  }
  color += vec3(-0.004, 0.0, 0.006) * uDepth;

  // Depth vignette: darker toward the edges, focus held in the middle.
  float vignette = smoothstep(0.35, 1.05, distance(uv, vec2(0.5, 0.55)));
  color = mix(color, ABYSS * 0.45, vignette * 0.5);

  color += (hash(gl_FragCoord.xy + fract(t)) - 0.5) / 255.0;
  gl_FragColor = vec4(color, 1.0);
}
`;

function createWater(canvas) {
  const gl = canvas.getContext('webgl', {
    alpha: false, antialias: false, depth: false, stencil: false,
    premultipliedAlpha: false, powerPreference: 'low-power',
  });
  if (!gl) return null;
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) || 'shader');
    return shader;
  };
  const program = gl.createProgram();
  try {
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) || 'link');
  } catch (error) {
    console.warn('Oryne: the WebGL water failed; the CSS water stands in.', error);
    return null;
  }
  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, 'aPosition');
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const uniform = (name) => gl.getUniformLocation(program, name);
  const u = {
    resolution: uniform('uResolution'), view: uniform('uView'), time: uniform('uTime'),
    depth: uniform('uDepth'), breath: uniform('uBreath'),
    glow: uniform('uGlow'), glowColor: uniform('uGlowColor'),
  };
  const glowData = new Float32Array(16);
  const colorData = new Float32Array(12);
  let lost = false;
  canvas.addEventListener('webglcontextlost', (event) => {
    event.preventDefault();
    lost = true;
    canvas.hidden = true;
  });
  return {
    resize(width, height, scale) {
      canvas.width = Math.max(1, Math.round(width * scale));
      canvas.height = Math.max(1, Math.round(height * scale));
      gl.viewport(0, 0, canvas.width, canvas.height);
    },
    draw(time, depth, breath, view, glows) {
      if (lost) return;
      for (let i = 0; i < 4; i++) {
        const g = glows[i] ?? { x: 0, y: 0, r: 1, alpha: 0, color: [0, 0, 0] };
        glowData.set([g.x, g.y, g.r, g.alpha], i * 4);
        colorData.set([g.color[0] / 255, g.color[1] / 255, g.color[2] / 255], i * 3);
      }
      gl.uniform2f(u.resolution, canvas.width, canvas.height);
      gl.uniform2f(u.view, view.w, view.h);
      gl.uniform1f(u.time, time);
      gl.uniform1f(u.depth, depth);
      gl.uniform1f(u.breath, breath);
      gl.uniform4fv(u.glow, glowData);
      gl.uniform3fv(u.glowColor, colorData);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}

// ------------------------------------------------------------ field pieces

function grainTile() {
  const tile = document.createElement('canvas');
  tile.width = 128;
  tile.height = 128;
  const context = tile.getContext('2d');
  const image = context.createImageData(128, 128);
  for (let i = 0; i < image.data.length; i += 4) {
    const v = Math.random() * 255;
    image.data[i] = v;
    image.data[i + 1] = v;
    image.data[i + 2] = v;
    image.data[i + 3] = 14;
  }
  context.putImageData(image, 0, 0);
  return tile.toDataURL('image/png');
}

const portals = new Map();

/**
 * The icon's portal lit like a sunset lamp, painted once per size: a disc of
 * light that shades from moonlit lilac at the top to dusk at the waterline, its
 * edge glowing, and a halo spilling past it. Painted as white light first,
 * then colored, so the halo carries the same sky as the disc.
 */
function portalSprite(radius) {
  const R = Math.max(1, Math.round(radius));
  const cached = portals.get(R);
  if (cached) return cached;
  const half = Math.ceil(R * 1.6);
  const canvas = document.createElement('canvas');
  canvas.width = half * 2;
  canvas.height = half * 2;
  const g = canvas.getContext('2d');
  const at = (d) => Math.min(1, d / half);
  const light = g.createRadialGradient(half, half, 0, half, half, half);
  light.addColorStop(0, 'rgba(255,255,255,0.2)');
  light.addColorStop(at(R * 0.72), 'rgba(255,255,255,0.24)');
  light.addColorStop(at(R * 0.94), 'rgba(255,255,255,0.34)');
  light.addColorStop(at(R * 0.995), 'rgba(255,255,255,0.5)');
  light.addColorStop(at(R * 1.035), 'rgba(255,255,255,0.19)');
  light.addColorStop(at(R * 1.16), 'rgba(255,255,255,0.07)');
  light.addColorStop(at(R * 1.38), 'rgba(255,255,255,0.02)');
  light.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = light;
  g.fillRect(0, 0, half * 2, half * 2);
  g.globalCompositeOperation = 'source-in';
  const sky = g.createLinearGradient(0, half - R, 0, half + R);
  sky.addColorStop(0, 'rgb(122,142,214)');
  sky.addColorStop(0.4, 'rgb(162,150,216)');
  sky.addColorStop(0.7, 'rgb(230,150,156)');
  sky.addColorStop(1, 'rgb(252,184,132)');
  g.fillStyle = sky;
  g.fillRect(0, 0, half * 2, half * 2);
  if (portals.size > 3) portals.clear();
  const sprite = { canvas, half };
  portals.set(R, sprite);
  return sprite;
}

function drawRing(ctx, ring, level, t) {
  const { x, y, R, alpha: A } = ring;
  if (A <= 0.01) return;
  const lift = 0.85 + 0.15 * level;
  const r = R * (1 + 0.006 * level);
  const { canvas, half } = portalSprite(R);
  const s = half * (r / R);
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.globalAlpha = Math.min(1, A * lift);
  ctx.drawImage(canvas, x - s, y - s, s * 2, s * 2);
  ctx.restore();

}

// ------------------------------------------------------------------ Ocean

const EASED = ['r', 'alpha', 'soft', 'warmth'];
const easeInOut = (p) => (p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2);
const easeOut = (p) => 1 - (1 - p) ** 3;
const unit = (v) => Math.min(1, Math.max(0, v));

export function createOcean({ water: waterCanvas, field, grain, policy = 'full' }) {
  const ctx = field.getContext('2d');
  const water = waterCanvas ? createWater(waterCanvas) : null;
  if (waterCanvas && !water) waterCanvas.hidden = true;
  if (grain) grain.style.backgroundImage = `url(${grainTile()})`;

  const released = [];
  let mode = policy;
  let scene = { depth: 0, lamps: [], targets: [], glows: [], rings: [], energy: 1 };
  let states = [];
  let glows = [];
  let vw = 1;
  let vh = 1;
  let dpr = 1;
  let waterScale = 0.5;
  let raf = 0;
  let running = false;
  let dirty = true;
  let last = now();
  let previous = 0;
  let frame = 0;
  let slowFor = 0;
  let degraded = false;
  let fps = 60;
  let ms = 0;
  const chinese = document.documentElement.lang.startsWith('zh');

  function kick() {
    if (running && !raf) raf = window.requestAnimationFrame(tick);
  }

  function resize() {
    vw = window.innerWidth;
    vh = window.innerHeight;
    dpr = Math.min(2, window.devicePixelRatio || 1);
    field.width = Math.round(vw * dpr);
    field.height = Math.round(vh * dpr);
    water?.resize(vw, vh, waterScale);
    dirty = true;
    kick();
  }

  function setScene(next) {
    if (states.length !== next.targets.length) {
      states = next.targets.map((t) => ({ ...t, vx: 0, vy: 0, drawX: t.x, drawY: t.y, scale: 1 }));
    }
    if (glows.length !== next.glows.length) glows = next.glows.map((g) => ({ ...g, color: [...g.color] }));
    scene = next;
    dirty = true;
    kick();
  }

  function setPolicy(next) {
    mode = next;
    dirty = true;
    kick();
  }

  function refresh() {
    dirty = true;
    kick();
  }

  function release({ text, x, y }) {
    released.push({
      text,
      born: now(),
      from: { x, y },
      to: {
        x: Math.min(vw - 60, Math.max(60, x + (Math.random() - 0.5) * 90)),
        y: Math.max(y + 40, Math.min(vh - 70, y + 150 + Math.random() * 60)),
      },
      seed: Math.random(),
    });
    if (released.length > 3) released.shift();
    dirty = true;
    kick();
    // A stilled Ocean does not animate: wake again to let the words and the light go.
    if (mode === 'still') {
      window.setTimeout(refresh, 4700);
      window.setTimeout(refresh, 10100);
    }
  }

  function update(dt) {
    const still = mode === 'still';
    const ease = still ? 1 : 1 - Math.exp(-dt * 3.2);
    states.forEach((s, i) => {
      const g = scene.targets[i];
      if (!g) return;
      if (still) {
        s.x = g.x;
        s.y = g.y;
        s.vx = 0;
        s.vy = 0;
      } else {
        [s.x, s.vx] = springStep(s.x, s.vx, g.x, dt);
        [s.y, s.vy] = springStep(s.y, s.vy, g.y, dt);
      }
      for (const key of EASED) s[key] += (g[key] - s[key]) * ease;
    });
    const glowEase = still ? 1 : 1 - Math.exp(-dt * 2.5);
    glows.forEach((g, i) => {
      const goal = scene.glows[i];
      if (!goal) return;
      for (const key of ['x', 'y', 'r', 'alpha']) g[key] += (goal[key] - g[key]) * glowEase;
      for (let c = 0; c < 3; c++) g.color[c] += (goal.color[c] - g.color[c]) * glowEase;
    });
  }

  function place(t, energy) {
    states.forEach((s, i) => {
      const l = scene.lamps[i];
      if (!l) return;
      const [wx, wy] = wanderOffset(l.seed, t, (3 + 3 * (1 - s.soft)) * energy);
      s.drawX = s.x + wx;
      s.drawY = s.y + wy;
      s.scale = breathing(l.seed, t, 0.02 * energy);
    });
  }

  function drawLamps() {
    const dim = 1 - 0.25 * scene.depth;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    // Deep, soft lights first, crisp ones on top.
    const order = states.map((_, i) => i).sort((a, b) => states[b].soft - states[a].soft);
    for (const i of order) {
      const s = states[i];
      const l = scene.lamps[i];
      if (!l || s.alpha < 0.004) continue;
      drawLamp(ctx, {
        x: s.drawX, y: s.drawY, r: s.r, scale: s.scale, alpha: s.alpha * dim,
        soft: s.soft, palette: l.palette, warmth: s.warmth,
      });
    }
    ctx.restore();
  }

  /** A released thought: its words sink inside a large soft light, which then drifts off to one side and lets go. */
  function drawReleased() {
    const t = now();
    const still = mode === 'still';
    for (let i = released.length - 1; i >= 0; i--) {
      if (t - released[i].born > 10) released.splice(i, 1);   // a released thought sinks out of view
    }
    for (const r of released) {
      const age = t - r.born;
      const p = still ? 1 : Math.min(1, age / 2.4);
      const e = easeInOut(p);
      const at = { x: r.from.x + (r.to.x - r.from.x) * e, y: r.from.y + (r.to.y - r.from.y) * e };
      const settled = still ? 0 : Math.max(0, age - 2.4);
      if (!still && p >= 1) {
        const [wx, wy] = wanderOffset(r.seed, t, 3);
        // Once it has settled, it drifts off to one side and keeps sinking, slowly.
        at.x += wx + settled * 9 * (r.seed < 0.5 ? -1 : 1);
        at.y += wy + settled * 4;
      }
      const fade = unit((10 - age) / 4.5);   // lets go over the last four seconds
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      drawLamp(ctx, { x: at.x, y: at.y, r: 64, alpha: 0.55 * fade, soft: Math.min(1, 0.35 + 0.45 * e + settled * 0.06) });
      ctx.restore();
      const wordsAlpha = unit(4.1 - age);   // the words let go just before the water opens
      if (wordsAlpha > 0) {
        const text = r.text.length > 42 ? `${r.text.slice(0, 41)}…` : r.text;
        ctx.font = chinese ? WORDS_FONT_ZH : WORDS_FONT;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        const half = ctx.measureText(text).width / 2;
        const x = Math.min(vw - 16 - half, Math.max(16 + half, at.x));
        ctx.fillStyle = `rgba(255,255,255,${(0.92 * wordsAlpha).toFixed(3)})`;
        ctx.fillText(text, x, at.y);
      }
    }
  }

  function render() {
    const started = performance.now();
    const clock = now();
    const dt = Math.min(0.05, Math.max(0, clock - last));
    last = clock;
    const t = mode === 'still' ? 0 : clock;
    const energy = mode === 'still' ? 0 : scene.energy;
    const level = breathAt(t).level;

    update(dt);
    if (water && (dirty || mode === 'still' || frame % 2 === 0)) {
      water.draw(t, scene.depth, level, { w: vw, h: vh }, glows);
    }

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, vw, vh);
    for (const ring of scene.rings) drawRing(ctx, ring, level, t);
    place(t, energy);
    drawLamps();
    drawReleased();

    ms = ms * 0.9 + (performance.now() - started) * 0.1;
    frame += 1;
    dirty = false;
  }

  function watchFrame(interval) {
    if (interval <= 0 || interval > 1) return;          // a paused tab, not a slow frame
    fps = fps * 0.9 + (1 / interval) * 0.1;
    slowFor = interval > 0.021 ? slowFor + interval : Math.max(0, slowFor - interval);
    if (!degraded && slowFor > 2) {
      // Two seconds of long frames: lighten the load with a softer, cheaper water.
      degraded = true;
      waterScale = 0.35;
      water?.resize(vw, vh, waterScale);
    }
  }

  function tick(timestamp) {
    raf = 0;
    if (!running) return;
    if (previous && mode === 'full') watchFrame((timestamp - previous) / 1000);
    previous = timestamp;
    render();
    if (mode === 'full') kick();
    else previous = 0;
  }

  function start() {
    if (running) return;
    running = true;
    last = now();
    previous = 0;
    dirty = true;
    kick();
  }

  function stop() {
    running = false;
    if (raf) window.cancelAnimationFrame(raf);
    raf = 0;
  }

  function stats() {
    return { fps, ms, lamps: states.length, degraded };
  }

  return { setScene, setPolicy, release, resize, refresh, start, stop, stats };
}
