// <skull-loader>: the Skull Salad logo as a loader. The salad hops in its bowl and tosses its leaves, with the
// nine cut-out layers at different depths so the bowl reads as 3D while it tilts.
//
//   <script type="module" src="skull-loader.js"></script>
//   <skull-loader size="200" label="Tossing your ideas" progress="0.4"></skull-loader>
//   document.querySelector('skull-loader').finish().then(showContent);
//
// Attributes
//   size      CSS pixels, default 160. Under 56 the layers are too small to read, so it hops the flat mark instead.
//   label     status line under the logo; also its accessible name.
//   progress  0–1 shows a determinate bar; leave it out for none.
//   delay     ms to wait before appearing, default 150, so quick loads never flash a loader.
//   state     "done" does the same as finish().
// Everything animates with the Web Animations API on transform and opacity only, so it stays smooth while the
// page is busy loading, which is exactly when a loader is on screen.

const ASSETS = new URL('assets/', import.meta.url);
const COMPACT = 56;
const MIN_VISIBLE = 700; // once shown, stay at least this long so the assembly never gets cut off halfway
const OUT = 'cubic-bezier(.23, 1, .32, 1)';
const SMOOTH = 'cubic-bezier(.45, 0, .3, 1)';
const POP = 'cubic-bezier(.34, 1.45, .64, 1)';

// Layers back to front, from tools/loader-assets.swift. depth: −1 far … 1 near. rect: left, top, width, height as %
// of the logo. pivot: where the layer hinges, % of the logo. amp: how far it lifts out of the bowl on a toss, % of the
// logo; fan: how far it tips outward, degrees, signed by side. Lifts stay under 2% because the hidden fills under each
// layer only reach about 3% of the logo. enter: when it arrives during assembly, ms. lag: follow-through delay, ms.
const LAYERS = [
  { file: '01-bowl-back.png', depth: -1, rect: [10.547, 33.789, 80.664, 42.383], bowl: true, enter: 0 },
  { file: '02-leaf-back-right.png', depth: -.7, rect: [59.375, 16.797, 35.742, 25.195], pivot: [68.95, 38.98], amp: 1.4, fan: 3.5, enter: 140, lag: 40 },
  { file: '03-leaf-mid-right.png', depth: -.5, rect: [67.383, 33.203, 27.734, 19.141], pivot: [74.40, 49.03], amp: 1.2, fan: 3, enter: 170, lag: 60 },
  { file: '04-leaf-back-left.png', depth: -.45, rect: [4.492, 35.938, 18.750, 18.164], pivot: [16.97, 50.78], amp: 1.2, fan: -3.5, enter: 200, lag: 50 },
  { file: '05-skull.png', depth: 0, rect: [15.625, 11.914, 56.055, 49.023], pivot: [43.79, 57.50], amp: 1.8, fan: 3, spin: true, enter: 260, lag: 0 },
  { file: '06-leaf-left-band.png', depth: .3, rect: [4.492, 48.242, 29.102, 23.242], pivot: [25.20, 68.17], amp: 1, fan: -2.5, enter: 380, lag: 30 },
  { file: '07-leaf-front-right.png', depth: .45, rect: [45.703, 46.289, 41.992, 23.633], pivot: [56.12, 66.60], amp: 1, fan: 2.5, enter: 420, lag: 20 },
  { file: '08-bowl-front.png', depth: .6, rect: [10.742, 44.727, 80.859, 48.047], bowl: true, enter: 0 },
  { file: '09-leaf-front-left.png', depth: .85, rect: [21.289, 54.688, 33.789, 19.531], pivot: [48.17, 73.95], amp: .9, fan: -2.5, enter: 470, lag: 25 },
];
const BOWL_BASE = [51.2, 92]; // bottom centre of the bowl, where the salad squashes and lands
const DEPTH = .1;             // z travel per unit of depth, as a fraction of the size
const PERSPECTIVE = 2.06;     // × size

// Bits of leaf tossed out of the bowl on the big hop, flying clear of the skull so they read against the background.
// at: start, % of the logo; dx, rise: travel at the top of the arc, %; spin: degrees; size: % of the logo.
const FLECKS = [
  { at: [20, 50], dx: -16, rise: -24, spin: -200, size: 10 },
  { at: [36, 46], dx: -12, rise: -34, spin: 150, size: 8 },
  { at: [66, 44], dx: 22, rise: -30, spin: 190, size: 9 },
];

// Two hops per loop, a big toss then a small one, tilting opposite ways so it never looks mechanical.
const CYCLE = 2000;
const HOPS = [
  { from: 0, to: .55, height: 12, toss: 1, tilt: 1, flecks: true },
  { from: .55, to: 1, height: 7, toss: .6, tilt: -1 },
];
const COMPACT_CYCLE = 900;
const COMPACT_HOPS = [{ from: 0, to: 1, height: 14, toss: 1, tilt: 0 }];

// Key moments of a hop, as fractions of it.
const K = { rest: 0, crouch: .10, lift: .22, apex: .47, float: .60, touch: .70, land: .78, settle: .90 };
const FK = { rest: 0, hide: .28, out: .36, high: .52, drift: .64, gone: .76 };

// The whole salad: crouch, push off, rise (decelerating), fall (accelerating), land and squash.
const UNIT = { rest: [0, 1, 1], crouch: [0, 1.05, .93], lift: [-.35, .97, 1.04], apex: [-1, 1, 1], touch: [0, .98, 1.02], land: [0, 1.05, .93], settle: [0, .99, 1.01] };
const UNIT_EASE = { rest: 'cubic-bezier(.33, 0, .2, 1)', crouch: 'cubic-bezier(.5, 0, .9, .6)', lift: 'cubic-bezier(.15, .55, .4, 1)', apex: 'cubic-bezier(.55, 0, .85, .45)', touch: OUT };
// The bowl tips toward the viewer and sideways in the air, which shows off the layers' depth.
const RIG = { rest: [0, 0, 0], crouch: [0, -3, 1], lift: [3, 6, -2], apex: [6, 12, -4], touch: [1, 3, -.5], land: [0, 0, 0] };
// Leaves and skull follow through: pressed into the bowl on take-off, thrown up past it at the top, landing just after it.
const MOVE = { rest: [0, 0, 1, 1], crouch: [.3, -.2, 1.02, .97], lift: [.8, -.3, .99, 1.02], apex: [-1, 1, 1, 1], float: [-.75, .6, 1, 1], touch: [-.2, .2, 1, 1], land: [.6, -.2, 1.02, .97], settle: [-.1, 0, 1, 1] };
const FLECK = { rest: [0, 0, 0, .6, 0], hide: [0, 0, 0, .6, 0], out: [.15, .3, .15, .9, 1], high: [.6, 1, .55, 1, 1], drift: [.9, .82, .8, 1, 1], gone: [1.05, .3, 1, .85, 0] };
const FLECK_EASE = { out: 'cubic-bezier(.2, .6, .4, 1)', drift: 'cubic-bezier(.5, 0, .9, .5)' };

/// Keyframes for a whole loop: `frame(key, hop)` gives the pose at each key moment of each hop, or null to skip it.
function loop(frame, { keys = K, easing = {}, hops = HOPS } = {}) {
  const frames = [];
  for (const hop of hops) {
    for (const [key, t] of Object.entries(keys)) {
      const pose = frame(key, hop);
      if (pose) frames.push({ offset: hop.from + t * (hop.to - hop.from), easing: easing[key] || SMOOTH, ...pose });
    }
  }
  frames.push({ offset: 1, ...frame('rest', hops[0]) });
  return frames;
}

const unitFrames = (hops) => loop((key, hop) => {
  if (!UNIT[key]) return null;
  const [y, sx, sy] = UNIT[key], g = hop.toss;
  return { transform: `translateY(${y * hop.height}%) scale(${1 + (sx - 1) * g}, ${1 + (sy - 1) * g})` };
}, { easing: UNIT_EASE, hops });

const shadowFrames = (hops) => loop((key, hop) => {
  if (!UNIT[key]) return null;
  const [y, sx] = UNIT[key], lift = -y * hop.height / 12, s = 1 - .38 * lift;
  return { transform: `scale(${(s * (1 + (sx - 1) * hop.toss)).toFixed(3)}, ${s.toFixed(3)})`, opacity: (1 - .6 * lift).toFixed(3) };
}, { easing: UNIT_EASE, hops });

const rigFrames = () => loop((key, hop) => {
  if (!RIG[key]) return null;
  const [rx, ry, rz] = RIG[key], t = hop.tilt * hop.toss;
  return { transform: `rotateX(${rx * hop.toss}deg) rotateY(${ry * t}deg) rotateZ(${rz * t}deg)` };
});

const moveFrames = (l) => loop((key, hop) => {
  const [y, r, sx, sy] = MOVE[key], g = hop.toss, fan = l.fan * (l.spin ? -hop.tilt : 1);
  return { transform: `translateY(${(y * l.amp * g).toFixed(3)}%) rotate(${(r * fan * g).toFixed(2)}deg) scale(${1 + (sx - 1) * g}, ${1 + (sy - 1) * g})` };
});

const fleckFrames = (f) => loop((key, hop) => {
  if (!hop.flecks && key !== 'rest') return null;
  const [x, y, r, s, o] = hop.flecks ? FLECK[key] : FLECK.rest;
  return { transform: `translate(${(x * f.dx).toFixed(2)}%, ${(y * f.rise).toFixed(2)}%) rotate(${(r * f.spin).toFixed(1)}deg) scale(${s})`, opacity: o };
}, { keys: FK, easing: FLECK_EASE });

// A glint of light sweeps across the skull at the top of the small hop.
const glintFrames = [
  { offset: 0, transform: 'translateX(-110%)' },
  { offset: .66, transform: 'translateX(-110%)', easing: SMOOTH },
  { offset: .88, transform: 'translateX(190%)' },
  { offset: 1, transform: 'translateX(190%)' },
];

const fleckSVG = (f, i) => `<svg viewBox="0 0 40 26" aria-hidden="true" style="left:${f.at[0]}%;top:${f.at[1]}%;width:${f.size}%">
  <defs><linearGradient id="fleck${i}" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#BAF8C4"/><stop offset=".45" stop-color="#21CA6A"/><stop offset="1" stop-color="#006344"/>
  </linearGradient></defs>
  <path d="M2 20C7 7 21 1 38 3c-4 11-17 21-36 17z" fill="url(#fleck${i})"/>
  <path d="M7 16C13 9 22 6 32 5" fill="none" stroke="#7EEF9A" stroke-width="2.2" stroke-linecap="round" opacity=".85"/>
</svg>`;

const pct = ([x, y, w, h]) => `left:${x}%;top:${y}%;width:${w}%;height:${h}%`;

const STYLE = `
  :host { display: inline-flex; flex-direction: column; align-items: center; vertical-align: middle; --size: 160px; }
  :host([hidden]) { display: none; }
  .stage { position: relative; width: var(--size); height: var(--size); perspective: calc(var(--size) * ${PERSPECTIVE}); opacity: 0; }
  .unit, .rig, .layer, .enter, .move, .fleck { position: absolute; inset: 0; }
  .unit { transform-origin: ${BOWL_BASE[0]}% ${BOWL_BASE[1]}%; transform-style: preserve-3d; }
  .rig { transform-origin: 50% 58%; transform-style: preserve-3d; }
  img, svg, .glint { position: absolute; display: block; pointer-events: none; user-select: none; -webkit-user-drag: none; }
  .mark { inset: 0; width: 100%; height: 100%; }
  .glint { overflow: hidden; -webkit-mask-size: 100% 100%; mask-size: 100% 100%; -webkit-mask-repeat: no-repeat; mask-repeat: no-repeat; }
  .glint i { position: absolute; top: 0; bottom: 0; width: 60%; transform: translateX(-110%);
    background: linear-gradient(100deg, transparent 20%, rgb(255 255 255 / .42) 50%, transparent 80%); }
  .fleck { opacity: 0; }
  .shadow { position: absolute; left: 24%; width: 54%; top: 88.5%; height: 7%; }
  .shadow i { position: absolute; inset: 0; border-radius: 50%; background: radial-gradient(closest-side, rgb(0 0 0 / .5), rgb(0 0 0 / .18) 60%, transparent); }
  .meta { display: flex; flex-direction: column; align-items: center; gap: 10px; margin-top: calc(var(--size) * -.02); opacity: 0; }
  .meta[hidden] { display: none; }
  .bar { position: relative; width: clamp(72px, calc(var(--size) * .6), 168px); height: 4px; border-radius: 99px; overflow: hidden;
    background: color-mix(in srgb, currentColor 14%, transparent); }
  .bar[hidden] { display: none; }
  .fill { position: absolute; inset: 0; border-radius: 99px; overflow: hidden; transform: translateX(-100%); }
  .fill i { position: absolute; inset: 0; transform: translateX(100%); background: linear-gradient(90deg, #2BD576, #5A6CF0 58%, #F06ACD); }
  .fill, .fill i { transition: transform 420ms ${OUT}; }
  .label { margin: 0; font: 500 13px/1.3 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; letter-spacing: -.005em;
    color: color-mix(in srgb, currentColor 62%, transparent); text-align: center; text-wrap: balance; max-width: calc(var(--size) * 1.5);
    font-variant-numeric: tabular-nums; }
  .label:empty { display: none; }
`;

export class SkullLoader extends HTMLElement {
  static observedAttributes = ['size', 'label', 'progress', 'state'];
  static #instances = new Set();
  static #speed = 1;

  /// Plays every loader at this rate (0.25 is handy for checking the motion frame by frame).
  static get speed() { return SkullLoader.#speed; }
  static set speed(v) {
    SkullLoader.#speed = v;
    for (const l of SkullLoader.#instances) for (const a of l.#root.getAnimations()) a.playbackRate = v;
  }

  #root = this.attachShadow({ mode: 'open' });
  #phase = 'idle'; // idle → enter → loop → exit → done
  #run = 0;        // bumped by replay(), so steps still pending from an earlier run stop
  #shownAt = 0;
  #timer = 0;
  #finishing = null;
  #parts = null;
  #reduced = matchMedia('(prefers-reduced-motion: reduce)');

  get size() { return Math.max(16, parseFloat(this.getAttribute('size')) || 160); }
  get compact() { return this.size < COMPACT; }
  get progress() { const p = parseFloat(this.getAttribute('progress')); return Number.isFinite(p) ? Math.min(1, Math.max(0, p)) : null; }
  set progress(v) { v == null ? this.removeAttribute('progress') : this.setAttribute('progress', v); }

  connectedCallback() {
    SkullLoader.#instances.add(this);
    this.setAttribute('role', 'progressbar');
    this.#render();
    this.#start();
  }

  disconnectedCallback() {
    SkullLoader.#instances.delete(this);
    clearTimeout(this.#timer);
    for (const a of this.#root.getAnimations()) a.cancel();
  }

  attributeChangedCallback(name, old, value) {
    if (!this.#parts || old === value) return;
    if (name === 'size') { this.replay(); return; }
    if (name === 'state' && value === 'done') { this.finish(); return; }
    this.#update(name === 'label');
  }

  /// Plays the exit and resolves once it has finished (a `finish` event fires then too).
  finish() {
    this.#finishing ??= this.#finish();
    return this.#finishing;
  }

  /// Starts over from the assembly.
  replay() {
    this.#run++;
    clearTimeout(this.#timer);
    for (const a of this.#root.getAnimations()) a.cancel();
    this.#finishing = null;
    if (this.getAttribute('state') === 'done') this.removeAttribute('state');
    this.#render();
    this.#start();
  }

  #render() {
    const size = this.size, compact = this.compact;
    this.style.setProperty('--size', `${size}px`);
    const layers = compact ? '' : LAYERS.map((l, i) => {
      const z = l.depth * DEPTH * size, k = 1 - (l.depth * DEPTH) / PERSPECTIVE;
      const origin = l.pivot ? `${l.pivot[0]}% ${l.pivot[1]}%` : `${BOWL_BASE[0]}% ${BOWL_BASE[1]}%`;
      const glint = l.spin ? `<div class="glint" style="${pct(l.rect)};-webkit-mask-image:url(${new URL(l.file, ASSETS)});mask-image:url(${new URL(l.file, ASSETS)})"><i></i></div>` : '';
      return `<div class="layer" data-i="${i}" style="transform:translateZ(${z.toFixed(2)}px) scale(${k.toFixed(5)})">
        <div class="enter" style="transform-origin:${origin}"><div class="move" style="transform-origin:${origin}">
          <img src="${new URL(l.file, ASSETS)}" alt="" style="${pct(l.rect)}">${glint}
        </div></div></div>`;
    }).join('');
    // The flecks sit between the front-right leaf and the bowl's front, so they come up out of the bowl.
    const fz = .5 * DEPTH * size, fk = 1 - (.5 * DEPTH) / PERSPECTIVE;
    const flecks = compact ? '' : `<div class="layer" style="transform:translateZ(${fz.toFixed(2)}px) scale(${fk.toFixed(5)})">${FLECKS.map((f, i) =>
      `<div class="fleck" style="transform-origin:${f.at[0] + f.size / 2}% ${f.at[1] + f.size / 3}%">${fleckSVG(f, i)}</div>`).join('')}</div>`;
    this.#root.innerHTML = `<style>${STYLE}</style>
      <div class="stage" part="stage">
        <div class="shadow"><i></i></div>
        <div class="unit">${compact ? `<img class="mark" src="${new URL('mark-128.png', ASSETS)}" alt="">` : `<div class="rig">${layers}${flecks}</div>`}</div>
      </div>
      <div class="meta" ${compact ? 'hidden' : ''}><div class="bar"><div class="fill"><i></i></div></div><p class="label"></p></div>`;
    const $ = (s) => this.#root.querySelector(s), $$ = (s) => [...this.#root.querySelectorAll(s)];
    this.#parts = {
      stage: $('.stage'), unit: $('.unit'), rig: $('.rig'), shadow: $('.shadow i'), meta: $('.meta'), bar: $('.bar'),
      fill: $('.fill'), grad: $('.fill i'), label: $('.label'), layers: $$('.layer[data-i]'), enters: $$('.enter'), moves: $$('.move'),
      flecks: $$('.fleck'), glint: $('.glint i'), imgs: $$('img'),
    };
    this.#update(false);
  }

  #update(labelChanged) {
    const { bar, fill, grad, label } = this.#parts, p = this.progress, text = this.getAttribute('label') || '';
    this.setAttribute('aria-label', text || 'Loading');
    bar.hidden = p == null;
    if (p == null) this.removeAttribute('aria-valuenow');
    else {
      this.setAttribute('aria-valuenow', Math.round(p * 100));
      fill.style.transform = `translateX(${(p - 1) * 100}%)`;
      grad.style.transform = `translateX(${(1 - p) * 100}%)`;
    }
    if (label.textContent === text) return;
    label.textContent = text;
    // A soft blur hides the swap, so the new status reads as the same line changing.
    if (labelChanged && this.#phase !== 'idle') this.#play(label, [{ opacity: .3, filter: 'blur(3px)' }, { opacity: 1, filter: 'blur(0)' }], { duration: 240, easing: OUT });
  }

  #play(el, frames, opts) {
    const a = el.animate(frames, opts);
    a.playbackRate = SkullLoader.#speed;
    return a;
  }

  #wait(ms) { return new Promise((r) => { this.#timer = setTimeout(r, ms / SkullLoader.#speed); }); }

  async #start() {
    this.#phase = 'idle';
    const run = this.#run, { imgs } = this.#parts;
    const delay = this.hasAttribute('delay') ? +this.getAttribute('delay') : 150;
    await Promise.all([this.#wait(delay), ...imgs.map((img) => img.decode().catch(() => {}))]);
    if (run !== this.#run || this.#phase !== 'idle' || this.#finishing) return;
    this.#phase = 'enter';
    this.#shownAt = performance.now();
    const parts = this.#parts, reduced = this.#reduced.matches;
    parts.stage.style.opacity = 1;
    const meta = this.#play(parts.meta, [{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 320, delay: reduced ? 0 : 260, easing: OUT, fill: 'both' });
    let arrivals;
    if (reduced) {
      arrivals = [this.#play(parts.stage, [{ opacity: 0 }, { opacity: 1 }], { duration: 300, easing: OUT })];
    } else if (this.compact) {
      arrivals = [this.#play(parts.stage, [{ opacity: 0, transform: 'scale(.85)' }, { opacity: 1, transform: 'none' }], { duration: 220, easing: OUT })];
    } else {
      arrivals = [this.#play(parts.shadow, [{ opacity: 0, transform: 'scale(.7)' }, { opacity: 1, transform: 'none' }], { duration: 400, easing: OUT, fill: 'backwards' })];
      LAYERS.forEach((l, i) => {
        const el = parts.enters[i];
        const from = l.bowl ? 'translateY(6%) scale(.92)' : l.spin ? 'translateY(5%) scale(.7)' : `scale(.55) rotate(${-l.fan * 4}deg)`;
        arrivals.push(this.#play(el, [{ transform: from }, { transform: 'none' }], { duration: l.spin ? 560 : 480, delay: l.enter, easing: POP, fill: 'backwards' }));
        this.#play(el, [{ opacity: 0 }, { opacity: 1 }], { duration: 160, delay: l.enter, easing: 'linear', fill: 'backwards' });
      });
    }
    try { await Promise.all([...arrivals.map((a) => a.finished), meta.finished]); } catch { return; }
    if (run === this.#run && this.#phase === 'enter') this.#loop();
  }

  #loop() {
    this.#phase = 'loop';
    const p = this.#parts, forever = { iterations: Infinity };
    if (this.#reduced.matches) {
      // Reduced motion: no hopping, just a slow breath so it still reads as working.
      this.#play(p.stage, [{ opacity: 1 }, { opacity: .55 }, { opacity: 1 }], { duration: 1800, easing: SMOOTH, ...forever });
      return;
    }
    if (this.compact) {
      this.#play(p.unit, unitFrames(COMPACT_HOPS), { duration: COMPACT_CYCLE, ...forever });
      this.#play(p.shadow, shadowFrames(COMPACT_HOPS), { duration: COMPACT_CYCLE, ...forever });
      return;
    }
    const cycle = { duration: CYCLE, ...forever };
    this.#play(p.unit, unitFrames(HOPS), cycle);
    this.#play(p.shadow, shadowFrames(HOPS), cycle);
    this.#play(p.rig, rigFrames(), cycle);
    LAYERS.forEach((l, i) => { if (l.pivot) this.#play(p.moves[i], moveFrames(l), { ...cycle, delay: l.lag }); });
    FLECKS.forEach((f, i) => this.#play(p.flecks[i], fleckFrames(f), cycle));
    if (p.glint) this.#play(p.glint, glintFrames, cycle);
  }

  async #finish() {
    const run = this.#run;
    clearTimeout(this.#timer);
    if (this.#phase === 'idle') {
      // Finished before it ever showed: skip the loader entirely.
      this.#phase = 'done';
      this.dispatchEvent(new Event('finish'));
      return;
    }
    const wait = MIN_VISIBLE - (performance.now() - this.#shownAt) * SkullLoader.#speed;
    if (wait > 0) await new Promise((r) => setTimeout(r, wait / SkullLoader.#speed));
    if (this.progress != null && this.progress < 1) {
      this.progress = 1;
      await new Promise((r) => setTimeout(r, 260 / SkullLoader.#speed));
    }
    if (run !== this.#run || this.#phase === 'done') return;
    this.#phase = 'exit';
    await this.#exit();
    if (run !== this.#run) return;
    this.#phase = 'done';
    this.dispatchEvent(new Event('finish'));
  }

  // Leaves from wherever it is mid-hop: every moving part eases home from its current pose while the layers burst
  // apart in depth and the whole thing fades, so nothing ever jumps.
  async #exit() {
    const p = this.#parts, reduced = this.#reduced.matches;
    const moving = [p.unit, p.rig, p.shadow, ...p.enters, ...p.moves, ...p.flecks].filter(Boolean);
    const from = moving.map((el) => { const cs = getComputedStyle(el); return { transform: cs.transform, opacity: cs.opacity }; });
    const stageOpacity = getComputedStyle(p.stage).opacity;
    for (const a of this.#root.getAnimations()) a.cancel();
    const opts = { duration: 380, easing: OUT, fill: 'forwards' };
    this.#play(p.meta, [{ opacity: 1 }, { opacity: 0 }], { duration: 160, easing: OUT, fill: 'forwards' });
    if (!reduced) {
      moving.forEach((el, i) => {
        const to = el === p.unit ? 'translateY(-1.5%) scale(1.03)' : el === p.shadow ? 'scale(1.15)' : 'none';
        const fade = p.flecks.includes(el) || el === p.shadow ? { opacity: 0 } : {};
        this.#play(el, [from[i], { transform: to, ...fade }], opts);
      });
      LAYERS.forEach((l, i) => {
        const el = p.layers[i];
        if (!el) return;
        const z = l.depth * DEPTH * this.size * 4, k = 1 - (l.depth * DEPTH) / PERSPECTIVE;
        this.#play(el, [{ transform: el.style.transform }, { transform: `translateZ(${z.toFixed(2)}px) scale(${k.toFixed(5)})` }], opts);
      });
    }
    const fade = this.#play(p.stage, [{ opacity: stageOpacity, filter: 'blur(0)' }, { opacity: 0, filter: reduced ? 'blur(0)' : 'blur(4px)' }],
      { duration: reduced ? 200 : 280, delay: reduced ? 0 : 90, easing: OUT, fill: 'forwards' });
    await fade.finished.catch(() => {});
  }
}

customElements.define('skull-loader', SkullLoader);
