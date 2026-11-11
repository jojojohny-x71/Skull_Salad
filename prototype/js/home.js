// Home: a frosted glass folder per idea on the paper, the Pile as the one dark folder, and the new-idea sheet.
(() => {
  const P = window.P;
  const STALE = 21 * P.DAY;
  const KIND_COLORS = { App: ['#8f7cff', '#ffb8e2'], Film: ['#2b3a8f', '#e0392b'], Script: ['#8c8473', '#e9e4da'], Business: ['#e2603b', '#f2b544'], Other: ['#2f9e5b', '#4b55f5'] };
  const TEMPLATES = { blank: 'Blank page', moodboard: 'Moodboard', stylescape: 'Stylescape', script: 'Script beats', business: 'Business canvas' };
  const EDGE = 'M0.6 42 Q0.6 24.6 18 24.6 L92 24.6 C112 24.6 112 0.6 134 0.6 L254 0.6 Q271.4 0.6 271.4 18 L271.4 126 Q271.4 143.4 254 143.4 L18 143.4 Q0.6 143.4 0.6 126 Z';

  P.isStale = (i) => i.stage === 'Parked' || Date.now() - i.touched > STALE;
  P.ideasByRecent = () => [...P.state.ideas].sort((a, b) => b.touched - a.touched);

  const count = (id) => P.itemsOf(id).filter((o) => !['zone', 'arrow', 'tape', 'sketch'].includes(o.type)).length;
  const peekOf = (items, font) => [...items.filter((o) => o.type === 'image'), ...items.filter((o) => o.type === 'note')].slice(0, 2).map((o) => o.type === 'image'
    ? `<img src="${P.esc(P.srcOf(o))}" alt="" draggable="false">`
    : `<i style="background:${o.color};font-family:${P.esc(P.fontOf(font))}">${P.esc((o.text || '').slice(0, 50))}</i>`).join('');

  function folder(idea) {
    const items = P.itemsOf(idea.id).sort((a, b) => b.created - a.created);
    const k = KIND_COLORS[idea.kind] || KIND_COLORS.Other;
    const imgs = items.filter((o) => o.type === 'image');
    const cols = items.filter((o) => o.color && (o.type === 'image' || o.type === 'swatch' || o.type === 'note')).map((o) => o.color);
    return `<div class="folder" data-open="${idea.id}" data-drop="${idea.id}" tabindex="0" role="button" aria-label="Open ${P.esc(idea.name)}">
      <div class="f-back" style="--c1:${cols[0] || k[0]};--c2:${cols[1] || k[1]}">${imgs[0] ? `<img src="${P.esc(P.srcOf(imgs[0]))}" alt="">` : ''}</div>
      <div class="f-peek">${peekOf(items, idea.font)}</div>
      <div class="f-front">
        <svg class="f-edge" viewBox="0 0 272 144" aria-hidden="true"><path d="${EDGE}"/></svg>
        <div class="f-name">${P.esc(idea.name)}</div>
        <div class="f-meta"><span class="stage s-${idea.stage.toLowerCase()}">${idea.stage}</span><span class="date">${P.day(idea.touched)}</span></div>
      </div>
      <button class="f-add" data-cap="${idea.id}" title="Dump into ${P.esc(idea.name)}" aria-label="Dump into ${P.esc(idea.name)}">${P.icon('plus')}</button>
    </div>`;
  }
  function pileFolder() {
    const items = P.itemsOf(null).sort((a, b) => b.created - a.created), n = items.length;
    const img = items.find((o) => o.type === 'image');
    return `<div class="folder dark" data-pile data-drop="pile" tabindex="0" role="button" aria-label="Open the Pile">
      <div class="f-back" style="--c1:#e0392b;--c2:#1d1b18">${img ? `<img src="${P.esc(P.srcOf(img))}" alt="">` : ''}</div>
      <div class="f-peek">${peekOf(items, 'caveat')}</div>
      <div class="f-front">
        <svg class="f-edge" viewBox="0 0 272 144" aria-hidden="true"><path d="${EDGE}"/></svg>
        <div class="f-name">Pile</div>
        <div class="f-meta"><span>${n ? `${n} waiting for a home` : 'Empty'}</span></div>
      </div>
      <button class="f-add" data-cap="" title="Dump into the Pile" aria-label="Dump into the Pile">${P.icon('plus')}</button>
    </div>`;
  }

  let ac;
  P.views.home = {
    mount(view) {
      view.className = 'v-home';
      ac = new AbortController();
      const sig = { signal: ac.signal };
      view.addEventListener('click', (e) => {
        const cap = e.target.closest('[data-cap]');
        if (cap) { e.stopPropagation(); return P.capture.open({ ideaId: cap.dataset.cap || null, trigger: cap }); }
        if (e.target.closest('[data-new]')) return P.newIdeaSheet();
        if (e.target.closest('[data-all]')) return P.go('library');
        if (e.target.closest('[data-pile]')) return P.go('pile');
        const f = e.target.closest('[data-open]');
        if (f) P.go('idea', f.dataset.open);
      }, sig);
      view.addEventListener('keydown', (e) => {
        const f = e.target.closest('[data-open], [data-pile]');
        if (!f || e.target !== f || (e.key !== 'Enter' && e.key !== ' ')) return;
        e.preventDefault();
        f.dataset.open ? P.go('idea', f.dataset.open) : P.go('pile');
      }, sig);
      this.render();
    },
    unmount() { ac && ac.abort(); },
    render() {
      const ideas = P.ideasByRecent(), active = ideas.filter((i) => !P.isStale(i)), stale = ideas.filter(P.isStale);
      P.$('#view').innerHTML = `${P.topBar({ title: 'Skull Salad' })}
        <section class="home">
          <header class="home-head"><h1>Ideas</h1><span class="spacer"></span><button class="link" data-all>${P.icon('grid')} Everything</button><button class="btn" data-new>${P.icon('plus')} New idea <kbd>⌥N</kbd></button></header>
          <div class="folders">${pileFolder()}${active.map(folder).join('')}<button class="folder new" data-new>${P.icon('plus')}<span>New idea</span></button></div>
          ${stale.length ? `<h2>Resting <span>Parked, or untouched for 3 weeks</span></h2><div class="folders resting">${stale.map(folder).join('')}</div>` : ''}
        </section>`;
    },
  };

  // ---------- new idea ----------
  P.createIdea = (name, o = {}) => {
    const now = Date.now();
    const idea = { id: P.uid(), name: name || 'Untitled idea', kind: 'Other', stage: 'Spark', next: '', surface: 'dot', font: 'caveat', created: now, touched: now, ...o };
    P.state.ideas.push(idea);
    return idea.id;
  };
  const pick = (name, list, cur, style) => `<div class="chips" data-pick="${name}">${list.map(([v, l]) => `<button class="chip${v === cur ? ' on' : ''}" data-v="${v}"${style ? ` style="${style(v)}"` : ''}>${l}</button>`).join('')}</div>`;
  P.newIdeaSheet = (prefill = {}) => {
    const s = P.sheet(`<h2>New idea</h2>
      <label class="fld"><span>Name</span><input type="text" class="in" id="ni-name" placeholder="e.g. Gym with a café" value="${P.esc(prefill.name || '')}"></label>
      <div class="fld"><span>Kind</span>${pick('kind', P.KINDS.map((k) => [k, k]), prefill.kind || 'Other')}</div>
      <div class="fld"><span>Start with</span>${pick('tpl', Object.entries(TEMPLATES), 'blank')}</div>
      <div class="fld"><span>Paper</span>${pick('surface', Object.entries(P.SURFACES), 'dot')}</div>
      <div class="fld"><span>Your handwriting</span>${pick('font', Object.entries(P.FONTS), 'caveat', (v) => `font-family:${P.fontOf(v).replace(/"/g, "'")};font-size:17px`)}</div>
      <div class="actions"><button class="btn" data-close>Cancel</button><button class="btn primary" data-ok>Create</button></div>`, { cls: 'pad' });
    const val = (n) => s.el.querySelector(`[data-pick="${n}"] .on`)?.dataset.v;
    const create = () => {
      P.checkpoint();
      const id = P.createIdea(s.el.querySelector('#ni-name').value.trim(), { kind: val('kind'), surface: val('surface'), font: val('font') });
      if (val('tpl') !== 'blank') P.applyTemplate(id, val('tpl'), { x: 0, y: 0 });
      P.save();
      s.close();
      P.go('idea', id);
    };
    s.el.addEventListener('click', (e) => {
      const c = e.target.closest('[data-pick] .chip');
      if (c) { c.parentElement.querySelectorAll('.chip').forEach((b) => b.classList.toggle('on', b === c)); return; }
      if (e.target.closest('[data-ok]')) create();
    });
    s.el.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target.id === 'ni-name') create(); });
    s.el.querySelector('#ni-name').focus();
  };

  // ---------- layouts ----------
  P.applyTemplate = (ideaId, key, o) => {
    const Z = (dx, dy, w, h, label) => P.newItem({ ideaId, type: 'zone', label, x: o.x + dx, y: o.y + dy, w, h });
    const N = (dx, dy, text, c = 0) => P.newItem({ ideaId, type: 'note', text, color: P.NOTE_COLORS[c], x: o.x + dx, y: o.y + dy, w: 200, h: 140 });
    const SW = (dx, dy, color) => P.newItem({ ideaId, type: 'swatch', color, x: o.x + dx, y: o.y + dy, w: 96, h: 116 });
    switch (key) {
      case 'moodboard':
        Z(0, 0, 680, 460, 'Images'); Z(720, 0, 460, 210, 'Colours'); Z(720, 250, 460, 210, 'Type'); Z(0, 520, 1180, 260, 'Notes');
        break;
      case 'stylescape':
        ['Palette', 'Type', 'Imagery', 'Texture'].forEach((l, i) => Z(i * 340, 0, 310, 560, l));
        ['#1d1b18', '#e9e4da', '#e0392b'].forEach((c, i) => SW(32, 40 + i * 150, c));
        P.newItem({ ideaId, type: 'type', text: 'Aa Headline', face: 'serif', x: o.x + 372, y: o.y + 40, w: 246, h: 130 });
        P.newItem({ ideaId, type: 'type', text: 'Body copy reads like this.', face: 'sans', x: o.x + 372, y: o.y + 200, w: 246, h: 130 });
        break;
      case 'script':
        [['Act 1 · Setup', ['Opening image', 'Inciting incident']], ['Act 2 · Confrontation', ['Midpoint twist', 'All is lost']], ['Act 3 · Resolution', ['Climax', 'Final image']]].forEach(([l, beats], i) => {
          Z(i * 340, 0, 300, 420, l);
          beats.forEach((b, j) => N(i * 340 + 50, 40 + j * 180, b, j ? 6 : 0));
        });
        break;
      case 'business':
        [['Problem', 0, 0], ['Solution', 350, 0], ['Customers', 700, 0], ['Money', 0, 320], ['Channels', 350, 320], ['Next steps', 700, 320]].forEach(([l, x, y]) => Z(x, y, 320, 280, l));
        break;
    }
  };
})();
