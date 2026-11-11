// The sketchbook: one endless page per idea. Draw, write, collage, cut out, tape, label, connect,
// and embed live websites and video. Also the ink helpers (smoothing and hold-to-snap shapes).
(() => {
  const P = window.P;
  const NS = 'http://www.w3.org/2000/svg';
  const r1 = (n) => Math.round(n * 10) / 10;
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const pbox = (pts) => {
    let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
    for (const p of pts) { x1 = Math.min(x1, p.x); y1 = Math.min(y1, p.y); x2 = Math.max(x2, p.x); y2 = Math.max(y2, p.y); }
    return { x1, y1, x2, y2 };
  };

  P.FACES = {
    serif: ['Serif', 'Georgia, "Times New Roman", serif'],
    sans: ['Sans', '-apple-system, "Helvetica Neue", sans-serif'],
    round: ['Rounded', 'ui-rounded, "SF Pro Rounded", "Arial Rounded MT Bold", sans-serif'],
    mono: ['Mono', 'ui-monospace, Menlo, monospace'],
    type: ['Typewriter', '"Special Elite", "American Typewriter", monospace'],
  };
  P.TYPE_NAMES = { note: 'Sticky note', text: 'Writing', label: 'Label', image: 'Image', video: 'Video', embed: 'Video', web: 'Website', link: 'Link', swatch: 'Colour', type: 'Type sample', sketch: 'Drawing', zone: 'Section', arrow: 'Connector', tape: 'Tape' };
  const FRAMES = new Set(['web', 'embed', 'video']);
  const NO_ROTATE = new Set(['zone', 'arrow', 'label', 'web', 'embed', 'video']);
  const KEEP_ASPECT = new Set(['image', 'video', 'embed', 'sketch']);
  const EDITABLE = { note: '.body', text: '.body', label: '.body', zone: '.zl', type: 'b' };

  // ---------- ink ----------
  const rdp = (pts, eps) => {
    if (pts.length < 3) return pts.slice();
    const keep = new Uint8Array(pts.length);
    keep[0] = keep[pts.length - 1] = 1;
    const stack = [[0, pts.length - 1]];
    while (stack.length) {
      const [s, e] = stack.pop();
      const A = pts[s], B = pts[e], L = dist(A, B);
      let md = 0, mi = -1;
      for (let i = s + 1; i < e; i++) {
        const p = pts[i];
        const d = L > 1 ? Math.abs((B.x - A.x) * (A.y - p.y) - (A.x - p.x) * (B.y - A.y)) / L : dist(A, p);
        if (d > md) { md = d; mi = i; }
      }
      if (md > eps && mi > 0) { keep[mi] = 1; stack.push([s, mi], [mi, e]); }
    }
    return pts.filter((_, i) => keep[i]);
  };
  const soften = (pts) => pts.map((p, i) => {
    if (i === 0 || i === pts.length - 1) return p;
    const a = pts[i - 1], b = pts[i + 1];
    return { x: (a.x + p.x * 2 + b.x) / 4, y: (a.y + p.y * 2 + b.y) / 4 };
  });
  P.ink = {
    raw: (pts) => 'M' + pts.map((p) => r1(p.x) + ' ' + r1(p.y)).join('L') + (pts.length === 1 ? 'l.1 0' : ''),
    smooth(pts, eps = 1) {
      const s = rdp(soften(pts), eps);
      if (s.length < 3) return P.ink.raw(s);
      let d = `M${r1(s[0].x)} ${r1(s[0].y)}`;
      for (let i = 1; i < s.length - 1; i++) {
        const m = { x: (s[i].x + s[i + 1].x) / 2, y: (s[i].y + s[i + 1].y) / 2 };
        d += `Q${r1(s[i].x)} ${r1(s[i].y)} ${r1(m.x)} ${r1(m.y)}`;
      }
      const l = s[s.length - 1];
      return d + `L${r1(l.x)} ${r1(l.y)}`;
    },
    // Classifies a stroke as a straight line, box, ellipse or free scribble.
    recognise(pts) {
      const b = pbox(pts), W = b.x2 - b.x1, H = b.y2 - b.y1, M = Math.max(W, H);
      if (pts.length < 2 || M < 3) return { shape: 'free' };
      let len = 0;
      for (let i = 1; i < pts.length; i++) len += dist(pts[i - 1], pts[i]);
      const a = pts[0], e = pts[pts.length - 1], se = dist(a, e);
      if (len > 20 && se / len > 0.9) return { shape: 'line', a, e };
      if (se < 0.3 * M && len > 2.3 * M && Math.min(W, H) > 12) {
        const cx = (b.x1 + b.x2) / 2, cy = (b.y1 + b.y2) / 2, rx = W / 2, ry = H / 2;
        let rectErr = 0, ellErr = 0;
        for (const p of pts) {
          rectErr += Math.min(Math.min(Math.abs(p.x - b.x1), Math.abs(p.x - b.x2)) / W, Math.min(Math.abs(p.y - b.y1), Math.abs(p.y - b.y2)) / H);
          ellErr += Math.abs(Math.hypot((p.x - cx) / rx, (p.y - cy) / ry) - 1);
        }
        rectErr /= pts.length; ellErr /= pts.length;
        if (rectErr < 0.04 && rectErr * 3 < ellErr) return { shape: 'rect', b };
        if (ellErr < 0.16) return { shape: 'ellipse', b };
      }
      return { shape: 'free' };
    },
    // A clean path for a recognised shape (or a smoothed scribble), plus its bounds.
    shape(pts, eps = 1) {
      const R = P.ink.recognise(pts);
      let d, b;
      if (R.shape === 'line') {
        const a = R.a; let e = R.e;
        const ang = (((Math.atan2(e.y - a.y, e.x - a.x) * 180) / Math.PI) % 90 + 90) % 90;
        if (ang < 6 || ang > 84) e = Math.abs(e.x - a.x) > Math.abs(e.y - a.y) ? { x: e.x, y: a.y } : { x: a.x, y: e.y };
        d = `M${r1(a.x)} ${r1(a.y)}L${r1(e.x)} ${r1(e.y)}`;
        b = pbox([a, e]);
      } else if (R.shape === 'rect') {
        b = R.b;
        d = `M${r1(b.x1)} ${r1(b.y1)}H${r1(b.x2)}V${r1(b.y2)}H${r1(b.x1)}Z`;
      } else if (R.shape === 'ellipse') {
        b = R.b;
        const cx = (b.x1 + b.x2) / 2, cy = (b.y1 + b.y2) / 2, rx = (b.x2 - b.x1) / 2, ry = (b.y2 - b.y1) / 2;
        d = `M${r1(cx - rx)} ${r1(cy)}A${r1(rx)} ${r1(ry)} 0 1 0 ${r1(cx + rx)} ${r1(cy)}A${r1(rx)} ${r1(ry)} 0 1 0 ${r1(cx - rx)} ${r1(cy)}Z`;
      } else {
        d = P.ink.smooth(pts, eps);
        b = pbox(pts);
      }
      return { shape: R.shape, d, b };
    },
    dots: (list) => list.map(([x, y, r]) => `M${r1(x - r)} ${r1(y)}a${r1(r)} ${r1(r)} 0 1 0 ${r1(r * 2)} 0a${r1(r)} ${r1(r)} 0 1 0 ${r1(-r * 2)} 0`).join(''),
    // Wraps shaped strokes as a drawing item; the viewBox keeps the original coordinates.
    toItem(shapes, pad = 6) {
      const b = pbox(shapes.flatMap((s) => [{ x: s.b.x1, y: s.b.y1 }, { x: s.b.x2, y: s.b.y2 }]));
      const x = b.x1 - pad, y = b.y1 - pad, w = b.x2 - b.x1 + pad * 2, h = b.y2 - b.y1 + pad * 2;
      return { x, y, w, h, vb: `${r1(x)} ${r1(y)} ${r1(w)} ${r1(h)}`, d: shapes.map((s) => s.d).join(' '), shape: shapes.length === 1 ? shapes[0].shape : 'free' };
    },
  };

  // ---------- text export (hand-off) ----------
  P.asText = (list) => list.map((it) => {
    switch (it.type) {
      case 'note': case 'text': case 'label': return it.text || '';
      case 'link': case 'web': case 'embed': return [it.title, it.src || it.url, it.why && '— ' + it.why].filter(Boolean).join('\n');
      case 'image': case 'video': return `[${P.TYPE_NAMES[it.type]}]` + (it.why ? ' ' + it.why : '') + (it.src ? ' ' + it.src : '');
      case 'swatch': return 'Colour ' + it.color;
      case 'type': return `Type: ${it.text} (${(P.FACES[it.face] || P.FACES.serif)[0]})`;
      case 'zone': return '## ' + (it.label || 'Section');
      default: return '';
    }
  }).filter(Boolean).join('\n\n');
  P.ideaText = (ideaId) => {
    const i = P.idea(ideaId);
    const items = P.itemsOf(ideaId).filter((o) => !['arrow', 'sketch', 'tape'].includes(o.type));
    const zones = items.filter((o) => o.type === 'zone').sort((a, b) => a.y - b.y || a.x - b.x);
    const inZ = (z, o) => o.x + o.w / 2 > z.x && o.x + o.w / 2 < z.x + z.w && o.y + o.h / 2 > z.y && o.y + o.h / 2 < z.y + z.h;
    const order = (l) => l.sort((a, b) => a.y - b.y || a.x - b.x);
    const used = new Set();
    let out = `# ${i.name}\n${i.kind} · ${i.stage}${i.next ? '\nNext: ' + i.next : ''}\n\n`;
    for (const z of zones) {
      const mem = order(items.filter((o) => o.type !== 'zone' && !used.has(o.id) && inZ(z, o)));
      mem.forEach((o) => used.add(o.id));
      out += P.asText([z, ...mem]) + '\n\n';
    }
    const rest = order(items.filter((o) => o.type !== 'zone' && !used.has(o.id)));
    if (rest.length) out += P.asText(rest) + '\n';
    return out.trim() + '\n';
  };

  // ---------- state ----------
  const C = (P.canvas = { sel: new Set(), tool: 'select' });
  let view, vp, world, svgA, zl, bar, wheel, idea, ideaId, ac;
  let editing = null, live = null, glide = 0, camAnim = 0, space = false, busy = false, cutId = null;

  const cam = () => idea.cam;
  const node = (id) => world && world.querySelector(`.it[data-id="${id}"]`);
  const sel = () => [...C.sel].map(P.item).filter(Boolean);
  const rc = (it) => ({ cx: it.x + it.w / 2, cy: it.y + it.h / 2, hw: it.w / 2, hh: it.h / 2 });
  const toWorld = (sx, sy) => {
    const r = vp.getBoundingClientRect(), c = cam();
    return { x: (sx - r.left - c.x) / c.z, y: (sy - r.top - c.y) / c.z };
  };
  const center = () => { const r = vp.getBoundingClientRect(); return toWorld(r.left + r.width / 2, r.top + r.height / 2); };
  const fontFor = (it) => P.fontOf(it.font || idea.font);
  const insideZone = (z) => P.itemsOf(ideaId).filter((o) => o.type !== 'zone' && o.type !== 'arrow' && o.x + o.w / 2 > z.x && o.x + o.w / 2 < z.x + z.w && o.y + o.h / 2 > z.y && o.y + o.h / 2 < z.y + z.h);
  const sig = (it) => { const { x, y, z, w, h, rot, ...rest } = it; return JSON.stringify(rest); };
  const clipCss = (clip) => `polygon(${clip.map(([u, v]) => `${(u * 100).toFixed(2)}% ${(v * 100).toFixed(2)}%`).join(',')})`;

  function track(move, up) {
    const mv = (e) => move(e);
    const u = (e) => {
      window.removeEventListener('pointermove', mv);
      window.removeEventListener('pointerup', u);
      window.removeEventListener('pointercancel', u);
      up && up(e);
    };
    window.addEventListener('pointermove', mv);
    window.addEventListener('pointerup', u);
    window.addEventListener('pointercancel', u);
  }
  const commit = () => { busy = false; P.touch(ideaId); P.save(); renderBar(); };

  // ---------- camera ----------
  function applyCam() {
    const c = cam();
    c.vw = vp.clientWidth; c.vh = vp.clientHeight;
    world.style.transform = `translate(${c.x}px,${c.y}px) scale(${c.z})`;
    let gs = 24 * c.z;
    while (gs < 12) gs *= 2;
    vp.style.setProperty('--gs', gs + 'px');
    vp.style.setProperty('--gx', c.x + 'px');
    vp.style.setProperty('--gy', c.y + 'px');
    vp.style.setProperty('--iz', 1 / c.z);
    zl.textContent = Math.round(c.z * 100) + '%';
    positionBar();
  }
  function flyTo(t) {
    cancelAnimationFrame(camAnim);
    const c = cam();
    if (P.reduced()) { Object.assign(c, t); applyCam(); P.save(); return; }
    const step = () => {
      let done = true;
      for (const k of ['x', 'y', 'z']) {
        c[k] += (t[k] - c[k]) * 0.2;
        if (Math.abs(t[k] - c[k]) > (k === 'z' ? 0.001 : 0.5)) done = false;
      }
      if (done) Object.assign(c, t);
      applyCam();
      if (done) P.save(); else camAnim = requestAnimationFrame(step);
    };
    camAnim = requestAnimationFrame(step);
  }
  function camFor(items, maxZ = 1.1) {
    const W = vp.clientWidth, H = vp.clientHeight, top = 76, bottom = 40, left = 90, right = 40;
    if (!items.length) return { x: W / 2, y: H / 2, z: 1 };
    // Section labels sit above their section, so include them when framing.
    const b = P.bbox(items.map((o) => (o.type === 'zone' ? { x: o.x, y: o.y - 36, w: o.w, h: o.h + 36 } : o)));
    const z = P.clamp(Math.min((W - left - right) / Math.max(b.w, 1), (H - top - bottom) / Math.max(b.h, 1)), 0.1, maxZ);
    return { z, x: left + (W - left - right) / 2 - (b.x1 + b.w / 2) * z, y: top + (H - top - bottom) / 2 - (b.y1 + b.h / 2) * z };
  }
  function fit(animate) {
    const t = camFor(P.itemsOf(ideaId).filter((o) => o.type !== 'arrow'));
    if (animate) flyTo(t); else { Object.assign(cam(), t); applyCam(); }
  }
  function zoomAt(sx, sy, k, animate) {
    const c = cam(), z = P.clamp(c.z * k, 0.1, 5), f = z / c.z;
    const t = { x: sx - (sx - c.x) * f, y: sy - (sy - c.y) * f, z };
    if (animate) flyTo(t); else { cancelAnimationFrame(camAnim); Object.assign(c, t); applyCam(); }
  }
  const zoomStep = (k) => zoomAt(vp.clientWidth / 2, vp.clientHeight / 2, k, true);
  function focus(id) {
    const it = P.item(id);
    if (!it || it.ideaId !== ideaId) return;
    C.sel = new Set([id]);
    markSel();
    const z = Math.max(cam().z, 0.9), W = vp.clientWidth, H = vp.clientHeight;
    flyTo({ z, x: W / 2 - (it.x + it.w / 2) * z, y: H / 2 - (it.y + it.h / 2) * z });
    const n = node(id);
    if (n) { n.classList.remove('flash'); void n.offsetWidth; n.classList.add('flash'); }
  }

  // ---------- rendering ----------
  function el(it) {
    const d = document.createElement('div');
    d.className = `it it-${it.type}${it.clip ? ' cut' : ''}${it.unsorted ? ' unsorted' : ''}${it.light ? ' light' : ''}${live === it.id ? ' live' : ''}`;
    d.dataset.id = it.id;
    if (it.font) d.dataset.f = it.font;
    const hand = P.esc(P.fontOf(idea.font));
    const why = it.why ? `<div class="why" style="font-family:${hand}">${P.esc(it.why)}</div>` : '';
    const src = P.esc(P.srcOf(it));
    const bar = (icon, label, url) => `<div class="fbar">${P.icon(icon)}<span>${P.esc(label)}</span>${url ? `<a class="fb-open" href="${P.esc(url)}" target="_blank" rel="noopener" title="Open in browser">${P.icon('out')}</a>` : ''}</div>`;
    const shield = (msg) => `<div class="shield"><span>${msg}</span></div>`;
    let h = '';
    switch (it.type) {
      case 'note': h = `<div class="body" data-ph="Write…" style="font-family:${P.esc(fontFor(it))}">${P.esc(it.text)}</div>`; d.style.background = it.color || P.NOTE_COLORS[0]; break;
      case 'text': h = `<div class="body" data-ph="Write…" style="font-family:${P.esc(fontFor(it))}${it.color ? `;color:${it.color}` : ''}">${P.esc(it.text)}</div>`; break;
      case 'label': h = `<div class="body" data-ph="Label">${P.esc(it.text)}</div>`; break;
      case 'image': {
        const c = it.crop, st = c ? `width:${100 / c.w}%;height:${100 / c.h}%;left:${(-c.x / c.w) * 100}%;top:${(-c.y / c.h) * 100}%` : '';
        h = `<div class="cw"${it.clip ? ` style="clip-path:${clipCss(it.clip)}"` : ''}><img src="${src}" alt="" draggable="false"${st ? ` style="${st}"` : ''}></div>` + why;
        break;
      }
      case 'video': h = bar('play', it.title || 'Video', '') + `<video src="${src}" playsinline preload="metadata"${live === it.id ? ' controls' : ''}></video>` + shield('Double-click to play') + why; break;
      case 'embed': h = bar('play', it.title || it.provider || 'Video', it.url) + `<iframe src="${P.esc(it.src)}" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>` + shield('Double-click to play') + why; break;
      case 'web': h = bar('globe', P.domain(it.url) || it.url, it.url) + `<iframe src="${P.esc(it.url)}" referrerpolicy="strict-origin-when-cross-origin"></iframe>` + shield('Double-click to use this page') + why; break;
      case 'link': h = `<i class="fav">${P.esc((P.domain(it.src) || it.title || '?')[0].toUpperCase())}</i><div class="lk"><b>${P.esc(it.title || it.src)}</b><small>${P.esc(P.domain(it.src) || 'file')}</small></div>` + why; break;
      case 'swatch': h = `<i style="background:${P.esc(it.color)}"></i><span>${P.esc(it.color)}</span>`; break;
      case 'type': { const f = P.FACES[it.face] || P.FACES.serif; h = `<b style="font-family:${P.esc(f[1])}">${P.esc(it.text)}</b><small>${f[0]}</small>`; break; }
      case 'sketch': {
        const tool = it.tool || 'pen', col = P.esc(it.color || it.ink || P.INKS[0]);
        const style = tool === 'spray' ? `fill:${col}` : `stroke:${col};stroke-width:${it.size || 2.6}`;
        h = `<svg class="k-${tool}" viewBox="${it.vb || `0 0 ${it.vw} ${it.vh}`}" preserveAspectRatio="none"><path d="${P.esc(it.d)}" style="${style}"/></svg>` + why;
        break;
      }
      case 'zone': h = `<div class="zl" data-ph="Section">${P.esc(it.label)}</div>`; break;
      case 'tape': d.style.setProperty('--tape', it.color || P.TAPES[0]); break;
    }
    if (it.ai) h += '<span class="aib">AI</span>';
    d.innerHTML = h;
    if (it.type === 'video') {
      const v = d.querySelector('video');
      v.addEventListener('loadeddata', () => { if (!v.currentTime) v.currentTime = 0.1; }, { once: true });
    }
    place(d, it);
    return d;
  }
  function place(d, it) {
    d.style.transform = `translate(${it.x}px,${it.y}px)${it.rot ? ` rotate(${it.rot}deg)` : ''}`;
    if (it.type !== 'label') d.style.width = it.w + 'px';
    if (it.type !== 'text' && it.type !== 'label') d.style.height = it.h + 'px';
    d.style.zIndex = it.z;
  }
  const measure = (it, n) => { it.h = n.offsetHeight; if (it.type === 'label') it.w = n.offsetWidth; };
  // Keyed update: unchanged items keep their DOM (so live pages and videos don't reload).
  function render(force) {
    if (editing) stopEdit(true);
    const items = P.itemsOf(ideaId).filter((o) => o.type !== 'arrow');
    const keep = new Set(items.map((o) => o.id));
    world.querySelectorAll('.it').forEach((n) => { if (!keep.has(n.dataset.id)) n.remove(); });
    for (const id of C.sel) { const it = P.item(id); if (!it || it.ideaId !== ideaId) C.sel.delete(id); }
    if (live && !keep.has(live)) live = null;
    for (const it of items) {
      let n = node(it.id);
      const s = sig(it);
      if (!n || force || n._sig !== s) {
        const m = el(it);
        m._sig = s;
        if (n) n.replaceWith(m); else world.insertBefore(m, svgA);
        n = m;
      } else place(n, it);
      if (it.type === 'text' || it.type === 'label') measure(it, n);
    }
    view.querySelector('.empty-hint').hidden = items.length > 0;
    markSel(true);
  }
  function replaceNode(it) {
    const old = node(it.id);
    if (!old) return;
    const n = el(it);
    n._sig = sig(it);
    old.replaceWith(n);
    if (it.type === 'text' || it.type === 'label') measure(it, n);
    markSel(true);
  }
  function markSel(quiet) {
    world.querySelectorAll('.h-se, .h-rot').forEach((n) => n.remove());
    world.querySelectorAll('.it').forEach((n) => n.classList.toggle('sel', C.sel.has(n.dataset.id)));
    const s = sel();
    if (s.length === 1 && s[0].type !== 'arrow' && s[0].type !== 'label') {
      const n = node(s[0].id);
      if (n) {
        n.insertAdjacentHTML('beforeend', '<span class="h-se" title="Resize"></span>');
        if (!NO_ROTATE.has(s[0].type)) n.insertAdjacentHTML('beforeend', '<span class="h-rot" title="Rotate (⇧ snaps)"></span>');
      }
    }
    drawArrows();
    if (quiet) positionBar(); else renderBar();
  }

  // ---------- connectors ----------
  function connGeom(A, B) {
    const ra = rc(A), rb = rc(B), dx = rb.cx - ra.cx, dy = rb.cy - ra.cy;
    const horiz = Math.abs(dx) - (ra.hw + rb.hw) > Math.abs(dy) - (ra.hh + rb.hh);
    const sx = Math.sign(dx) || 1, sy = Math.sign(dy) || 1;
    return {
      horiz,
      p1: horiz ? { x: ra.cx + sx * ra.hw, y: ra.cy } : { x: ra.cx, y: ra.cy + sy * ra.hh },
      p2: horiz ? { x: rb.cx - sx * rb.hw, y: rb.cy } : { x: rb.cx, y: rb.cy - sy * rb.hh },
    };
  }
  function connPath({ p1, p2, horiz }, ends = 'dot') {
    const span = horiz ? p2.x - p1.x : p2.y - p1.y, s = Math.sign(span) || 1, k = Math.max(24, Math.abs(span) * 0.45);
    const c1 = horiz ? { x: p1.x + s * k, y: p1.y } : { x: p1.x, y: p1.y + s * k };
    const c2 = horiz ? { x: p2.x - s * k, y: p2.y } : { x: p2.x, y: p2.y - s * k };
    const line = `M${r1(p1.x)} ${r1(p1.y)}C${r1(c1.x)} ${r1(c1.y)} ${r1(c2.x)} ${r1(c2.y)} ${r1(p2.x)} ${r1(p2.y)}`;
    let marks = `<circle class="cd" cx="${r1(p1.x)}" cy="${r1(p1.y)}" r="4.5"/>`;
    if (ends === 'arrow') {
      const ux = horiz ? s : 0, uy = horiz ? 0 : s;
      marks += `<path class="ch" d="M${r1(p2.x)} ${r1(p2.y)}L${r1(p2.x - ux * 11 - uy * 6)} ${r1(p2.y - uy * 11 + ux * 6)}L${r1(p2.x - ux * 11 + uy * 6)} ${r1(p2.y - uy * 11 - ux * 6)}Z"/>`;
    } else marks += `<circle class="cd" cx="${r1(p2.x)}" cy="${r1(p2.y)}" r="4.5"/>`;
    return { line, marks };
  }
  function drawArrows(tmp) {
    let h = '';
    for (const a of P.itemsOf(ideaId)) {
      if (a.type !== 'arrow') continue;
      const A = P.item(a.from), B = P.item(a.to);
      if (!A || !B) continue;
      const { line, marks } = connPath(connGeom(A, B), a.ends);
      h += `<g class="cn${C.sel.has(a.id) ? ' sel' : ''}"><path class="cl" d="${line}"/>${marks}<path class="hit" data-id="${a.id}" d="${line}"/></g>`;
    }
    if (tmp) h += `<g class="cn tmp"><path class="cl" d="${tmp.line}"/>${tmp.marks}</g>`;
    svgA.innerHTML = h;
  }

  // ---------- pointer ----------
  function onDown(e) {
    const n = e.target.closest('.it');
    if (editing && n && n.dataset.id === editing) return;
    if (live && !(n && n.dataset.id === live)) exitLive();
    if (live && n && n.dataset.id === live) return;
    if (editing) stopEdit();
    cancelGlide();
    cancelAnimationFrame(camAnim);
    if (e.button === 1 || (e.button === 0 && (space || C.tool === 'hand'))) { e.preventDefault(); return startPan(e); }
    if (e.button !== 0) return;
    P.capturePointer(vp, e);
    const p = toWorld(e.clientX, e.clientY);
    switch (C.tool) {
      case 'draw': return P.ui.brush.tool === 'spray' ? startSpray(e) : startStroke(e);
      case 'eraser': return startErase(e);
      case 'note': case 'text': case 'label': return addAt(C.tool, p);
      case 'zone': return startZone(e, p);
      case 'tape': return startTape(e, p);
      case 'cut': return startCut(e);
      case 'arrow': if (n && !n.classList.contains('it-zone')) startConnector(n.dataset.id); return;
    }
    const handle = e.target.closest('.h-se, .h-rot');
    if (handle) { const it = sel()[0]; return handle.classList.contains('h-se') ? startResize(e, it) : startRotate(it); }
    const hit = e.target.closest('.hit');
    if (hit) { C.sel = e.shiftKey ? new Set([...C.sel, hit.dataset.id]) : new Set([hit.dataset.id]); return markSel(); }
    if (n) {
      const id = n.dataset.id;
      if (e.shiftKey) { C.sel.has(id) ? C.sel.delete(id) : C.sel.add(id); markSel(); if (!C.sel.has(id)) return; }
      else if (!C.sel.has(id)) { C.sel = new Set([id]); markSel(); }
      return startDrag(e, p, id);
    }
    if (!e.shiftKey && C.sel.size) { C.sel.clear(); markSel(); }
    startMarquee(e, p);
  }

  function startPan(e) {
    vp.classList.add('panning');
    const c = cam(), x0 = c.x, y0 = c.y;
    track((ev) => { c.x = x0 + ev.clientX - e.clientX; c.y = y0 + ev.clientY - e.clientY; applyCam(); }, () => { if (!space) vp.classList.remove('panning'); P.save(); });
  }

  function startDrag(e, p0, id) {
    const moving = new Map();
    for (const it of sel()) {
      if (it.type === 'arrow') continue;
      moving.set(it.id, it);
      if (it.type === 'zone') for (const o of insideZone(it)) moving.set(o.id, o);
    }
    const start = [...moving.values()].map((it) => [it, it.x, it.y]);
    let moved = false;
    const samples = [];
    track((ev) => {
      if (!moved && Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < 3) return;
      if (!moved) { moved = true; busy = true; bar.hidden = true; P.checkpoint(); }
      const q = toWorld(ev.clientX, ev.clientY), dx = q.x - p0.x, dy = q.y - p0.y;
      for (const [it, x, y] of start) { it.x = x + dx; it.y = y + dy; place(node(it.id), it); }
      drawArrows();
      samples.push({ t: ev.timeStamp, x: q.x, y: q.y });
      while (samples.length > 2 && ev.timeStamp - samples[0].t > 80) samples.shift();
    }, (ev) => {
      if (!moved) {
        if (!e.shiftKey && C.sel.size > 1) { C.sel = new Set([id]); markSel(); }
        return;
      }
      const a = samples[0], b = samples[samples.length - 1];
      if (a && b && b.t > a.t && ev.timeStamp - b.t < 50 && !P.reduced()) {
        const vx = ((b.x - a.x) / (b.t - a.t)) * 16, vy = ((b.y - a.y) / (b.t - a.t)) * 16;
        if (Math.hypot(vx, vy) * cam().z > 6) return glideItems(start.map((s) => s[0]), vx, vy);
      }
      commit();
    });
  }
  // Release velocity carries into a short settle; any new press stops it where it is.
  function glideItems(list, vx, vy) {
    const step = () => {
      vx *= 0.8; vy *= 0.8;
      for (const it of list) { it.x += vx; it.y += vy; const n = node(it.id); if (n) place(n, it); }
      drawArrows();
      if (Math.hypot(vx, vy) * cam().z > 0.3) glide = requestAnimationFrame(step);
      else { glide = 0; commit(); }
    };
    glide = requestAnimationFrame(step);
  }
  function cancelGlide() { if (glide) { cancelAnimationFrame(glide); glide = 0; commit(); } }

  function startResize(e, it) {
    P.checkpoint();
    busy = true; bar.hidden = true;
    const p0 = toWorld(e.clientX, e.clientY), w0 = it.w, h0 = it.h, ar = h0 / w0;
    const a = (-(it.rot || 0) * Math.PI) / 180, n = node(it.id);
    track((ev) => {
      const q = toWorld(ev.clientX, ev.clientY);
      let dx = q.x - p0.x, dy = q.y - p0.y;
      [dx, dy] = [dx * Math.cos(a) - dy * Math.sin(a), dx * Math.sin(a) + dy * Math.cos(a)];
      it.w = Math.max(30, w0 + dx);
      it.h = KEEP_ASPECT.has(it.type) !== ev.shiftKey ? it.w * ar : Math.max(it.type === 'tape' ? 14 : 30, h0 + dy);
      place(n, it);
      if (it.type === 'text') it.h = n.offsetHeight;
      drawArrows();
    }, commit);
  }
  function startRotate(it) {
    P.checkpoint();
    busy = true; bar.hidden = true;
    const c = { x: it.x + it.w / 2, y: it.y + it.h / 2 }, n = node(it.id);
    track((ev) => {
      const q = toWorld(ev.clientX, ev.clientY);
      let deg = (Math.atan2(q.y - c.y, q.x - c.x) * 180) / Math.PI + 90;
      deg = ((deg + 540) % 360) - 180;
      if (ev.shiftKey) deg = Math.round(deg / 15) * 15;
      else if (Math.abs(deg) < 3) deg = 0;
      it.rot = r1(deg);
      place(n, it);
      drawArrows();
    }, commit);
  }

  function startMarquee(e, p0) {
    const m = document.createElement('div');
    m.className = 'marquee';
    vp.appendChild(m);
    const base = new Set(C.sel), r = vp.getBoundingClientRect();
    const items = P.itemsOf(ideaId).filter((o) => o.type !== 'arrow');
    let moved = false;
    track((ev) => {
      moved = true;
      Object.assign(m.style, { left: Math.min(e.clientX, ev.clientX) - r.left + 'px', top: Math.min(e.clientY, ev.clientY) - r.top + 'px', width: Math.abs(ev.clientX - e.clientX) + 'px', height: Math.abs(ev.clientY - e.clientY) + 'px' });
      const q = toWorld(ev.clientX, ev.clientY);
      const x1 = Math.min(p0.x, q.x), x2 = Math.max(p0.x, q.x), y1 = Math.min(p0.y, q.y), y2 = Math.max(p0.y, q.y);
      C.sel = new Set(base);
      for (const o of items) {
        const hit = o.type === 'zone' ? o.x >= x1 && o.y >= y1 && o.x + o.w <= x2 && o.y + o.h <= y2 : o.x < x2 && o.x + o.w > x1 && o.y < y2 && o.y + o.h > y1;
        if (hit) C.sel.add(o.id);
      }
      markSel(true);
      bar.hidden = true;
    }, () => { m.remove(); if (moved) markSel(); });
  }

  // ---------- drawing ----------
  const brushSize = () => P.BRUSHES[P.ui.brush.tool].sizes[P.ui.brush.size];
  function tempSvg(tool) {
    const s = document.createElementNS(NS, 'svg');
    s.setAttribute('class', 'arrows ink-tmp k-' + tool);
    world.appendChild(s);
    return s;
  }
  // Hold still at the end of a stroke to snap it into a clean line, box or ellipse.
  function startStroke(e) {
    const { tool, color } = P.ui.brush, size = brushSize();
    const pts = [toWorld(e.clientX, e.clientY)];
    const tmp = tempSvg(tool);
    const path = document.createElementNS(NS, 'path');
    path.setAttribute('style', `stroke:${color};stroke-width:${size}`);
    tmp.appendChild(path);
    path.setAttribute('d', P.ink.raw(pts));
    let snapped = null, holdT = 0;
    const hold = () => {
      clearTimeout(holdT);
      holdT = setTimeout(() => {
        if (pts.length < 5) return;
        const s = P.ink.shape(pts);
        if (s.shape === 'free') return;
        snapped = s;
        path.setAttribute('d', s.d);
        tmp.classList.add('snapped');
      }, 500);
    };
    hold();
    track((ev) => {
      if (snapped) return;
      const list = ev.getCoalescedEvents ? ev.getCoalescedEvents() : [];
      for (const ce of list.length ? list : [ev]) pts.push(toWorld(ce.clientX, ce.clientY));
      path.setAttribute('d', P.ink.raw(pts));
      hold();
    }, () => {
      clearTimeout(holdT);
      tmp.remove();
      const s = snapped || { shape: 'free', d: P.ink.smooth(pts, tool === 'pencil' ? 0.5 / cam().z : 0.9 / cam().z), b: pbox(pts) };
      P.checkpoint();
      P.newItem({ ideaId, type: 'sketch', tool, color, size, ...P.ink.toItem([s], size / 2 + 4) });
      P.touch(ideaId); P.save();
      render();
    });
  }
  function startSpray(e) {
    const { color } = P.ui.brush, R = brushSize();
    const dots = [], tmp = tempSvg('spray');
    const path = document.createElementNS(NS, 'path');
    path.setAttribute('style', `fill:${color}`);
    tmp.appendChild(path);
    let at = toWorld(e.clientX, e.clientY);
    const emit = () => {
      for (let i = 0; i < Math.ceil(R / 3); i++) {
        const a = Math.random() * Math.PI * 2, d = R * Math.pow(Math.random(), 0.7);
        dots.push([at.x + Math.cos(a) * d, at.y + Math.sin(a) * d, (0.35 + Math.random() * 0.9) * Math.max(0.7, R / 18)]);
      }
      path.setAttribute('d', P.ink.dots(dots));
    };
    emit();
    const tick = setInterval(emit, 45);
    track((ev) => { at = toWorld(ev.clientX, ev.clientY); emit(); }, () => {
      clearInterval(tick);
      tmp.remove();
      const b = pbox(dots.map(([x, y]) => ({ x, y })));
      P.checkpoint();
      P.newItem({ ideaId, type: 'sketch', tool: 'spray', color, size: R, ...P.ink.toItem([{ d: P.ink.dots(dots), b, shape: 'free' }], 4) });
      P.touch(ideaId); P.save();
      render();
    });
  }
  function startErase(e) {
    let erased = false;
    const rub = (ev) => {
      const p = toWorld(ev.clientX, ev.clientY), r = 7 / cam().z;
      const strokes = P.itemsOf(ideaId).filter((o) => o.type === 'sketch' && p.x > o.x - r && p.x < o.x + o.w + r && p.y > o.y - r && p.y < o.y + o.h + r);
      for (const o of strokes) {
        const path = node(o.id)?.querySelector('path');
        if (!path) continue;
        const [vx, vy, vw, vh] = (o.vb || `0 0 ${o.vw} ${o.vh}`).split(' ').map(Number);
        const sx = vw / o.w, sy = vh / o.h;
        const hitAt = ([dx, dy]) => {
          const pt = new DOMPoint(vx + (p.x + dx - o.x) * sx, vy + (p.y + dy - o.y) * sy);
          return o.tool === 'spray' ? path.isPointInFill(pt) : path.isPointInStroke(pt);
        };
        if (![[0, 0], [r, 0], [-r, 0], [0, r], [0, -r]].some(hitAt)) continue;
        if (!erased) { P.checkpoint(); erased = true; }
        P.removeItems([o.id]);
        C.sel.delete(o.id);
        node(o.id)?.remove();
      }
    };
    rub(e);
    track(rub, () => { if (erased) { P.touch(ideaId); P.save(); markSel(); } });
  }

  // ---------- placing things ----------
  function startConnector(fromId) {
    const A = P.item(fromId);
    track((ev) => {
      const q = toWorld(ev.clientX, ev.clientY);
      drawArrows(connPath(connGeom(A, { x: q.x, y: q.y, w: 0, h: 0 }), 'dot'));
    }, (ev) => {
      const t = document.elementFromPoint(ev.clientX, ev.clientY)?.closest('.it');
      const B = t && P.item(t.dataset.id);
      if (B && B.id !== A.id) {
        P.checkpoint();
        const a = P.newItem({ ideaId, type: 'arrow', from: A.id, to: B.id, ends: 'dot', x: 0, y: 0, w: 0, h: 0 });
        P.touch(ideaId); P.save();
        C.sel = new Set([a.id]);
      }
      setTool('select');
      markSel();
    });
  }
  function startZone(e, p0) {
    const m = document.createElement('div');
    m.className = 'marquee';
    vp.appendChild(m);
    const r = vp.getBoundingClientRect();
    let q = p0;
    track((ev) => {
      q = toWorld(ev.clientX, ev.clientY);
      Object.assign(m.style, { left: Math.min(e.clientX, ev.clientX) - r.left + 'px', top: Math.min(e.clientY, ev.clientY) - r.top + 'px', width: Math.abs(ev.clientX - e.clientX) + 'px', height: Math.abs(ev.clientY - e.clientY) + 'px' });
    }, () => {
      m.remove();
      let x = Math.min(p0.x, q.x), y = Math.min(p0.y, q.y), w = Math.abs(q.x - p0.x), h = Math.abs(q.y - p0.y);
      if (w < 40 || h < 40) { w = 480; h = 320; x = p0.x - 20; y = p0.y - 20; }
      P.checkpoint();
      const z = P.newItem({ ideaId, type: 'zone', label: '', x, y, w, h });
      setTool('select');
      render();
      C.sel = new Set([z.id]); markSel();
      startEdit(z.id);
    });
  }
  // Drag to lay a strip of tape along the gesture; a click drops a short piece.
  function startTape(e, p0) {
    const color = P.ui.tapeColor || P.TAPES[0];
    const prev = document.createElement('div');
    prev.className = 'it it-tape';
    prev.style.setProperty('--tape', color);
    world.appendChild(prev);
    const geo = (q) => {
      let len = dist(p0, q), ang = (Math.atan2(q.y - p0.y, q.x - p0.x) * 180) / Math.PI;
      if (len < 16) { len = 130; ang = -6; q = { x: p0.x + 130 * Math.cos(-0.1), y: p0.y + 130 * Math.sin(-0.1) }; }
      const mx = (p0.x + q.x) / 2, my = (p0.y + q.y) / 2;
      return { x: mx - len / 2, y: my - 15, w: len, h: 30, rot: r1(ang), z: 999999 };
    };
    let g = geo(p0);
    place(prev, g);
    track((ev) => { g = geo(toWorld(ev.clientX, ev.clientY)); place(prev, g); }, () => {
      prev.remove();
      P.checkpoint();
      const t = P.newItem({ ideaId, type: 'tape', color, ...g, z: undefined });
      t.z = ++P.state.zc;
      P.touch(ideaId); P.save();
      render();
    });
  }
  function addAt(type, p, props = {}) {
    P.checkpoint();
    const base = {
      note: { w: 200, h: 200, text: '', color: P.ui.noteColor },
      text: { w: 320, h: 40, text: '' },
      label: { w: 80, h: 28, text: '' },
      swatch: { w: 96, h: 116, color: '#e0392b' },
      type: { w: 240, h: 130, text: 'Aa Headline', face: 'serif' },
    }[type];
    const it = P.newItem({ ideaId, type, ...base, ...props });
    it.x = p.x - (type === 'text' || type === 'label' ? 6 : it.w / 2);
    it.y = p.y - (type === 'text' ? 20 : type === 'label' ? 14 : it.h / 2);
    P.touch(ideaId);
    setTool('select');
    render();
    C.sel = new Set([it.id]); markSel();
    if (EDITABLE[type] && type !== 'type') startEdit(it.id);
    P.save();
    return it;
  }
  async function addUrl(url) {
    const u = P.asUrl(url);
    if (!u) return P.toast('That doesn\'t look like a link');
    const v = P.videoEmbed(u), c = center();
    const props = v ? { type: 'embed', provider: v.provider, src: v.src, url: u, title: v.provider + ' video', w: 480, h: 300 }
      : /\.(png|jpe?g|gif|webp|avif|svg)(\?|$)/i.test(u) ? await P.fromUrl(u)
      : { type: 'web', url: u, title: P.domain(u), w: 560, h: 400 };
    P.saveMany([props], ideaId, c);
  }

  // ---------- cut-outs ----------
  function startCutMode(id) {
    cutId = id;
    setTool('cut');
    view.querySelector('.cut-hint').hidden = false;
  }
  function endCutMode() {
    cutId = null;
    view.querySelector('.cut-hint').hidden = true;
    setTool('select');
  }
  // Lasso around the part of the image to keep; the item shrinks to the cut and its shadow follows the shape.
  function startCut(e) {
    const it = P.item(cutId);
    if (!it) return endCutMode();
    const pts = [toWorld(e.clientX, e.clientY)];
    const tmp = tempSvg('lasso');
    const path = document.createElementNS(NS, 'path');
    tmp.appendChild(path);
    track((ev) => { pts.push(toWorld(ev.clientX, ev.clientY)); path.setAttribute('d', P.ink.raw(pts) + 'Z'); }, () => {
      tmp.remove();
      if (pts.length < 6) return;
      const cx = it.x + it.w / 2, cy = it.y + it.h / 2, a = (-(it.rot || 0) * Math.PI) / 180;
      const local = rdp(pts, 1.5 / cam().z).map((p) => {
        const dx = p.x - cx, dy = p.y - cy;
        return { x: P.clamp((dx * Math.cos(a) - dy * Math.sin(a) + it.w / 2) / it.w, 0, 1), y: P.clamp((dx * Math.sin(a) + dy * Math.cos(a) + it.h / 2) / it.h, 0, 1) };
      });
      const b = pbox(local), bw = b.x2 - b.x1, bh = b.y2 - b.y1;
      if (bw < 0.03 || bh < 0.03) return;
      P.checkpoint();
      it.uncut ||= { x: it.x, y: it.y, w: it.w, h: it.h, crop: it.crop || null };
      const c0 = it.crop || { x: 0, y: 0, w: 1, h: 1 };
      it.crop = { x: c0.x + b.x1 * c0.w, y: c0.y + b.y1 * c0.h, w: bw * c0.w, h: bh * c0.h };
      it.clip = local.map((p) => [+((p.x - b.x1) / bw).toFixed(4), +((p.y - b.y1) / bh).toFixed(4)]);
      const ox = ((b.x1 + b.x2) / 2 - 0.5) * it.w, oy = ((b.y1 + b.y2) / 2 - 0.5) * it.h, ra = -a;
      const ncx = cx + ox * Math.cos(ra) - oy * Math.sin(ra), ncy = cy + ox * Math.sin(ra) + oy * Math.cos(ra);
      it.w *= bw; it.h *= bh; it.x = ncx - it.w / 2; it.y = ncy - it.h / 2;
      P.touch(ideaId); P.save();
      endCutMode();
      replaceNode(it);
      renderBar();
    });
  }
  function uncut(it) {
    if (!it.uncut) return;
    P.checkpoint();
    Object.assign(it, { x: it.uncut.x, y: it.uncut.y, w: it.uncut.w, h: it.uncut.h, crop: it.uncut.crop || undefined });
    delete it.clip; delete it.uncut;
    if (!it.crop) delete it.crop;
    P.save(); replaceNode(it); renderBar();
  }

  // ---------- live pages and video ----------
  function enterLive(id) {
    if (live) exitLive();
    live = id;
    const n = node(id);
    if (!n) return;
    n.classList.add('live');
    const v = n.querySelector('video');
    if (v) { v.controls = true; v.play().catch(() => {}); }
    renderBar();
  }
  function exitLive() {
    const n = live && node(live);
    live = null;
    if (!n) return;
    n.classList.remove('live');
    const v = n.querySelector('video');
    if (v) { v.controls = false; v.pause(); }
    renderBar();
  }

  // ---------- inline editing ----------
  function startEdit(id) {
    const it = P.item(id), n = node(id);
    if (!it || !n || !EDITABLE[it.type]) return;
    const b = n.querySelector(EDITABLE[it.type]);
    if (!b) return;
    editing = id;
    n.classList.add('editing');
    b.contentEditable = 'plaintext-only';
    if (b.contentEditable !== 'plaintext-only') b.contentEditable = 'true';
    b.focus();
    const r = document.createRange();
    r.selectNodeContents(b);
    const s = getSelection();
    s.removeAllRanges(); s.addRange(r);
    bar.hidden = true;
    b.addEventListener('blur', () => stopEdit(), { once: true });
    b.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape' || (ev.key === 'Enter' && (ev.metaKey || ev.ctrlKey || it.type === 'label' || it.type === 'zone'))) { ev.preventDefault(); b.blur(); }
      ev.stopPropagation();
    });
    b.addEventListener('input', () => { if (it.type === 'text' || it.type === 'label') { measure(it, n); drawArrows(); } });
  }
  function stopEdit(silent) {
    const id = editing;
    if (!id) return;
    editing = null;
    const it = P.item(id), n = node(id);
    if (!it || !n) return;
    const b = n.querySelector(EDITABLE[it.type]);
    const val = b.innerText.replace(/\n+$/, '');
    b.removeAttribute('contenteditable');
    n.classList.remove('editing');
    getSelection().removeAllRanges();
    const key = it.type === 'zone' ? 'label' : 'text';
    if (!val.trim() && ['note', 'text', 'label'].includes(it.type)) {
      P.removeItems([id]);
      C.sel.delete(id);
      if (!silent) render();
    } else {
      if (val !== (it[key] || '')) {
        P.checkpoint();
        it[key] = it.type === 'zone' && !val.trim() ? 'Section' : val;
        if (b.textContent !== it[key]) b.textContent = it[key];
        n._sig = sig(it);
        P.touch(ideaId);
      }
      if (!silent) renderBar();
    }
    P.save();
  }

  // ---------- commands ----------
  function setTool(t) {
    if (C.tool === 'cut' && t !== 'cut') { cutId = null; view.querySelector('.cut-hint').hidden = true; }
    C.tool = t;
    if (!vp) return;
    vp.dataset.tool = t;
    view.querySelectorAll('.rail [data-tool]').forEach((b) => b.classList.toggle('on', b.dataset.tool === t));
    wheel.hidden = t !== 'draw';
    if (t === 'draw') drawWheel();
    if (t !== 'select' && t !== 'hand' && C.sel.size) { C.sel.clear(); markSel(); }
  }
  function del() {
    const ids = [...C.sel];
    if (!ids.length) return;
    P.checkpoint();
    P.removeItems(ids);
    C.sel.clear();
    P.touch(ideaId); P.save();
    render(); renderBar();
  }
  function duplicate() {
    const list = sel().filter((i) => i.type !== 'arrow');
    if (!list.length) return;
    P.checkpoint();
    const map = {};
    for (const it of list) {
      const { id, z, unsorted, ...rest } = it;
      const c = P.newItem({ ...JSON.parse(JSON.stringify(rest)), x: it.x + 24, y: it.y + 24, created: Date.now(), ai: false });
      map[id] = c.id;
    }
    for (const a of P.itemsOf(ideaId).filter((o) => o.type === 'arrow' && map[o.from] && map[o.to])) {
      P.newItem({ ideaId, type: 'arrow', from: map[a.from], to: map[a.to], ends: a.ends, x: 0, y: 0, w: 0, h: 0 });
    }
    C.sel = new Set(Object.values(map));
    P.touch(ideaId); P.save();
    render(); renderBar();
  }
  function order(front) {
    const list = sel().filter((i) => i.type !== 'zone' && i.type !== 'arrow');
    if (!list.length) return;
    P.checkpoint();
    for (const it of list) it.z = front ? ++P.state.zc : 1;
    P.save(); render();
  }
  function groupZone() {
    const list = sel().filter((i) => i.type !== 'arrow' && i.type !== 'zone');
    if (!list.length) return;
    P.checkpoint();
    const b = P.bbox(list), pad = 32;
    const z = P.newItem({ ideaId, type: 'zone', label: '', x: b.x1 - pad, y: b.y1 - pad, w: b.w + pad * 2, h: b.h + pad * 2 + 20 });
    C.sel = new Set([z.id]);
    render();
    startEdit(z.id);
  }
  function tidy(list, zone) {
    P.checkpoint();
    if (!zone) {
      const b = P.bbox(list);
      zone = { x: b.x1 - 32, y: b.y1 - 32, w: 0, h: 0 };
    }
    P.layoutZone(zone, list.sort((a, b) => a.y - b.y || a.x - b.x));
    P.save(); render();
  }
  async function copyItems(list) {
    try {
      if (list.length === 1 && list[0].type === 'image') {
        const im = new Image();
        im.src = P.srcOf(list[0]);
        await im.decode();
        const c = document.createElement('canvas');
        c.width = im.naturalWidth; c.height = im.naturalHeight;
        c.getContext('2d').drawImage(im, 0, 0);
        const png = await new Promise((res) => c.toBlob(res, 'image/png'));
        await navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]);
        P.toast('Image copied. Paste it into Figma, Notion or a doc.');
        return;
      }
      await navigator.clipboard.writeText(P.asText(list));
      P.toast('Copied as text');
    } catch {
      P.toast('The browser blocked clipboard access');
    }
  }
  P.downloadText = (name, text) => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
    a.download = name.replace(/[^\w\- ]+/g, '').trim() + '.txt';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  };

  // ---------- selection bar ----------
  const opt = (v, label, cur) => `<option value="${P.esc(v)}"${v === (cur || '') ? ' selected' : ''}>${P.esc(label)}</option>`;
  const ib = (act, icon, title) => `<button class="ib" data-b="${act}" title="${title}" aria-label="${title}">${P.icon(icon)}</button>`;
  const tb = (act, label, title = '') => `<button class="tb" data-b="${act}"${title ? ` title="${title}"` : ''}>${label}</button>`;
  const SEP = '<i class="sep"></i>';
  const dotsHtml = (list, cur, key) => `<span class="cdots">${list.map((c) => `<button class="cdot${c.toLowerCase() === (cur || '').toLowerCase() ? ' on' : ''}" data-set="${key}" data-v="${c}" style="background:${c}" aria-label="Colour ${c}"></button>`).join('')}</span>`;
  const fontSel = (it) => `<select data-in="font" aria-label="Lettering">${opt('', `${P.FONTS[idea.font] || 'Caveat'} · board`, it.font)}${Object.entries(P.FONTS).filter(([k]) => k !== idea.font).map(([k, v]) => opt(k, v, it.font)).join('')}${Object.entries(P.TEXT_FACES).map(([k, [n]]) => opt(k, n, it.font)).join('')}</select>`;
  const whyIn = (it) => `<input class="why-in" data-in="why" value="${P.esc(it.why)}" placeholder="Why I saved it" style="font-family:${P.esc(P.fontOf(idea.font))}">`;
  function barHtml(s) {
    const trash = ib('del', 'trash', 'Delete (⌫)');
    if (s.length > 1) return tb('group', 'Section', 'Wrap in a section') + tb('tidy', 'Tidy', 'Line them up') + SEP + ib('copy', 'copy', 'Copy as text') + trash;
    const it = s[0], url = it.src || it.url;
    const open = url && /^https?:/.test(url) ? `<a class="ib" href="${P.esc(url)}" target="_blank" rel="noopener" title="Open source">${P.icon('out')}</a>` : '';
    switch (it.type) {
      case 'note': return dotsHtml(P.NOTE_COLORS, it.color, 'color') + SEP + fontSel(it) + SEP + trash;
      case 'text': return dotsHtml(P.INKS, it.color || P.INKS[0], 'color') + SEP + fontSel(it) + SEP + trash;
      case 'label': return tb('invert', it.light ? 'Black' : 'White', 'Swap colours') + SEP + trash;
      case 'image': return whyIn(it) + SEP + (it.clip ? tb('uncut', 'Undo cut') : ib('cut', 'scissors', 'Cut out')) + open + ib('copy', 'copy', 'Copy image') + trash;
      case 'video': case 'embed': case 'web': return whyIn(it) + SEP + tb('live', live === it.id ? 'Done' : it.type === 'web' ? 'Use page' : 'Play') + open + trash;
      case 'link': return whyIn(it) + SEP + tb('makeweb', 'Show live page') + open + trash;
      case 'sketch': return dotsHtml(P.INKS, it.color || P.INKS[0], 'color') + SEP + trash;
      case 'swatch': return `<input type="color" data-in="color" value="${P.esc(it.color)}" aria-label="Colour"><span class="hex">${P.esc(it.color)}</span>` + SEP + trash;
      case 'type': return `<input data-in="text" value="${P.esc(it.text)}" aria-label="Sample text"><select data-in="face" aria-label="Typeface">${Object.entries(P.FACES).map(([k, v]) => opt(k, v[0], it.face)).join('')}</select>` + SEP + trash;
      case 'zone': return `<input data-in="label" value="${P.esc(it.label)}" aria-label="Section name">` + tb('tidyzone', 'Tidy') + SEP + trash;
      case 'arrow': return tb('ends', it.ends === 'arrow' ? 'Dot → Arrow' : 'Dot → Dot', 'Change the end') + ib('reverse', 'reverse', 'Reverse') + SEP + trash;
      case 'tape': return dotsHtml(P.TAPES, it.color, 'color') + SEP + trash;
    }
    return trash;
  }
  function renderBar() {
    if (!bar) return;
    const s = sel();
    if (!s.length || busy || editing || C.tool === 'cut') { bar.hidden = true; return; }
    bar.innerHTML = barHtml(s);
    bar.hidden = false;
    positionBar();
  }
  function positionBar() {
    if (!bar || bar.hidden) return;
    const s = sel();
    if (!s.length) return;
    const geo = s.filter((o) => o.type !== 'arrow');
    let b;
    if (geo.length) b = P.bbox(geo.map((o) => (o.type === 'zone' ? { x: o.x, y: o.y - 34, w: o.w, h: o.h + 34 } : o)));
    else {
      const A = P.item(s[0].from), B = P.item(s[0].to);
      if (!A || !B) return;
      const g = connGeom(A, B);
      b = { x1: Math.min(g.p1.x, g.p2.x), y1: Math.min(g.p1.y, g.p2.y), x2: Math.max(g.p1.x, g.p2.x), y2: Math.max(g.p1.y, g.p2.y) };
    }
    const c = cam(), W = vp.clientWidth, H = vp.clientHeight, bw = bar.offsetWidth, bh = bar.offsetHeight;
    const lift = geo.length === 1 && !NO_ROTATE.has(geo[0].type) ? 46 : 14;
    let y = b.y1 * c.z + c.y - bh - lift;
    if (y < 64) y = b.y2 * c.z + c.y + 18;
    y = P.clamp(y, 64, H - bh - 12);
    const x = P.clamp(((b.x1 + b.x2) / 2) * c.z + c.x - bw / 2, 76, W - bw - 12);
    bar.style.transform = `translate(${Math.round(x)}px,${Math.round(y)}px)`;
  }
  function bindBar() {
    bar.addEventListener('pointerdown', (e) => e.stopPropagation());
    bar.addEventListener('focusin', (e) => { if (e.target.matches('input, select')) P.checkpoint(); });
    bar.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === 'Escape') e.target.blur(); });
    bar.addEventListener('click', (e) => {
      const s = sel(), it = s[0];
      const set = e.target.closest('[data-set]');
      if (set) {
        P.checkpoint();
        for (const o of s) o[set.dataset.set] = set.dataset.v;
        if (it.type === 'note') P.ui.noteColor = set.dataset.v;
        if (it.type === 'tape') P.ui.tapeColor = set.dataset.v;
        s.forEach(replaceNode);
        P.touch(ideaId); P.save(); renderBar();
        return;
      }
      const act = e.target.closest('[data-b]')?.dataset.b;
      if (!act) return;
      if (act === 'del') return del();
      if (act === 'copy') return copyItems(s);
      if (act === 'group') return groupZone();
      if (act === 'tidy') return tidy(s.filter((o) => o.type !== 'arrow' && o.type !== 'zone'));
      if (act === 'tidyzone') return tidy(insideZone(it), it);
      if (act === 'cut') return startCutMode(it.id);
      if (act === 'uncut') return uncut(it);
      if (act === 'live') return live === it.id ? exitLive() : enterLive(it.id);
      P.checkpoint();
      if (act === 'invert') it.light = !it.light;
      if (act === 'ends') it.ends = it.ends === 'arrow' ? 'dot' : 'arrow';
      if (act === 'reverse') [it.from, it.to] = [it.to, it.from];
      if (act === 'makeweb') { it.type = 'web'; it.url = it.src; it.w = 560; it.h = 400; P.autoTag(it); }
      P.save();
      if (it.type === 'arrow') drawArrows(); else replaceNode(it);
      renderBar();
    });
    const onIn = (e) => {
      const k = e.target.dataset.in;
      if (!k) return;
      const it = sel()[0];
      if (!it) return;
      const v = e.target.value;
      if (k === 'font') it.font = v || undefined; else it[k] = v;
      if (k === 'why') {
        const n = node(it.id);
        let w = n.querySelector('.why');
        if (!w && v) { n.insertAdjacentHTML('beforeend', `<div class="why" style="font-family:${P.esc(P.fontOf(idea.font))}"></div>`); w = n.querySelector('.why'); }
        if (w) { w.textContent = v; if (!v) w.remove(); }
        n._sig = sig(it);
      } else replaceNode(it);
      if (k === 'color' && it.type === 'swatch') bar.querySelector('.hex').textContent = v;
      P.touch(ideaId); P.save();
      positionBar();
    };
    bar.addEventListener('input', onIn);
    bar.addEventListener('change', (e) => { if (e.target.tagName === 'SELECT') onIn(e); });
  }

  // ---------- brush wheel ----------
  const GLYPH = {
    pen: '<path d="M4 13c3-6 6 2 12-6" style="stroke-width:1.6"/>',
    marker: '<path d="M4 13c3-6 6 2 12-6" style="stroke-width:4"/>',
    pencil: '<path d="M4 13c3-6 6 2 12-6" style="stroke-width:1.4" filter="url(#pencil)"/>',
    hl: '<path d="M4 11h12" style="stroke-width:6;stroke-linecap:butt;opacity:.5"/>',
    spray: '<path d="M7 9h.01M10 7h.01M12 11h.01M9 12h.01M13 8h.01M6 12h.01M11 9h.01" style="stroke-width:1.8"/>',
  };
  function arc(i, n, R, r) {
    const a0 = ((-90 + (i * 360) / n + 2.5) * Math.PI) / 180, a1 = ((-90 + ((i + 1) * 360) / n - 2.5) * Math.PI) / 180;
    const pt = (rad, a) => `${r1(84 + rad * Math.cos(a))} ${r1(84 + rad * Math.sin(a))}`;
    return `M${pt(R, a0)}A${R} ${R} 0 0 1 ${pt(R, a1)}L${pt(r, a1)}A${r} ${r} 0 0 0 ${pt(r, a0)}Z`;
  }
  function drawWheel() {
    const b = P.ui.brush, keys = Object.keys(P.BRUSHES);
    const dotPx = [6, 11, 18][b.size];
    wheel.innerHTML = `<svg viewBox="0 0 168 168" class="ring">${P.INKS.map((c, i) => `<path d="${arc(i, P.INKS.length, 82, 64)}" fill="${c}" data-ink="${c}" class="${c === b.color ? 'on' : ''}"><title>Colour ${c}</title></path>`).join('')}</svg>
      ${keys.map((k, i) => {
        const a = ((-90 + (i * 360) / keys.length) * Math.PI) / 180;
        return `<button class="wb${k === b.tool ? ' on' : ''}" data-brush="${k}" style="left:${r1(84 + 44 * Math.cos(a) - 15)}px;top:${r1(84 + 44 * Math.sin(a) - 15)}px" title="${P.BRUSHES[k].name}" aria-label="${P.BRUSHES[k].name}"><svg viewBox="0 0 20 20" style="color:${b.color}">${GLYPH[k]}</svg></button>`;
      }).join('')}
      <button class="wsize" data-size title="Size (1, 2, 3)" aria-label="Brush size"><i style="width:${dotPx}px;height:${dotPx}px;background:${b.color}"></i></button>`;
    const db = view.querySelector('.rail [data-tool="draw"] i');
    if (db) db.style.background = b.color;
  }
  function bindWheel() {
    wheel.addEventListener('pointerdown', (e) => e.stopPropagation());
    wheel.addEventListener('click', (e) => {
      const ink = e.target.closest('[data-ink]'), br = e.target.closest('[data-brush]');
      if (ink) P.ui.brush.color = ink.dataset.ink;
      else if (br) P.ui.brush.tool = br.dataset.brush;
      else if (e.target.closest('[data-size]')) P.ui.brush.size = (P.ui.brush.size + 1) % 3;
      else return;
      drawWheel();
    });
  }

  // ---------- board menu ----------
  const TEMPLATE_NAMES = { moodboard: 'Moodboard', stylescape: 'Stylescape', script: 'Script beats', business: 'Business canvas' };
  function boardMenu(anchor) {
    const pop = P.popover(anchor, `<div class="bm">
      <label class="fld"><span>Name</span><input type="text" data-k="name" value="${P.esc(idea.name)}"></label>
      <div class="row2"><label class="fld"><span>Kind</span><select data-k="kind">${P.KINDS.map((k) => opt(k, k, idea.kind)).join('')}</select></label>
      <label class="fld"><span>Handwriting</span><select data-k="font">${Object.entries(P.FONTS).map(([k, v]) => opt(k, v, idea.font)).join('')}</select></label></div>
      <div class="fld"><span>Stage</span><div class="seg" data-seg="stage">${P.STAGES.map((s) => `<button data-v="${s}" class="${s === idea.stage ? 'on' : ''}">${s}</button>`).join('')}</div></div>
      <label class="fld"><span>Next step</span><input type="text" data-k="next" value="${P.esc(idea.next)}" placeholder="One small thing to do next"></label>
      <div class="fld"><span>Paper</span><div class="seg" data-seg="surface">${Object.entries(P.SURFACES).map(([v, l]) => `<button data-v="${v}" class="${v === idea.surface ? 'on' : ''}">${l}</button>`).join('')}</div></div>
      <label class="fld"><span>Add a layout</span><select data-act="template"><option value="">Choose…</option>${Object.entries(TEMPLATE_NAMES).map(([k, v]) => opt(k, v, '')).join('')}</select></label>
      <div class="bm-acts"><button class="mi" data-act="copynotes">Copy all notes as text</button><button class="mi" data-act="download">Download as .txt</button><button class="mi danger" data-act="delidea">Delete idea…</button></div>
    </div>`, { cls: 'wide' });
    pop.addEventListener('focusin', (e) => { if (e.target.matches('input, select')) P.checkpoint(); });
    pop.addEventListener('input', (e) => {
      const k = e.target.dataset.k;
      if (!k) return;
      idea[k] = e.target.value;
      P.save();
      if (k === 'font') render(true);
      chrome();
    });
    pop.addEventListener('change', (e) => {
      if (e.target.dataset.act !== 'template' || !e.target.value) return;
      P.checkpoint();
      const items = P.itemsOf(ideaId).filter((o) => o.type !== 'arrow');
      const o = items.length ? { x: P.bbox(items).x2 + 140, y: P.bbox(items).y1 } : { x: 0, y: 0 };
      P.applyTemplate(ideaId, e.target.value, o);
      P.save(); render(); fit(true);
      P.closePopover();
    });
    pop.addEventListener('click', (e) => {
      const b = e.target.closest('[data-seg] button');
      if (b) {
        P.checkpoint();
        idea[b.parentElement.dataset.seg] = b.dataset.v;
        b.parentElement.querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b));
        P.save(); surface(); chrome();
        return;
      }
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'copynotes') navigator.clipboard.writeText(P.ideaText(ideaId)).then(() => P.toast('Notes copied as text'), () => P.toast('The browser blocked clipboard access'));
      if (act === 'download') P.downloadText(idea.name, P.ideaText(ideaId));
      if (act === 'delidea') { P.closePopover(); P.deleteIdea(ideaId); }
    });
  }
  function mediaMenu(anchor) {
    const pop = P.popover(anchor, `<div class="mm">
      <button class="mi" data-m="file">${P.icon('media')} Image or video from this Mac…</button>
      <form class="mm-url"><input name="u" placeholder="Paste a website, YouTube or Vimeo link" autocomplete="off"><button class="btn primary">Add</button></form>
      <p class="meta">Websites show as live pages; double-click one to use it. A few sites refuse to be shown inside other apps, so open those in your browser.</p>
      <button class="mi" data-m="swatch">${P.icon('drop')} Colour swatch</button>
      <button class="mi" data-m="type"><b class="aa">Aa</b> Type sample</button>
    </div>`, { side: 'right' });
    pop.querySelector('input')?.focus();
    pop.addEventListener('submit', (e) => { e.preventDefault(); const u = e.target.u.value; P.closePopover(); addUrl(u); });
    pop.addEventListener('click', (e) => {
      const m = e.target.closest('[data-m]')?.dataset.m;
      if (!m) return;
      P.closePopover();
      if (m === 'file') view.querySelector('#addfile').click();
      if (m === 'swatch') addAt('swatch', center(), { color: P.INKS[2 + Math.floor(Math.random() * 6)] });
      if (m === 'type') addAt('type', center());
    });
  }

  // ---------- keyboard ----------
  const KEYS = { v: 'select', h: 'hand', p: 'draw', b: 'draw', e: 'eraser', t: 'text', s: 'note', n: 'note', l: 'label', x: 'arrow', f: 'zone', g: 'tape' };
  function key(e) {
    const k = e.key, mod = e.metaKey || e.ctrlKey;
    if (k === ' ' && !mod) { if (!space) { space = true; vp.classList.add('panning'); } return true; }
    if (mod) {
      const lk = k.toLowerCase();
      if (lk === 'd') { duplicate(); return true; }
      if (lk === 'a') { C.sel = new Set(P.itemsOf(ideaId).filter((o) => o.type !== 'arrow').map((o) => o.id)); markSel(); return true; }
      if (k === '0') { fit(true); return true; }
      if (k === '=' || k === '+') { zoomStep(1.25); return true; }
      if (k === '-') { zoomStep(0.8); return true; }
      if (lk === 'c' && C.sel.size) { copyItems(sel()); return true; }
      return false;
    }
    if (k === 'Escape') {
      if (live) exitLive();
      else if (C.tool !== 'select') setTool('select');
      else if (C.sel.size) { C.sel.clear(); markSel(); }
      else return false;
      return true;
    }
    if (k === 'Backspace' || k === 'Delete') { del(); return true; }
    if (k === 'Enter') { const s = sel(); if (s.length === 1 && EDITABLE[s[0].type]) { startEdit(s[0].id); return true; } }
    if (k === ']' || k === '[') { order(k === ']'); return true; }
    if (C.tool === 'draw' && /^[123]$/.test(k)) { P.ui.brush.size = +k - 1; drawWheel(); return true; }
    if (k.startsWith('Arrow') && C.sel.size) {
      const step = e.shiftKey ? 10 : 1;
      const dx = k === 'ArrowLeft' ? -step : k === 'ArrowRight' ? step : 0, dy = k === 'ArrowUp' ? -step : k === 'ArrowDown' ? step : 0;
      P.checkpoint();
      for (const it of sel()) { if (it.type === 'arrow') continue; it.x += dx; it.y += dy; place(node(it.id), it); }
      drawArrows(); positionBar(); P.save();
      return true;
    }
    if (k.toLowerCase() === 'i' && !e.altKey) { mediaMenu(view.querySelector('.rail [data-tool="media"]')); return true; }
    const t = KEYS[k.toLowerCase()];
    if (t && !e.altKey) { setTool(e.shiftKey && k.toLowerCase() === 's' ? 'zone' : t); return true; }
    return false;
  }

  // ---------- chrome ----------
  function surface() {
    vp.className = `vp surface-${idea.surface || 'dot'}${space ? ' panning' : ''}`;
    vp.dataset.tool = C.tool;
  }
  function chrome() {
    if (!view || !idea) return;
    const b = view.querySelector('.name-pill');
    b.querySelector('.nm').textContent = idea.name;
    b.querySelector('.stage-dot').className = `stage-dot s-${idea.stage.toLowerCase()}`;
    b.title = `${idea.stage}${idea.next ? ' · Next: ' + idea.next : ''}`;
  }
  const RAIL = [
    ['select', 'cursor', 'Select', 'V'], ['hand', 'hand', 'Hand', 'H'], 0,
    ['draw', 'pen', 'Draw', 'P'], ['eraser', 'eraser', 'Eraser', 'E'], 0,
    ['text', 'text', 'Write', 'T'], ['note', 'note', 'Sticky note', 'S'], ['label', 'label', 'Label', 'L'], 0,
    ['arrow', 'connector', 'Connector', 'X'], ['zone', 'section', 'Section', 'F'], ['tape', 'tape', 'Tape', 'G'], 0,
    ['media', 'media', 'Image, video or website', 'I'],
  ];

  P.views.idea = {
    mount(v, id, opts = {}) {
      view = v; ideaId = id; idea = P.idea(id);
      C.sel = new Set(); C.tool = 'select'; editing = null; live = null; space = false; busy = false; cutId = null;
      ac = new AbortController();
      const sig$ = { signal: ac.signal };
      view.className = 'v-idea';
      view.innerHTML = `<div class="vp"><div class="world"><svg class="arrows" width="1" height="1"></svg></div></div>
        <p class="empty-hint" hidden>Double-click anywhere to write. Draw with P. Paste or drop images, links and videos.</p>
        ${P.topBar({ board: true })}
        <nav class="rail" aria-label="Tools">${RAIL.map((t) => !t ? '<i class="gap"></i>' : `<button class="rb${t[0] === 'select' ? ' on' : ''}" data-tool="${t[0]}" title="${t[2]} (${t[3]})" aria-label="${t[2]}">${P.icon(t[1])}${t[0] === 'draw' ? `<i style="background:${P.ui.brush.color}"></i>` : ''}</button>`).join('')}</nav>
        <div class="wheel" hidden></div>
        <div class="zoom pill"><button data-z="out" title="Zoom out (⌘−)" aria-label="Zoom out">−</button><button data-z="fit" title="Fit everything (⌘0)"></button><button data-z="in" title="Zoom in (⌘+)" aria-label="Zoom in">+</button></div>
        <div class="selbar" hidden></div>
        <div class="cut-hint pill" hidden>Draw around the part to keep · Esc cancels</div>
        <input type="file" id="addfile" accept="image/*,video/*" multiple hidden>`;
      vp = view.querySelector('.vp'); world = view.querySelector('.world'); svgA = view.querySelector('.arrows');
      zl = view.querySelector('[data-z="fit"]'); bar = view.querySelector('.selbar'); wheel = view.querySelector('.wheel');
      surface(); chrome(); bindBar(); bindWheel();

      vp.addEventListener('pointerdown', onDown, sig$);
      vp.addEventListener('wheel', (e) => {
        e.preventDefault();
        cancelAnimationFrame(camAnim);
        const r = vp.getBoundingClientRect();
        if (e.ctrlKey || e.metaKey) zoomAt(e.clientX - r.left, e.clientY - r.top, Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.002)));
        else { cam().x -= e.deltaX; cam().y -= e.deltaY; applyCam(); }
        P.save();
      }, { passive: false, signal: ac.signal });
      vp.addEventListener('dblclick', (e) => {
        if (C.tool !== 'select') return;
        const n = e.target.closest('.it');
        if (n) {
          const it = P.item(n.dataset.id);
          if (EDITABLE[it.type]) startEdit(it.id);
          else if (FRAMES.has(it.type)) enterLive(it.id);
          else if (it.type === 'link' && it.src) window.open(it.src, '_blank', 'noopener');
        } else if (!e.target.closest('.hit')) addAt('text', toWorld(e.clientX, e.clientY));
      }, sig$);
      vp.addEventListener('dragover', (e) => { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; }, sig$);
      vp.addEventListener('drop', (e) => { e.preventDefault(); e.stopPropagation(); P.ingestDrop(e.dataTransfer, ideaId, toWorld(e.clientX, e.clientY)); }, sig$);
      window.addEventListener('keyup', (e) => { if (e.key === ' ') { space = false; vp && vp.classList.remove('panning'); } }, sig$);
      window.addEventListener('resize', () => vp && applyCam(), sig$);
      view.querySelector('.rail').addEventListener('click', (e) => {
        const b = e.target.closest('[data-tool]');
        if (!b) return;
        if (b.dataset.tool === 'media') return mediaMenu(b);
        if (b.dataset.tool === 'draw' && C.tool === 'draw') { wheel.hidden = !wheel.hidden; return; }
        setTool(b.dataset.tool);
      }, sig$);
      view.querySelector('.name-pill').addEventListener('click', (e) => boardMenu(e.currentTarget), sig$);
      view.querySelector('.zoom').addEventListener('click', (e) => {
        const z = e.target.closest('[data-z]')?.dataset.z;
        if (z === 'in') zoomStep(1.25);
        if (z === 'out') zoomStep(0.8);
        if (z === 'fit') fit(true);
      }, sig$);
      view.querySelector('#addfile').addEventListener('change', (e) => { P.ingestFiles([...e.target.files], ideaId, center()); e.target.value = ''; }, sig$);

      render();
      if (!idea.cam) { idea.cam = { x: 0, y: 0, z: 1 }; fit(false); } else applyCam();
      if (opts.focus) requestAnimationFrame(() => focus(opts.focus));
    },
    unmount() {
      if (editing) stopEdit(true);
      cancelGlide();
      cancelAnimationFrame(camAnim);
      ac && ac.abort();
      vp = world = bar = wheel = view = null;
    },
    render() {
      if (!vp) return;
      idea = P.idea(ideaId);
      if (!idea) return;
      surface(); chrome(); render(); applyCam();
    },
    chrome: () => chrome(),
    key, focus,
    center: () => (vp ? center() : null),
    id: () => ideaId,
  };
})();
