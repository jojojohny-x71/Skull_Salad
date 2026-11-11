// Capture: the quick-capture panel (type, grab, sketch, speak), the idea picker, paste and drag-drop,
// and turning any dropped or pasted data into items.
(() => {
  const P = window.P;
  const layer = () => P.$('#layer');
  P.sim = P.sim || {};

  // ---------- data → item props ----------
  const IMG_EXT = /\.(png|jpe?g|gif|webp|avif|svg)(\?|#|$)/i;
  const prettyTitle = (u) => {
    try {
      const x = new URL(u);
      const seg = decodeURIComponent(x.pathname.split('/').filter(Boolean).pop() || '').replace(/\.[a-z0-9]+$/i, '').replace(/[-_+]+/g, ' ').trim();
      return seg ? seg[0].toUpperCase() + seg.slice(1) : x.hostname.replace(/^www\./, '');
    } catch { return u; }
  };
  // Stickies stay square unless the text needs more room.
  P.noteSize = (text, sys, w) => {
    w = w || (text.length > 140 ? 240 : 200);
    const cpl = sys ? (w - 36) / 7.4 : (w - 36) / 10, lh = sys ? 19.6 : 26;
    const lines = text.split('\n').reduce((n, p) => n + Math.max(1, Math.ceil(p.length / cpl)), 0);
    return { w, h: P.clamp(Math.round(40 + lines * lh), w, 680) };
  };
  P.fromFile = async (f) => {
    if (f.type.startsWith('image/')) {
      const info = await P.ingestImage(f);
      return { type: 'image', ...info, w: 240, h: Math.round((240 * info.ih) / info.iw), title: f.name };
    }
    if (f.type.startsWith('video/')) {
      const [vw, vh] = await new Promise((res) => {
        const v = document.createElement('video');
        v.preload = 'metadata';
        v.onloadedmetadata = () => res([v.videoWidth || 16, v.videoHeight || 9]);
        v.onerror = () => res([16, 9]);
        v.src = URL.createObjectURL(f);
      });
      return { type: 'video', blob: P.keepBlob(f), w: 320, h: Math.round((320 * vh) / vw), title: f.name };
    }
    return { type: 'link', title: f.name, blob: P.keepBlob(f), src: '', w: 230, h: 68 };
  };
  P.fromUrl = async (url, asImage) => {
    if (asImage || IMG_EXT.test(url) || url.startsWith('data:image')) {
      try {
        const info = await P.ingestImage(url);
        return { type: 'image', ...info, w: 240, h: Math.round((240 * info.ih) / info.iw), src: url.startsWith('data:') ? '' : url };
      } catch {
        return { type: 'image', url, w: 240, h: 180, src: url };
      }
    }
    const v = P.videoEmbed(url);
    if (v) return { type: 'embed', provider: v.provider, src: v.src, url, title: `${v.provider} video`, w: 480, h: 300 };
    return { type: 'link', title: prettyTitle(url), src: url, w: 240, h: 72 };
  };
  P.fromText = async (t) => {
    const u = P.asUrl(t);
    if (u && !t.trim().includes(' ')) return P.fromUrl(u);
    if (t.length > 420) return { type: 'text', text: t, w: 360, h: 40 };
    return { type: 'note', text: t, color: P.NOTE_COLORS[0], ...P.noteSize(t) };
  };
  // Reads everything synchronously first: a DataTransfer is emptied once the event handler returns.
  P.readTransfer = async (dt) => {
    if (!dt) return [];
    const files = [...(dt.files || [])];
    const html = dt.getData('text/html'), uri = dt.getData('text/uri-list'), txt = dt.getData('text/plain');
    const out = [];
    if (files.length) {
      for (const f of files) { try { out.push(await P.fromFile(f)); } catch (e) { console.warn('Pile: could not read', f.name, e); } }
      return out;
    }
    const img = html && (html.match(/<img[^>]+src=["']([^"']+)["']/i) || [])[1];
    const link = uri && uri.split(/\r?\n/).find((l) => l && !l.startsWith('#'));
    if (img) { const p = await P.fromUrl(img, true); if (link && link !== img) p.src = link; out.push(p); }
    else if (link) out.push(await P.fromUrl(link));
    else if (txt && txt.trim()) out.push(await P.fromText(txt.trim()));
    return out;
  };

  // Saves a batch of captures, then confirms with a toast (or flies to it when that idea is open).
  P.saveMany = (list, ideaId, at, o = {}) => {
    const items = list.map((props, i) => P.addCapture(props, ideaId, at && { x: at.x + i * 30, y: at.y + i * 30 }));
    if (!items.length || o.quiet) return items;
    const last = items[items.length - 1], name = ideaId ? P.idea(ideaId).name : 'the Pile';
    const n = items.length > 1 ? `${items.length} things` : 'Saved';
    if (ideaId && P.route.view === 'idea' && P.route.id === ideaId) {
      if (!at) P.views.idea.focus(last.id);
      P.toast(`${n === 'Saved' ? 'Saved' : n + ' saved'} to ${name}`);
    } else {
      P.toast(`${n === 'Saved' ? 'Saved' : n + ' saved'} to ${name}`, { label: 'Show', run: () => (ideaId ? P.go('idea', ideaId, { focus: last.id }) : P.go('pile')) });
    }
    return items;
  };
  P.ingestDrop = async (dt, ideaId, at) => {
    const pileId = dt.getData('text/x-pile-item');
    if (pileId) { if (ideaId) P.fileItem(pileId, ideaId); return; }
    const list = await P.readTransfer(dt);
    if (list.length) P.saveMany(list, ideaId || null, at);
  };
  P.ingestFiles = async (files, ideaId, at) => {
    const list = [];
    for (const f of files) { try { list.push(await P.fromFile(f)); } catch (e) { console.warn(e); } }
    if (list.length) P.saveMany(list, ideaId, at);
  };

  // ---------- quick-capture panel ----------
  const MODES = [['type', 'text', 'Write'], ['grab', 'grab', 'Grab'], ['sketch', 'pen', 'Sketch'], ['speak', 'mic', 'Speak']];
  const OFFLINE_NOTE = 'Offline copy (simulated): the Mac app stores the readable text of this page here, so it survives the original being deleted.';
  let panel = null, st = null, closeTimer = 0, rec = null;

  const orderedIdeas = () => {
    const ideas = P.ideasByRecent();
    const first = [P.route.view === 'idea' ? P.route.id : null, P.state.lastIdea].filter(Boolean);
    return [...first.map(P.idea).filter(Boolean), ...ideas.filter((i) => !first.includes(i.id))].filter((v, i, a) => a.indexOf(v) === i);
  };
  const defaultIdea = () => (P.route.view === 'idea' ? P.route.id : P.idea(P.state.lastIdea) ? P.state.lastIdea : null);

  function open(o = {}) {
    if (panel && closeTimer) { clearTimeout(closeTimer); closeTimer = 0; panel.remove(); panel = null; }
    if (panel) {
      if (o.mode) setMode(o.mode);
      if (o.grabbed) setGrab(o.grabbed);
      if (o.ideaId !== undefined) { st.ideaId = o.ideaId; renderChips(); }
      return;
    }
    const d = P.ui.draft || {};
    st = { mode: o.mode || 'type', ideaId: o.ideaId !== undefined ? o.ideaId : defaultIdea(), text: d.text || '', raw: d.raw || '', why: '', grabbed: o.grabbed || null, strokes: [], tag: null, newName: null };
    if (o.grabbed) st.mode = 'grab';
    P.ui.draft = null;
    panel = document.createElement('div');
    panel.className = 'cap';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Quick capture');
    panel.innerHTML = `<div class="cap-modes" role="tablist">${MODES.map(([m, ic, l], i) => `<button role="tab" data-mode="${m}" title="${l} (⌃${i + 1})">${P.icon(ic)}${l}</button>`).join('')}
        <span class="cap-x"><button class="ib" data-closecap aria-label="Close" title="Close (Esc)">${P.icon('x')}</button></span></div>
      <div class="cap-body"></div>
      <div class="cap-foot"><span class="cap-to">To</span><div class="chips"></div><select class="more" aria-label="Other ideas"></select><button class="btn primary" data-save>Save <kbd>↩</kbd></button></div>`;
    layer().appendChild(panel);
    const t = o.trigger && o.trigger.getBoundingClientRect(), pr = panel.getBoundingClientRect();
    panel.style.transformOrigin = t ? `${t.left + t.width / 2 - pr.left}px ${t.top + t.height / 2 - pr.top}px` : '50% 0';
    bindPanel();
    renderBody(); renderChips();
    requestAnimationFrame(() => panel && panel.classList.add('open'));
    if (d.text || d.raw) hint('Restored your unsaved draft.');
  }
  // Leaves the way it came (shrinks back toward its trigger). Reopening mid-exit replaces it immediately.
  function close(saved) {
    if (!panel || closeTimer) return;
    stopSpeech();
    if (!saved && (st.text.trim() || st.raw.trim())) P.ui.draft = { text: st.text, raw: st.raw };
    const p = panel;
    p.classList.remove('open');
    if (p.contains(document.activeElement)) document.activeElement.blur();
    closeTimer = setTimeout(() => { p.remove(); panel = null; closeTimer = 0; }, P.reduced() ? 0 : 260);
  }
  const isOpen = () => !!panel && !closeTimer;
  P.capture = { open, close: () => close(false), isOpen, toggle: (o) => (isOpen() ? close(false) : open(o)) };

  function setMode(m) {
    if (st.mode === 'speak' && m !== 'speak') stopSpeech();
    st.mode = m;
    renderBody();
  }
  function setGrab(list) {
    st.grabbed = [...(st.grabbed || []), ...list];
    st.mode = 'grab';
    renderBody();
  }
  function hint(msg) { const h = panel && panel.querySelector('.cap-hint'); if (h) h.textContent = msg || ''; }
  function shake() { panel.classList.remove('shake'); void panel.offsetWidth; panel.classList.add('shake'); }

  function renderChips() {
    const ideas = orderedIdeas();
    let top = ideas.slice(0, 5);
    if (st.ideaId && !top.some((i) => i.id === st.ideaId) && P.idea(st.ideaId)) top = [...top.slice(0, 4), P.idea(st.ideaId)];
    st.top = top.map((i) => i.id);
    panel.querySelector('.chips').innerHTML = `<button class="chip${!st.ideaId && !st.newName ? ' on' : ''}" data-to="">Pile <kbd>⌥0</kbd></button>`
      + top.map((i, n) => `<button class="chip${st.ideaId === i.id && !st.newName ? ' on' : ''}" data-to="${i.id}">${P.esc(i.name)} <kbd>⌥${n + 1}</kbd></button>`).join('')
      + (st.newName ? `<button class="chip on" data-to="new">New: ${P.esc(st.newName)}</button>` : '');
    const more = panel.querySelector('.more');
    more.hidden = ideas.length <= 5;
    more.innerHTML = '<option value="">More…</option>' + ideas.slice(5).map((i) => `<option value="${i.id}">${P.esc(i.name)}</option>`).join('');
  }

  function renderBody() {
    panel.querySelectorAll('[data-mode]').forEach((b) => { b.classList.toggle('on', b.dataset.mode === st.mode); b.setAttribute('aria-selected', b.dataset.mode === st.mode); });
    const body = panel.querySelector('.cap-body');
    const hand = P.esc(P.fontOf(P.idea(st.ideaId)?.font));
    if (st.mode === 'type') {
      body.innerHTML = `<textarea id="cap-text" placeholder="Dump it here. Add #gym to file it straight into an idea." style="font-family:${hand}">${P.esc(st.text)}</textarea>
        <input class="why-in" id="cap-why" placeholder="Why I saved it (optional)" style="font-family:${hand}" hidden>
        <div class="cap-hint"></div>`;
      const ta = body.querySelector('#cap-text');
      ta.focus();
      ta.setSelectionRange(ta.value.length, ta.value.length);
      onType();
    } else if (st.mode === 'grab') {
      const g = st.grabbed || [];
      const f = g[0];
      const prev = !f ? 'Paste (⌘V) or drop an image, video, file or link here'
        : f.type === 'image' ? `<img src="${P.esc(f.blob ? P.blobs[f.blob] : f.url)}" alt="">`
        : f.type === 'video' ? `Video · ${P.esc(f.title)}`
        : f.type === 'link' ? `${P.esc(f.title)}<br><small>${P.esc(P.domain(f.src) || 'file')}</small>`
        : P.esc((f.text || '').slice(0, 140));
      body.innerHTML = `<div class="dz" id="cap-dz">${prev}${g.length > 1 ? `<small style="position:absolute;bottom:8px">+ ${g.length - 1} more</small>` : ''}</div>
        <div class="cap-row"><input class="in" id="cap-url" placeholder="…or paste a link" autocomplete="off"><button class="btn" data-shot>${P.icon('grab')} Screenshot</button><button class="btn" data-file>Choose file</button>${g.length ? '<button class="btn" data-ungrab>Clear</button>' : ''}</div>
        <input class="why-in" id="cap-why" placeholder="Why I saved it (optional)" value="${P.esc(st.why)}" style="font-family:${hand}">
        <label class="cap-chk"><input type="checkbox" id="cap-off" checked> Keep an offline copy <small>(files are stored on this Mac; page text is simulated)</small></label>
        <input type="file" id="cap-file" hidden multiple>
        <div class="cap-hint"></div>`;
      (g.length ? body.querySelector('#cap-why') : body.querySelector('#cap-url')).focus();
    } else if (st.mode === 'sketch') {
      body.innerHTML = `<svg class="pad" id="cap-pad" aria-label="Sketch pad">${st.strokes.map((s) => `<path d="${s.d}"/>`).join('')}</svg>
        <div class="cap-row"><small>Rough is fine: circles, boxes and lines snap clean.</small><span style="flex:1"></span><button class="btn" data-clear>Clear</button></div>
        <input class="why-in" id="cap-why" placeholder="Caption (optional)" value="${P.esc(st.why)}" style="font-family:${hand}">
        <div class="cap-hint"></div>`;
      bindPad(body.querySelector('#cap-pad'));
    } else {
      const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
      body.innerHTML = `<div class="speak"><button class="mic" data-mic aria-label="Start listening" title="Start or stop listening">${P.icon('mic')}</button>
          <div style="flex:1;min-width:0"><small id="cap-status">${SR ? 'Click the mic and ramble. Pile keeps a tidied note and throws the audio away.' : "This browser has no speech recognition. Type or paste a ramble to see the tidy-up."}</small>
          <textarea id="cap-raw" placeholder="Raw transcript appears here. You can also type or paste a ramble.">${P.esc(st.raw)}</textarea></div></div>
        <div class="tidy" id="cap-tidy" style="font-family:${hand}"></div>
        <div class="cap-row"><small>Preview uses the browser's speech recognition; the Mac app does this on-device.</small><span style="flex:1"></span><button class="btn" data-sample>Try a sample ramble</button></div>
        <div class="cap-hint"></div>`;
      showTidy();
    }
  }

  // #tag picks an idea while you type; an unknown #tag becomes a new idea on save.
  function onType() {
    const ta = panel.querySelector('#cap-text');
    if (!ta) return;
    st.text = ta.value;
    const tags = [...st.text.matchAll(/(^|\s)#([\p{L}\p{N}][\p{L}\p{N}-]*)/gu)];
    const m = tags[tags.length - 1];
    st.tag = null; st.newName = null;
    let msg = '';
    if (m) {
      const key = m[2].toLowerCase();
      const norm = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
      const hit = P.ideasByRecent().find((i) => norm(i.name).startsWith(key)) || P.ideasByRecent().find((i) => norm(i.name).includes(key));
      st.tag = m[0].trim();
      if (hit) { st.ideaId = hit.id; msg = `#${m[2]} → ${hit.name}`; }
      else { st.newName = m[2].replace(/-/g, ' ').replace(/^./, (c) => c.toUpperCase()); msg = `No idea matches #${m[2]}. Saving will start a new idea “${st.newName}”.`; }
    }
    const url = P.asUrl(st.text.replace(st.tag || '', '').trim());
    const why = panel.querySelector('#cap-why');
    why.hidden = !url;
    if (url) msg = (msg ? msg + ' · ' : '') + 'Saving as a link; the source is kept.';
    hint(msg);
    renderChips();
  }

  function bindPad(svg) {
    svg.addEventListener('pointerdown', (e) => {
      P.capturePointer(svg, e);
      const r = svg.getBoundingClientRect();
      const pt = (ev) => ({ x: ev.clientX - r.left, y: ev.clientY - r.top });
      const pts = [pt(e)];
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      svg.appendChild(path);
      const mv = (ev) => { pts.push(pt(ev)); path.setAttribute('d', P.ink.raw(pts)); };
      const up = () => {
        svg.removeEventListener('pointermove', mv);
        if (pts.length < 2) { path.remove(); return; }
        const s = P.ink.shape(pts);
        path.setAttribute('d', s.d);
        st.strokes.push(s);
        if (s.shape !== 'free') hint(`Snapped to a clean ${s.shape === 'rect' ? 'box' : s.shape}.`);
      };
      svg.addEventListener('pointermove', mv);
      svg.addEventListener('pointerup', up, { once: true });
    });
  }

  // ---------- voice ----------
  const FILLERS = [/\b(?:u+m+|u+h+|e+r+m+|h+m+)\b/g, /\b(?:you know|i mean|basically|so yeah|okay so|ok so|so okay|right so)\b/g, /\blike(?= (?:what|um|uh|so|a|the)\b)/g];
  P.tidy = (t) => {
    let s = ' ' + (t || '').toLowerCase().replace(/\s+/g, ' ') + ' ';
    for (const re of FILLERS) s = s.replace(re, ' ');
    s = s.replace(/\b(\w+)(\s+\1\b)+/g, '$1').replace(/\s+([,.!?])/g, '$1').replace(/\s{2,}/g, ' ').trim();
    const parts = s.split(/\s*(?:[.!?]+|\band also\b|\balso\b|\banother thing\b|\boh and\b|\bplus\b)\s*/).map((p) => p.replace(/^(?:and|so|but|then)\s+/, '').trim()).filter((p) => p.split(' ').length > 2);
    const fix = (p) => p.replace(/\bi\b/g, 'I').replace(/\bi'(m|ve|d|ll)\b/g, "I'$1").replace(/^./, (c) => c.toUpperCase()).replace(/[,;]$/, '');
    if (!parts.length) return '';
    if (parts.length < 3) return parts.map((p) => fix(p) + '.').join(' ');
    return parts.map((p) => '• ' + fix(p)).join('\n');
  };
  const SAMPLE = "um so okay so I was thinking like what if the gym had a a café at the front you know so people waiting for coffee can see the energy and um also maybe the café is open to the public so it's a second income and also uh we could do a cheaper morning-only membership basically for people who work from home";
  function showTidy() {
    const el = panel && panel.querySelector('#cap-tidy');
    if (el) el.textContent = P.tidy(st.raw) || '';
  }
  function startSpeech() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    const status = panel.querySelector('#cap-status'), mic = panel.querySelector('[data-mic]');
    if (!SR) { status.textContent = "This browser has no speech recognition. Type or paste a ramble, or try the sample."; return; }
    if (rec) return stopSpeech();
    rec = new SR();
    rec.continuous = true; rec.interimResults = true; rec.lang = navigator.language || 'en-US';
    let final = st.raw ? st.raw + ' ' : '';
    rec.onresult = (e) => {
      let interim = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) final += r[0].transcript + ' '; else interim += r[0].transcript;
      }
      st.raw = (final + interim).trim();
      const raw = panel && panel.querySelector('#cap-raw');
      if (raw) raw.value = st.raw;
      showTidy();
    };
    rec.onerror = (e) => { if (status) status.textContent = e.error === 'not-allowed' ? 'Microphone access was blocked. Type or paste a ramble instead.' : 'Listening stopped (' + e.error + ').'; };
    rec.onend = () => { rec = null; const m = panel && panel.querySelector('[data-mic]'); if (m) { m.classList.remove('on'); m.setAttribute('aria-label', 'Start listening'); } };
    try { rec.start(); } catch { rec = null; return; }
    mic.classList.add('on');
    mic.setAttribute('aria-label', 'Stop listening');
    status.textContent = 'Listening… click the mic again to stop.';
  }
  function stopSpeech() { if (rec) { try { rec.stop(); } catch {} rec = null; } }

  // ---------- save ----------
  async function save() {
    let list = [];
    const why = (panel.querySelector('#cap-why')?.value || '').trim();
    if (st.mode === 'type') {
      let t = st.text;
      if (st.tag) t = t.replace(st.tag, ' ');
      t = t.replace(/[ \t]{2,}/g, ' ').trim();
      if (!t) return shake();
      const p = await P.fromText(t);
      if (p.type === 'link' && why) p.why = why;
      list = [p];
    } else if (st.mode === 'grab') {
      const url = P.asUrl(panel.querySelector('#cap-url').value);
      const g = [...(st.grabbed || [])];
      if (url) g.push(await P.fromUrl(url));
      if (!g.length) return shake();
      const off = panel.querySelector('#cap-off').checked;
      list = g.map((p) => ({ ...p, why: why || p.why, page: p.type === 'link' && p.src && off ? p.page || OFFLINE_NOTE : p.page }));
    } else if (st.mode === 'sketch') {
      if (!st.strokes.length) return shake();
      list = [{ type: 'sketch', ...P.ink.toItem(st.strokes), why }];
    } else {
      const t = P.tidy(st.raw);
      if (!t) return shake();
      list = [{ type: 'note', text: t, color: P.NOTE_COLORS[3], tags: ['voice'], ...P.noteSize(t, false, 240) }];
    }
    let dest = st.ideaId && P.idea(st.ideaId) ? st.ideaId : null;
    if (st.newName) { dest = P.createIdea(st.newName); }
    st.text = st.raw = '';
    close(true);
    P.saveMany(list, dest);
  }

  function bindPanel() {
    panel.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.mode) return setMode(b.dataset.mode);
      if (b.dataset.to !== undefined && b.dataset.to !== 'new') { st.ideaId = b.dataset.to || null; st.newName = null; if (st.tag && st.mode === 'type') { const ta = panel.querySelector('#cap-text'); ta.value = st.text = st.text.replace(st.tag, '').trim(); st.tag = null; hint(''); } renderChips(); return; }
      if (b.hasAttribute('data-save')) return save();
      if (b.hasAttribute('data-closecap')) return close(false);
      if (b.hasAttribute('data-file')) return panel.querySelector('#cap-file').click();
      if (b.hasAttribute('data-ungrab')) { st.grabbed = null; return renderBody(); }
      if (b.hasAttribute('data-clear')) { st.strokes = []; return renderBody(); }
      if (b.hasAttribute('data-mic')) return startSpeech();
      if (b.hasAttribute('data-sample')) { stopSpeech(); st.raw = SAMPLE; panel.querySelector('#cap-raw').value = SAMPLE; return showTidy(); }
      if (b.hasAttribute('data-shot')) {
        panel.style.visibility = 'hidden';
        P.sim.shot().then((p) => { if (!panel) return; panel.style.visibility = ''; if (p) setGrab([p]); });
      }
    });
    panel.addEventListener('change', async (e) => {
      if (e.target.id === 'cap-file') {
        const list = [];
        for (const f of e.target.files) { try { list.push(await P.fromFile(f)); } catch {} }
        if (list.length) setGrab(list);
      }
      if (e.target.classList.contains('more') && e.target.value) { st.ideaId = e.target.value; st.newName = null; renderChips(); }
    });
    panel.addEventListener('input', (e) => {
      if (e.target.id === 'cap-text') onType();
      if (e.target.id === 'cap-raw') { st.raw = e.target.value; showTidy(); }
      if (e.target.id === 'cap-why') st.why = e.target.value;
    });
    panel.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Escape') { e.preventDefault(); return close(false); }
      if (e.altKey && e.code === 'Space') { e.preventDefault(); return close(false); }
      if (e.altKey && /^Digit[0-5]$/.test(e.code)) {
        e.preventDefault();
        const n = +e.code.slice(5);
        st.ideaId = n === 0 ? null : st.top[n - 1] || st.ideaId;
        st.newName = null;
        return renderChips();
      }
      if (e.ctrlKey && /^Digit[1-4]$/.test(e.code)) { e.preventDefault(); return setMode(MODES[+e.code.slice(5) - 1][0]); }
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && !(e.target.type === 'checkbox')) { e.preventDefault(); save(); }
    });
    panel.addEventListener('dragover', (e) => { e.preventDefault(); e.stopPropagation(); panel.querySelector('#cap-dz')?.classList.add('over'); });
    panel.addEventListener('dragleave', (e) => { if (!panel.contains(e.relatedTarget)) panel.querySelector('#cap-dz')?.classList.remove('over'); });
    panel.addEventListener('drop', async (e) => {
      e.preventDefault(); e.stopPropagation();
      const list = await P.readTransfer(e.dataTransfer);
      if (list.length) setGrab(list);
    });
  }

  // ---------- simulated region screenshot ----------
  P.sim.shot = () => new Promise((res) => {
    const o = document.createElement('div');
    o.className = 'shot';
    o.innerHTML = '<span>Drag across the screen to capture a region · Esc cancels <span class="sim">Simulated</span></span><i hidden></i>';
    layer().appendChild(o);
    const box = o.querySelector('i');
    const end = (v) => { o.remove(); document.removeEventListener('keydown', onKey, true); res(v); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); end(null); } };
    document.addEventListener('keydown', onKey, true);
    o.addEventListener('pointerdown', (e) => {
      P.capturePointer(o, e);
      const x0 = e.clientX, y0 = e.clientY;
      box.hidden = false;
      const mv = (ev) => Object.assign(box.style, { left: Math.min(x0, ev.clientX) + 'px', top: Math.min(y0, ev.clientY) + 'px', width: Math.abs(ev.clientX - x0) + 'px', height: Math.abs(ev.clientY - y0) + 'px' });
      o.addEventListener('pointermove', mv);
      o.addEventListener('pointerup', async (ev) => {
        o.removeEventListener('pointermove', mv);
        const w = Math.abs(ev.clientX - x0), h = Math.abs(ev.clientY - y0);
        if (w < 20 || h < 20) return end(null);
        const pals = Object.values(P.PALETTES);
        const info = await P.ingestImage(P.art(Math.floor(Math.random() * 999), pals[Math.floor(Math.random() * pals.length)], 480, Math.round((480 * h) / w), 'SCREENSHOT'));
        end({ type: 'image', ...info, w: 260, h: Math.round((260 * h) / w), title: 'Screenshot', tags: ['screenshot'] });
      }, { once: true });
    });
  });

  // ---------- global paste and drop ----------
  window.addEventListener('paste', async (e) => {
    const dt = e.clipboardData;
    const hasFiles = dt && dt.files && dt.files.length > 0;
    if (P.sheets && P.sheets.length) return;
    if (isOpen()) {
      if (P.isTyping(e.target) && !hasFiles) return;
      e.preventDefault();
      const list = await P.readTransfer(dt);
      if (!list.length) return;
      if (st.mode === 'type' && list[0].type === 'note' && !hasFiles) { const ta = panel.querySelector('#cap-text'); ta.value += list[0].text; return onType(); }
      return setGrab(list);
    }
    if (P.isTyping(e.target)) return;
    e.preventDefault();
    const list = await P.readTransfer(dt);
    if (!list.length) return;
    if (P.route.view === 'idea') P.saveMany(list, P.route.id, P.views.idea.center());
    else open({ grabbed: list });
  });
  const clearOver = (keep) => document.querySelectorAll('.over').forEach((n) => n !== keep && n.classList.remove('over'));
  document.addEventListener('dragover', (e) => {
    e.preventDefault();
    const t = e.target.closest && e.target.closest('[data-drop]');
    clearOver(t);
    if (t) t.classList.add('over');
  });
  document.addEventListener('dragleave', (e) => { if (!e.relatedTarget) clearOver(); });
  document.addEventListener('drop', async (e) => {
    e.preventDefault();
    clearOver();
    const t = e.target.closest && e.target.closest('[data-drop]');
    if (t) return P.ingestDrop(e.dataTransfer, t.dataset.drop === 'pile' ? null : t.dataset.drop);
    if (e.dataTransfer.getData('text/x-pile-item')) return;
    const list = await P.readTransfer(e.dataTransfer);
    if (list.length) open({ grabbed: list });
  });
})();
