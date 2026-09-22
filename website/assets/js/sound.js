// The Ocean's sound. Surf generated live from filtered noise, swelling on the
// shared breath so it rises with the ring and the waves you see, and the
// app's own chime (OceanReceived) when a thought is released. Silent until
// the visitor asks for it; fades in and out; sleeps while the tab is hidden.

import { BREATH_BASE, breathAt, envelope, now, wave, wavesBetween } from './breath.js';

const LOOKAHEAD = 4;      // seconds of waves scheduled ahead of the clock
const TICK_MS = 1000;
const MASTER = 0.9;

/** The swell of one wave as automation curves: loudness and brightness follow the breath. */
export function swellCurve(w, from, depth, steps = 48) {
  const begin = Math.max(from, w.start);
  const end = w.start + w.duration;
  const gains = new Float32Array(steps);
  const cutoffs = new Float32Array(steps);
  for (let i = 0; i < steps; i++) {
    const time = begin + (i / (steps - 1)) * (end - begin);
    const lift = (envelope(w, (time - w.start) / w.duration) - BREATH_BASE) / (1 - BREATH_BASE);
    gains[i] = 0.03 + 0.47 * lift;
    cutoffs[i] = (380 + 1220 * lift ** 1.5) * (1 - 0.45 * depth);
  }
  return { begin, end, gains, cutoffs };
}

/** Looping noise whose tail is crossfaded into its head, so the loop has no seam. */
function seamlessNoise(ac, kind, seconds) {
  const length = Math.round(ac.sampleRate * seconds);
  const overlap = Math.round(ac.sampleRate * 0.5);
  const buffer = ac.createBuffer(2, length, ac.sampleRate);
  for (let channel = 0; channel < 2; channel++) {
    const raw = new Float32Array(length + overlap);
    let b0 = 0;
    let b1 = 0;
    let b2 = 0;
    let b3 = 0;
    let b4 = 0;
    let b5 = 0;
    let b6 = 0;
    let brown = 0;
    for (let i = 0; i < raw.length; i++) {
      const white = Math.random() * 2 - 1;
      if (kind === 'white') {
        raw[i] = white * 0.5;
      } else if (kind === 'pink') {
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.969 * b2 + white * 0.153852;
        b3 = 0.8665 * b3 + white * 0.3104856;
        b4 = 0.55 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.016898;
        raw[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
        b6 = white * 0.115926;
      } else {
        brown = (brown + 0.02 * white) / 1.02;
        raw[i] = brown * 3.5;
      }
    }
    const data = buffer.getChannelData(channel);
    for (let i = 0; i < length; i++) {
      if (i < overlap) {
        const k = i / overlap;
        data[i] = raw[i] * Math.sqrt(k) + raw[length + i] * Math.sqrt(1 - k);
      } else {
        data[i] = raw[i];
      }
    }
  }
  return buffer;
}

export function createSound({ chimeUrl }) {
  let ac = null;
  let nodes = null;
  let on = false;
  let depth = 0;
  let offset = 0;           // audio clock minus page clock
  let scheduledUntil = 0;   // page-clock time already scheduled
  let timer = 0;
  let chimeBuffer = null;
  let chimeLoading = null;

  function build() {
    const master = ac.createGain();
    master.gain.value = 0;
    master.connect(ac.destination);
    const analyser = ac.createAnalyser();
    analyser.fftSize = 2048;
    master.connect(analyser);
    const loop = (buffer) => {
      const source = ac.createBufferSource();
      source.buffer = buffer;
      source.loop = true;
      return source;
    };
    const filter = (type, frequency, q = 0.7) => {
      const node = ac.createBiquadFilter();
      node.type = type;
      node.frequency.value = frequency;
      node.Q.value = q;
      return node;
    };
    const gain = (value) => {
      const node = ac.createGain();
      node.gain.value = value;
      return node;
    };

    // Deep: the low body of the water, darker the further down the page.
    const deepFilter = filter('lowpass', 420, 0.4);
    const deep = loop(seamlessNoise(ac, 'brown', 7.3));
    deep.connect(deepFilter).connect(gain(0.1)).connect(master);

    // Swell: each wave's body, opened and closed by the breath.
    const swellPan = ac.createStereoPanner();
    swellPan.connect(master);
    const swellFilter = filter('lowpass', 380, 0.6);
    const swellGain = gain(0.03);
    const swell = loop(seamlessNoise(ac, 'pink', 8.1));
    swell.connect(swellFilter).connect(swellGain).connect(swellPan);

    // Wash: the fizz as a wave breaks and slides back.
    const washGain = gain(0);
    const wash = loop(seamlessNoise(ac, 'white', 6.7));
    wash.connect(filter('highpass', 2500)).connect(washGain).connect(swellPan);

    [deep, swell, wash].forEach((source) => source.start());
    return { master, analyser, deepFilter, swellFilter, swellGain, swellPan, washGain };
  }

  function ramp(param, value, seconds) {
    const t = ac.currentTime;
    param.cancelScheduledValues(t);
    param.setValueAtTime(param.value, t);
    param.linearRampToValueAtTime(value, t + seconds);
  }

  function scheduleWave(w, from) {
    const { begin, end, gains, cutoffs } = swellCurve(w, from, depth);
    const at = begin + offset;
    if (end - begin < 0.1 || at < ac.currentTime) return;
    const span = end - begin - 0.002;
    try {
      nodes.swellGain.gain.setValueCurveAtTime(gains, at + 0.001, span);
      nodes.swellFilter.frequency.setValueCurveAtTime(cutoffs, at + 0.001, span);
      nodes.swellPan.pan.setTargetAtTime(w.pan, at + 0.001, 1.5);
      const crest = w.start + w.rise + offset;
      if (crest - 0.3 > ac.currentTime) {
        const wash = nodes.washGain.gain;
        wash.setValueAtTime(0, crest - 0.3);
        wash.linearRampToValueAtTime(0.05 * w.peak * (1 - depth), crest + 0.35);
        wash.setTargetAtTime(0, crest + 0.35, 0.9);
      }
    } catch {
      // An overlapping curve means this wave is already scheduled; the water carries on.
    }
  }

  function schedule() {
    if (!on || !ac) return;
    const clock = now();
    const horizon = clock + LOOKAHEAD;
    for (const w of wavesBetween(Math.max(scheduledUntil, clock), horizon)) scheduleWave(w, w.start);
    scheduledUntil = horizon;
  }

  function begin() {
    offset = ac.currentTime - now();
    for (const param of [nodes.swellGain.gain, nodes.swellFilter.frequency, nodes.washGain.gain, nodes.swellPan.pan]) {
      param.cancelScheduledValues(0);
    }
    const clock = now();
    scheduleWave(wave(breathAt(clock).index), clock + 0.05);   // join the wave already under way
    scheduledUntil = clock;
    schedule();
    window.clearInterval(timer);
    timer = window.setInterval(schedule, TICK_MS);
  }

  function loadChime() {
    if (chimeLoading || !chimeUrl) return;
    chimeLoading = fetch(chimeUrl)
      .then((response) => response.arrayBuffer())
      .then((data) => ac.decodeAudioData(data))
      .then((buffer) => { chimeBuffer = buffer; })
      .catch(() => { chimeLoading = null; });
  }

  async function enable() {
    if (on) return true;
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return false;
    on = true;
    if (!ac) {
      ac = new Context({ latencyHint: 'playback' });
      nodes = build();
    }
    try {
      await ac.resume();
    } catch {
      on = false;
      return false;
    }
    if (!on) return false;   // turned off again while waking
    begin();
    ramp(nodes.master.gain, MASTER, 2.5);
    loadChime();
    return true;
  }

  function disable() {
    if (!on) return;
    on = false;
    window.clearInterval(timer);
    if (!ac) return;
    ramp(nodes.master.gain, 0, 1.2);
    window.setTimeout(() => {
      if (!on && ac.state === 'running') ac.suspend();
    }, 1300);
  }

  function chime() {
    if (!on || !chimeBuffer) return;
    const source = ac.createBufferSource();
    source.buffer = chimeBuffer;
    source.connect(nodes.master);
    source.start();
  }

  function setDepth(value) {
    depth = Math.max(0, Math.min(1, value));
    if (on && nodes) nodes.deepFilter.frequency.setTargetAtTime(420 - 200 * depth, ac.currentTime, 0.8);
  }

  /** Current output level in dBFS, for verification. */
  function rms() {
    if (!nodes) return -Infinity;
    const data = new Float32Array(nodes.analyser.fftSize);
    nodes.analyser.getFloatTimeDomainData(data);
    let sum = 0;
    for (const v of data) sum += v * v;
    return 10 * Math.log10(sum / data.length || 1e-12);
  }

  document.addEventListener('visibilitychange', async () => {
    if (!ac || !on) return;
    if (document.hidden) {
      window.clearInterval(timer);
      ramp(nodes.master.gain, 0, 0.3);
      window.setTimeout(() => {
        if (document.hidden) ac.suspend();
      }, 350);
    } else {
      await ac.resume();
      begin();
      ramp(nodes.master.gain, MASTER, 1);
    }
  });

  return {
    enable,
    disable,
    chime,
    setDepth,
    rms,
    get isOn() {
      return on;
    },
  };
}
