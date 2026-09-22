// Wires the page together: scroll position to choreography to the Ocean, the
// sound toggles, the language choice, the use-case tabs, and the release
// demo. The only module that reads the DOM broadly; everything it drives is
// DOM-free or tested on its own.

import { createLamps, energyFor, glowsFor, layout, ringsFor, smoothstep } from './choreo.js';
import { createOcean } from './ocean.js';
import { createSound } from './sound.js';
import { mountVignettes } from './vignettes.js';

const params = new URLSearchParams(window.location.search);
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const longPage = document.body.dataset.page === 'long';

const store = {
  get(key) {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Private browsing: the choice lasts for this page only.
    }
  },
};

function motionPolicy() {
  return reduceMotion.matches || params.get('motion') === 'still' || longPage ? 'still' : 'full';
}

/** Which chapter holds the middle of the viewport, how far through it we are, and the handover to the next. */
function chapterState(sections, viewportHeight) {
  if (!sections.length) return { chapter: 'deep', progress: 0, next: null, blend: 0 };
  const middle = viewportHeight / 2;
  let index = sections.findIndex((section) => {
    const rect = section.getBoundingClientRect();
    return rect.top <= middle && rect.bottom > middle;
  });
  if (index === -1) index = sections[0].getBoundingClientRect().top > middle ? 0 : sections.length - 1;
  const rect = sections[index].getBoundingClientRect();
  const progress = Math.min(1, Math.max(0, (middle - rect.top) / Math.max(1, rect.height)));
  const following = sections[index + 1];
  const blend = following ? smoothstep(0.75, 1, progress) : 0;
  return {
    chapter: sections[index].dataset.chapter,
    progress,
    next: blend > 0 ? following.dataset.chapter : null,
    blend,
  };
}

function setupOcean(sound) {
  const field = document.querySelector('.ocean__field');
  if (!field) return null;
  const ocean = createOcean({
    water: document.querySelector('.ocean__water'),
    field,
    grain: document.querySelector('.ocean__grain'),
    policy: motionPolicy(),
  });
  const sections = [...document.querySelectorAll('[data-chapter]')];
  const anchors = [...document.querySelectorAll('[data-anchor]')];
  const quiet = [...document.querySelectorAll('[data-calm]')];
  const lamps = createLamps();
  let queued = false;

  function update() {
    queued = false;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const rects = {};
    for (const element of anchors) {
      const rect = element.getBoundingClientRect();
      rects[element.dataset.anchor] = { x: rect.left, y: rect.top, w: rect.width, h: rect.height };
    }
    const calm = [];
    for (const element of quiet) {
      const rect = element.getBoundingClientRect();
      if (rect.bottom > 0 && rect.top < vh) calm.push({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    }
    const view = { vw, vh, anchors: rects, calm };
    const state = chapterState(sections, vh);
    const scrollable = document.documentElement.scrollHeight - vh;
    const depth = longPage ? 0.6 : scrollable > 0 ? Math.min(1, window.scrollY / scrollable) : 0;
    ocean.setScene({
      depth,
      lamps,
      targets: layout(state, lamps, view),
      glows: glowsFor(state, view),
      rings: ringsFor(view),
      energy: energyFor(state),
    });
    sound?.setDepth(depth);
  }

  const refresh = () => {
    if (queued) return;
    queued = true;
    window.requestAnimationFrame(update);
  };

  window.addEventListener('scroll', refresh, { passive: true });
  window.addEventListener('resize', () => {
    ocean.resize();
    refresh();
  });
  document.addEventListener('visibilitychange', () => (document.hidden ? ocean.stop() : ocean.start()));
  ocean.start();
  ocean.resize();
  update();
  return { ocean, refresh };
}

function setupSound() {
  const toggles = [...document.querySelectorAll('[data-sound-toggle]')];
  if (!toggles.length) return null;
  const sound = createSound({ chimeUrl: new URL('../audio/ocean-received.m4a', import.meta.url).href });
  const show = (on) => {
    for (const toggle of toggles) toggle.setAttribute('aria-pressed', String(on));
  };
  const turn = async (on) => {
    if (on) {
      const ok = await sound.enable();
      show(ok);
      store.set('oryne.sound', ok ? 'on' : 'off');
    } else {
      sound.disable();
      show(false);
      store.set('oryne.sound', 'off');
    }
  };
  for (const toggle of toggles) toggle.addEventListener('click', () => turn(!sound.isOn));
  if (store.get('oryne.sound') === 'on') {
    // Browsers start audio only from a gesture, so resume on the visitor's first one.
    const resume = (event) => {
      window.removeEventListener('pointerdown', resume, true);
      window.removeEventListener('keydown', resume, true);
      if (event.target instanceof Element && event.target.closest('[data-sound-toggle]')) return;
      turn(true);
    };
    window.addEventListener('pointerdown', resume, true);
    window.addEventListener('keydown', resume, true);
  }
  return sound;
}

function setupRelease(ocean, sound) {
  const form = document.querySelector('[data-release]');
  if (!form) return;
  const input = form.querySelector('input');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector('[role="status"]');
  let clearTimer = 0;
  const sync = () => {
    button.disabled = input.value.trim() === '';
  };
  input.addEventListener('input', sync);
  sync();
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    // The thought drops out of the card's lower edge into open water.
    const card = form.getBoundingClientRect();
    ocean?.release({ text, x: card.left + card.width / 2, y: card.bottom + 40 });
    sound?.chime();
    input.value = '';
    sync();
    input.focus();
    status.textContent = '';
    window.requestAnimationFrame(() => {
      status.textContent = form.dataset.released;
    });
    window.clearTimeout(clearTimer);
    clearTimer = window.setTimeout(() => {
      status.textContent = '';
    }, 4000);
  });
}

/** WAI-ARIA tabs, built from panels that read fine as plain sections without JS. */
function setupTabs() {
  for (const root of document.querySelectorAll('[data-tabs]')) {
    const list = root.querySelector('[data-tab-list]');
    const panels = [...root.querySelectorAll('[data-tab-panel]')];
    if (!list || panels.length < 2) continue;
    list.setAttribute('role', 'tablist');
    if (list.dataset.label) list.setAttribute('aria-label', list.dataset.label);
    const tabs = panels.map((panel) => {
      const title = panel.querySelector('[data-tab-title]');
      const tab = document.createElement('button');
      tab.type = 'button';
      tab.className = 'tabs__tab';
      tab.id = `${panel.id}-tab`;
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panel.id);
      tab.textContent = title.textContent;
      title.classList.add('vh');
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', tab.id);
      panel.tabIndex = 0;
      list.append(tab);
      return tab;
    });
    const select = (index, focus) => {
      tabs.forEach((tab, i) => {
        const selected = i === index;
        tab.setAttribute('aria-selected', String(selected));
        tab.tabIndex = selected ? 0 : -1;
        panels[i].hidden = !selected;
      });
      if (focus) tabs[index].focus();
    };
    tabs.forEach((tab, i) => {
      tab.addEventListener('click', () => select(i, false));
      tab.addEventListener('keydown', (event) => {
        const last = tabs.length - 1;
        const target = { ArrowRight: i === last ? 0 : i + 1, ArrowLeft: i === 0 ? last : i - 1, Home: 0, End: last }[event.key];
        if (target === undefined) return;
        event.preventDefault();
        select(target, true);
      });
    });
    root.classList.add('tabs--ready');
    select(0, false);
  }
}

function setupLanguage() {
  for (const link of document.querySelectorAll('[data-lang-switch]')) {
    link.addEventListener('click', () => store.set('oryne.lang', link.dataset.langSwitch));
  }
}

function setupPerf(ocean) {
  if (params.get('debug') !== 'perf' || !ocean) return;
  const readout = document.createElement('div');
  readout.className = 'perf';
  document.body.append(readout);
  window.setInterval(() => {
    const s = ocean.stats();
    readout.textContent = `${s.fps.toFixed(0)} fps · ${s.ms.toFixed(1)} ms · ${s.lamps} lights${s.degraded ? ' · degraded' : ''}`;
  }, 500);
}

const sound = setupSound();
const water = setupOcean(sound);
const vignettes = mountVignettes(document.querySelectorAll('canvas[data-vignette]'), motionPolicy);
setupRelease(water?.ocean, sound);
setupTabs();
setupLanguage();
setupPerf(water?.ocean);

reduceMotion.addEventListener('change', () => {
  water?.ocean.setPolicy(motionPolicy());
  water?.refresh();
  vignettes?.refresh();
});

if (params.has('debug')) window.__oryne = { ocean: water?.ocean, sound };
