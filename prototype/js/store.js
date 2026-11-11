// Data model, local persistence (IndexedDB), undo, and shared helpers.
(() => {
  const P = (window.P = { views: {}, ui: {} });

  P.KINDS = ['App', 'Film', 'Script', 'Business', 'Other'];
  P.STAGES = ['Spark', 'Exploring', 'Doing', 'Parked'];
  // Handwriting faces for what you write. Interface text always uses the system font.
  P.FONTS = { caveat: 'Caveat', kalam: 'Kalam', reenie: 'Reenie Beanie', shadows: 'Shadows Into Light', marker: 'Permanent Marker' };
  P.TEXT_FACES = { type: ['Typewriter', '"Special Elite", "American Typewriter", "Courier New", monospace'], sys: ['Plain', '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif'] };
  P.SURFACES = { dot: 'Dots', mat: 'Grid', paper: 'Plain' };
  P.NOTE_COLORS = ['#FBEA7E', '#FFC98B', '#FFB8E2', '#BDF0C6', '#C5CBFF', '#E2CCFF', '#E9E4DA', '#FFFFFF'];
  P.INKS = ['#1d1b18', '#8a857b', '#e0392b', '#f28c28', '#ffd23f', '#2f9e5b', '#3b4cca', '#f25fc4'];
  P.TAPES = ['#f3d9a4', '#bfe3d0', '#f7c4d9', '#c9d2ff', '#e8e2d4'];
  P.BRUSHES = {
    pen: { name: 'Pen', sizes: [1.6, 3, 6] },
    marker: { name: 'Marker', sizes: [6, 10, 16] },
    pencil: { name: 'Pencil', sizes: [1.2, 2.2, 3.6] },
    hl: { name: 'Highlighter', sizes: [14, 22, 32] },
    spray: { name: 'Spray', sizes: [12, 22, 36] },
  };
  P.ui.brush = { tool: 'pen', color: P.INKS[0], size: 1 };
  P.ui.noteColor = P.NOTE_COLORS[0];
  P.DAY = 864e5;

  P.state = { ideas: [], items: [], lastIdea: null, zc: 10 };
  P.blobs = {};
  let blobsDirty = false;

  // ---------- small helpers ----------
  P.uid = () => Math.random().toString(36).slice(2, 10);
  P.$ = (q, el = document) => el.querySelector(q);
  P.esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  P.clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  P.fontOf = (key) => {
    if (P.TEXT_FACES[key]) return P.TEXT_FACES[key][1];
    return `"${P.FONTS[key] || P.FONTS.caveat}", "Bradley Hand", cursive`;
  };
  P.fontName = (key) => (P.TEXT_FACES[key] ? P.TEXT_FACES[key][0] : P.FONTS[key] || P.FONTS.caveat);
  P.idea = (id) => P.state.ideas.find((i) => i.id === id);
  P.item = (id) => P.state.items.find((i) => i.id === id);
  P.itemsOf = (ideaId) => P.state.items.filter((i) => (i.ideaId || null) === (ideaId || null));
  P.touch = (ideaId) => { const i = P.idea(ideaId); if (i) i.touched = Date.now(); };
  P.isTyping = (t) => !!t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
  P.reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  P.capturePointer = (el, e) => { try { el.setPointerCapture(e.pointerId); } catch { /* pointer already released */ } };
  P.logo = (cls = '') => `<img class="logo ${cls}" src="assets/logo.png" onerror="this.onerror=null;this.src='assets/logo.svg'" alt="Skull Salad">`;

  P.ago = (ts) => {
    const d = Math.floor((Date.now() - ts) / P.DAY);
    if (d < 1) return 'today';
    if (d < 2) return 'yesterday';
    if (d < 14) return d + ' days ago';
    if (d < 60) return Math.floor(d / 7) + ' weeks ago';
    return Math.floor(d / 30) + ' months ago';
  };
  P.day = (ts) => new Date(ts).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
  P.asUrl = (s) => {
    s = (s || '').trim().split('\n')[0];
    if (/^https?:\/\/\S+$/i.test(s)) return s;
    if (/^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(s)) return 'https://' + s;
    return '';
  };
  P.domain = (u) => { try { return new URL(u).hostname.replace(/^www\./, ''); } catch { return ''; } };
  // YouTube and Vimeo links become playable embeds.
  P.videoEmbed = (u) => {
    try {
      const x = new URL(u), h = x.hostname.replace(/^(www|m)\./, '');
      let id = '';
      if (h === 'youtu.be') id = x.pathname.slice(1);
      else if (h.endsWith('youtube.com')) id = x.searchParams.get('v') || (x.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]+)/) || [])[1];
      if (id) return { provider: 'YouTube', src: `https://www.youtube-nocookie.com/embed/${id}?rel=0` };
      const v = h.endsWith('vimeo.com') && (x.pathname.match(/\/(\d+)/) || [])[1];
      if (v) return { provider: 'Vimeo', src: `https://player.vimeo.com/video/${v}` };
    } catch {}
    return null;
  };

  const ICONS = {
    home: 'M2.5 7.5 8 3l5.5 4.5V13a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5z',
    search: 'M7 12A5 5 0 1 0 7 2a5 5 0 0 0 0 10zM11 11l3 3',
    plus: 'M8 3v10M3 8h10',
    chev: 'M5 6.5l3 3 3-3',
    back: 'M10 3 5 8l5 5',
    x: 'M4 4l8 8M12 4l-8 8',
    check: 'M3.5 8.5l3 3 6-7',
    spark: 'M8 2l1.3 3.7L13 7 9.3 8.3 8 12 6.7 8.3 3 7l3.7-1.3zM12.5 11v2.5M11.25 12.25h2.5',
    cursor: 'M4 2.5l8 5-3.6.9L7 12z',
    hand: 'M5.5 8.5V4a1 1 0 0 1 2 0v3.5M7.5 7V3a1 1 0 0 1 2 0v4M9.5 7V4a1 1 0 0 1 2 0v5a4.5 4.5 0 0 1-4.5 4.5c-1.7 0-2.7-.9-3.5-2.1L2.2 9.3a1 1 0 0 1 1.6-1.2l1.7 1.9',
    pen: 'M3 13l.6-2.8L10.8 3 13 5.2l-7.2 7.2zM9.5 4.3l2.2 2.2',
    eraser: 'M6.5 13.5h7M2.8 9.7l6-6a1.5 1.5 0 0 1 2.1 0l2.4 2.4a1.5 1.5 0 0 1 0 2.1L8 13.5H5.6L2.8 10.8a.8.8 0 0 1 0-1.1zM5.5 7l4 4',
    text: 'M3.5 4.5V3h9v1.5M8 3v10M6.5 13h3',
    note: 'M3 3h10v6.5L9.5 13H3zM9.5 13V9.5H13',
    label: 'M2.5 5.5h9l2 2.5-2 2.5h-9zM5 8h.01',
    connector: 'M3.5 12.5C7 12.5 9 3.5 12.5 3.5M3.5 12.5h.01M12.5 3.5h.01',
    section: 'M2.5 5.5h11v8h-11zM2.5 3h4',
    media: 'M2.5 3.5h11v9h-11zM2.5 10.5l3-3 3 3 2-2 3 3M10.5 6.5h.01',
    tape: 'M3 6.2 11.6 3l1.4 3.8L4.4 10zM5.5 5.3l1.4 3.8M8.6 4.1 10 7.9',
    scissors: 'M5 6.2a1.7 1.7 0 1 0 0-.01zM5 12.2a1.7 1.7 0 1 0 0-.01M6.4 5.3 13 11M6.4 11.1 13 5.4',
    out: 'M9 3h4v4M13 3 7.5 8.5M11.5 9.5v3.5h-9v-9H6',
    copy: 'M5.5 5.5h7v7h-7zM3.5 10.5v-7h7',
    trash: 'M3 4.5h10M6 4.5V3h4v1.5M4.5 4.5l.5 8.5h6l.5-8.5',
    globe: 'M8 13.5A5.5 5.5 0 1 0 8 2.5a5.5 5.5 0 0 0 0 11zM2.5 8h11M8 2.5c1.6 1.5 2.3 3.4 2.3 5.5S9.6 12 8 13.5C6.4 12 5.7 10.1 5.7 8S6.4 4 8 2.5z',
    play: 'M5 3.5v9l7.5-4.5z',
    tray: 'M2.5 9.5 4 3.5h8l1.5 6v3h-11zM2.5 9.5h3.2l.8 1.5h3l.8-1.5h3.2',
    grid: 'M3 3h4v4H3zM9 3h4v4H9zM3 9h4v4H3zM9 9h4v4H9z',
    mic: 'M8 2.5a2 2 0 0 0-2 2v3a2 2 0 0 0 4 0v-3a2 2 0 0 0-2-2zM4 7.5a4 4 0 0 0 8 0M8 11.5v2',
    grab: 'M2.5 5.5v-2a1 1 0 0 1 1-1h2M10.5 2.5h2a1 1 0 0 1 1 1v2M13.5 10.5v2a1 1 0 0 1-1 1h-2M5.5 13.5h-2a1 1 0 0 1-1-1v-2',
    drop: 'M8 2.5s4 4.2 4 7a4 4 0 0 1-8 0c0-2.8 4-7 4-7z',
    stack: 'M8 2.5 2.5 5.5 8 8.5l5.5-3zM2.5 8.5 8 11.5l5.5-3M2.5 11 8 14l5.5-3',
    reverse: 'M3 5.5h9.5M10 3l2.5 2.5L10 8M13 10.5H3.5M6 8l-2.5 2.5L6 13',
    tidy: 'M2.5 2.5h4.5v4.5H2.5zM9 2.5h4.5v4.5H9zM2.5 9h4.5v4.5H2.5zM9 9h4.5v4.5H9z',
  };
  P.icon = (n) => `<svg class="ic" viewBox="0 0 16 16" aria-hidden="true"><path d="${ICONS[n] || ''}"/></svg>`;

  // ---------- colour ----------
  P.HUES = [['red', '#e5484d'], ['orange', '#f08c3a'], ['yellow', '#f2cf45'], ['green', '#4caf6d'], ['blue', '#3b82f6'], ['purple', '#8b5cf6'], ['pink', '#e86aa6'], ['dark', '#1b1b1d'], ['light', '#f1f1ee'], ['grey', '#8a8a8e']];
  P.hue = (hex) => {
    if (!/^#[0-9a-f]{6}$/i.test(hex || '')) return null;
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
    const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
    if (l < 0.16) return 'dark';
    if (l > 0.9) return 'light';
    if (s < 0.16) return 'grey';
    let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
    return h < 15 ? 'red' : h < 45 ? 'orange' : h < 70 ? 'yellow' : h < 170 ? 'green' : h < 255 ? 'blue' : h < 300 ? 'purple' : h < 345 ? 'pink' : 'red';
  };
  // Dominant colour, ignoring transparent pixels so cut-outs report the colour of the subject.
  const dominant = (canvas) => {
    const c = document.createElement('canvas'); c.width = c.height = 16;
    const g = c.getContext('2d'); g.drawImage(canvas, 0, 0, 16, 16);
    const d = g.getImageData(0, 0, 16, 16).data;
    let R = 0, G = 0, B = 0, W = 0;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] < 40) continue;
      const mx = Math.max(d[i], d[i + 1], d[i + 2]), mn = Math.min(d[i], d[i + 1], d[i + 2]);
      const w = (mx - mn) / 255 + 0.08;
      R += d[i] * w; G += d[i + 1] * w; B += d[i + 2] * w; W += w;
    }
    if (!W) return '#888888';
    return '#' + [R, G, B].map((v) => Math.round(v / W).toString(16).padStart(2, '0')).join('');
  };

  // ---------- images ----------
  // Downscales into a data URL kept in P.blobs; returns { blob, iw, ih, color, alpha }.
  P.ingestImage = (src) => new Promise((res, rej) => {
    const isFile = typeof src !== 'string';
    const url = isFile ? URL.createObjectURL(src) : src;
    const im = new Image();
    if (!isFile && /^https?:/.test(src)) im.crossOrigin = 'anonymous';
    im.onload = () => {
      const k = Math.min(1, 1400 / Math.max(im.width, im.height));
      const w = Math.max(1, Math.round(im.width * k)), h = Math.max(1, Math.round(im.height * k));
      const c = document.createElement('canvas'); c.width = w; c.height = h;
      const g = c.getContext('2d');
      g.drawImage(im, 0, 0, w, h);
      if (isFile) URL.revokeObjectURL(url);
      try {
        const corner = g.getImageData(0, 0, 1, 1).data[3];
        const png = (isFile && src.type === 'image/png') || /svg/.test(isFile ? src.type : src.slice(0, 30)) || corner < 250;
        const id = P.uid();
        P.blobs[id] = c.toDataURL(png ? 'image/png' : 'image/jpeg', 0.88);
        blobsDirty = true;
        res({ blob: id, iw: w, ih: h, color: dominant(c), alpha: corner < 250 });
      } catch (e) { rej(e); }
    };
    im.onerror = () => rej(new Error('image load failed'));
    im.src = url;
  });
  P.keepBlob = (file) => { const id = P.uid(); P.blobs[id] = file; blobsDirty = true; return id; };
  const urls = {};
  P.srcOf = (it) => {
    if (!it.blob) return it.url || '';
    const b = P.blobs[it.blob];
    if (!b) return '';
    return typeof b === 'string' ? b : (urls[it.blob] ||= URL.createObjectURL(b));
  };

  // ---------- layout ----------
  P.bbox = (items) => {
    let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
    for (const i of items) { x1 = Math.min(x1, i.x); y1 = Math.min(y1, i.y); x2 = Math.max(x2, i.x + i.w); y2 = Math.max(y2, i.y + i.h); }
    return { x1, y1, x2, y2, w: x2 - x1, h: y2 - y1 };
  };
  // Shelf-packs members into a section and grows it to fit.
  P.layoutZone = (zone, mem) => {
    const pad = 32, gap = 24, maxW = 760;
    let cx = pad, cy = pad, rowH = 0, used = 0;
    for (const m of mem) {
      if (cx > pad && cx + m.w > maxW) { cx = pad; cy += rowH + gap; rowH = 0; }
      m.x = zone.x + cx; m.y = zone.y + cy;
      cx += m.w + gap; used = Math.max(used, cx - gap);
      rowH = Math.max(rowH, m.h + (m.why ? 26 : 0));
    }
    zone.w = Math.max(420, used + pad); zone.h = Math.max(220, cy + rowH + pad);
  };
  const overlaps = (a, list, gap) => list.some((o) => a.x < o.x + o.w + gap && a.x + a.w + gap > o.x && a.y < o.y + o.h + gap && a.y + a.h + gap > o.y);
  const footprint = (o) => ({ x: o.x, y: o.y, w: o.w, h: o.h + (o.why ? 26 : 0) });
  // New captures land in the idea's "Unsorted" section: first free spot inside it, growing it downward.
  // The section is created in the middle of the last view if that space is empty, else beside existing content.
  P.autoPlace = (it) => {
    const all = P.itemsOf(it.ideaId).filter((o) => o !== it && o.type !== 'arrow');
    const solid = all.filter((o) => o.type !== 'zone').map(footprint);
    let zone = all.find((o) => o.type === 'zone' && o.unsorted);
    if (!zone) {
      const W = 600, H = 280, c = P.idea(it.ideaId)?.cam;
      let spot = null;
      if (c && c.vw) {
        const cand = { x: (c.vw / 2 - c.x) / c.z - W / 2, y: (c.vh / 2 - c.y) / c.z - H / 2, w: W, h: H };
        if (!overlaps(cand, all, 40)) spot = cand;
      }
      if (!spot) spot = all.length ? { x: P.bbox(all).x2 + 120, y: P.bbox(all).y1 } : { x: 0, y: 0 };
      zone = P.newItem({ ideaId: it.ideaId, type: 'zone', label: 'Unsorted', unsorted: true, x: spot.x, y: spot.y, w: W, h: H });
    }
    const pad = 32, gap = 24, f = footprint(it);
    const inner = Math.max(zone.w - pad * 2, it.w);
    const others = solid.filter((o) => o.x < zone.x + zone.w && o.x + o.w > zone.x && o.y + o.h > zone.y);
    for (let y = zone.y + pad; y < zone.y + 6000; y += 16) {
      for (let x = zone.x + pad; x + it.w <= zone.x + pad + inner; x += 16) {
        if (overlaps({ x, y, w: it.w, h: f.h }, others, gap)) continue;
        it.x = x; it.y = y;
        zone.w = Math.max(zone.w, x + it.w + pad - zone.x);
        zone.h = Math.max(zone.h, y + f.h + pad - zone.y);
        return;
      }
    }
  };
  P.removeItems = (ids) => {
    const gone = new Set(ids);
    P.state.items = P.state.items.filter((o) => !gone.has(o.id) && !(o.type === 'arrow' && (gone.has(o.from) || gone.has(o.to))));
  };

  // ---------- items ----------
  P.autoTag = (it) => {
    const t = new Set(it.tags || []);
    t.add(it.type);
    const src = it.src || it.url;
    if (src && /^https?:/.test(src)) { const d = P.domain(src); if (d) t.add(d); }
    if (it.ai) t.add('ai');
    it.tags = [...t];
  };
  P.newItem = (props) => {
    const it = { id: P.uid(), created: Date.now(), rot: 0, tags: [], ...props };
    it.z = it.type === 'zone' ? 0 : ++P.state.zc;
    P.autoTag(it);
    P.state.items.push(it);
    return it;
  };
  // Central entry for every capture route. `at` = world point for direct drops; otherwise auto-placed.
  P.addCapture = (props, ideaId, at) => {
    P.checkpoint();
    const it = P.newItem({ ...props, ideaId: ideaId || null });
    if (ideaId) {
      if (at) { it.x = at.x - it.w / 2; it.y = at.y - it.h / 2; } else P.autoPlace(it);
      P.touch(ideaId);
      P.state.lastIdea = ideaId;
    }
    P.save(); P.refresh();
    return it;
  };
  P.fileItem = (itemId, ideaId) => {
    const it = P.item(itemId); if (!it || !P.idea(ideaId)) return;
    P.checkpoint();
    it.ideaId = ideaId; P.autoPlace(it); P.touch(ideaId);
    P.save(); P.refresh();
    P.toast(`Moved to ${P.idea(ideaId).name}`);
  };

  // ---------- persistence ----------
  let dbp = null;
  const idb = () => (dbp ||= new Promise((res, rej) => {
    const r = indexedDB.open('skull-salad', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('kv');
    r.onsuccess = () => { r.result.onversionchange = () => r.result.close(); res(r.result); };
    r.onerror = () => { dbp = null; rej(r.error); };
  }));
  const get = async (k) => { const db = await idb(); return new Promise((res, rej) => { const q = db.transaction('kv').objectStore('kv').get(k); q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error); }); };
  const put = async (k, v) => { const db = await idb(); return new Promise((res, rej) => { const tx = db.transaction('kv', 'readwrite'); tx.objectStore('kv').put(v, k); tx.oncomplete = res; tx.onerror = () => rej(tx.error); }); };
  P.load = async () => {
    try {
      const s = await get('state');
      if (s && s.ideas) { P.state = s; P.blobs = (await get('blobs')) || {}; return true; }
    } catch (e) { console.warn('Skull Salad: could not read local data', e); }
    return false;
  };
  let timer;
  P.flush = async () => {
    clearTimeout(timer);
    try { await put('state', P.state); if (blobsDirty) { blobsDirty = false; await put('blobs', P.blobs); } }
    catch (e) { console.warn('Skull Salad: could not save', e); }
  };
  P.save = () => { clearTimeout(timer); timer = setTimeout(P.flush, 250); };
  P.reset = async () => { await put('state', null); await put('blobs', null); location.reload(); };

  // ---------- undo ----------
  const undo = [], redo = [];
  const snap = () => JSON.stringify({ ideas: P.state.ideas, items: P.state.items });
  // Camera positions are view state, not content: keep the current ones across undo/redo.
  const restore = (s) => {
    const o = JSON.parse(s), cams = Object.fromEntries(P.state.ideas.map((i) => [i.id, i.cam]));
    for (const i of o.ideas) if (cams[i.id]) i.cam = cams[i.id];
    P.state.ideas = o.ideas; P.state.items = o.items;
    P.save(); P.refresh();
  };
  P.checkpoint = () => { undo.push(snap()); if (undo.length > 80) undo.shift(); redo.length = 0; };
  P.undo = () => { if (undo.length) { redo.push(snap()); restore(undo.pop()); } };
  P.redo = () => { if (redo.length) { undo.push(snap()); restore(redo.pop()); } };
})();
