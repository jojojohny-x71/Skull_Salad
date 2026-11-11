// Finding things again: the ⌘K palette, the Everything grid, and the Pile (captures with no idea yet).
(() => {
  const P = window.P;
  const GROUPS = { writing: ['note', 'text', 'label'], images: ['image'], links: ['link', 'web'], video: ['video', 'embed'], drawings: ['sketch'], colours: ['swatch', 'type'] };
  const GROUP_NAMES = [['', 'All'], ['writing', 'Writing'], ['images', 'Images'], ['links', 'Links & pages'], ['video', 'Video'], ['drawings', 'Drawings'], ['colours', 'Colours & type']];
  const TIMES = [['', 'Any time'], ['1', 'Today'], ['7', 'This week'], ['31', 'This month']];
  const SKIP = new Set(['zone', 'arrow', 'tape']);
  const F = (P.ui.find = { group: '', days: '', hue: '' });

  // ---------- search ----------
  const TIME = [[/\btoday\b/, 1], [/\byesterday\b/, 2], [/\b(?:this|last|past) week\b/, 7], [/\b(?:this|last|past) month\b/, 31], [/\b(?:last|past) (\d+) days?\b/, 0]];
  P.parseQuery = (q) => {
    q = (q || '').toLowerCase();
    let days = 0;
    for (const [re, d] of TIME) {
      const m = q.match(re);
      if (m) { days = d || +m[1]; q = q.replace(re, ' '); break; }
    }
    return { words: q.split(/\s+/).map((w) => w.replace(/^#/, '')).filter(Boolean), days };
  };
  const looks = (it) => (it.type === 'image' || it.type === 'swatch' ? P.hue(it.color) : it.type === 'sketch' ? P.hue(it.color) : null);
  // What the item itself says; its idea's name is searchable too but ranks lower.
  const own = (it) => [it.text, it.title, it.why, it.url, it.src, it.page, it.ocr, it.provider, (it.tags || []).join(' '), P.TYPE_NAMES[it.type], looks(it)].filter(Boolean).join(' ').toLowerCase();
  const hay = (it) => { const i = it.ideaId && P.idea(it.ideaId); return own(it) + ' ' + (i ? `${i.name} ${i.kind} ${i.stage}` : 'pile').toLowerCase(); };
  P.search = (q, f = {}) => {
    const { words, days: qd } = P.parseQuery(q);
    const days = qd || +f.days || 0, now = Date.now(), types = f.group && GROUPS[f.group];
    return P.state.items.filter((it) => {
      if (SKIP.has(it.type)) return false;
      if (it.ideaId && !P.idea(it.ideaId)) return false;
      if (types && !types.includes(it.type)) return false;
      // Drawings carry no words, so they only appear when asked for (or when searching by colour).
      if (it.type === 'sketch' && words.length && f.group !== 'drawings' && !f.hue) return false;
      if (f.hue && looks(it) !== f.hue) return false;
      if (days && now - it.created > days * P.DAY) return false;
      if (words.length) { const h = hay(it); if (!words.every((w) => h.includes(w))) return false; }
      return true;
    }).map((it) => [it, words.filter((w) => own(it).includes(w)).length])
      .sort((a, b) => b[1] - a[1] || b[0].created - a[0].created)
      .map(([it]) => it);
  };
  const matchIdeas = (q) => {
    const { words } = P.parseQuery(q);
    const list = P.ideasByRecent();
    return words.length ? list.filter((i) => words.every((w) => `${i.name} ${i.kind} ${i.stage} ${i.next}`.toLowerCase().includes(w))) : list.slice(0, 4);
  };
  const open = (it) => (it.ideaId ? P.go('idea', it.ideaId, { focus: it.id }) : P.go('pile'));

  // ---------- thumbnails and cards ----------
  const handOf = (it) => P.esc(P.fontOf(it.font || P.idea(it.ideaId)?.font || 'caveat'));
  const thumb = (it) => {
    switch (it.type) {
      case 'image': return `<img src="${P.esc(P.srcOf(it))}" alt="">`;
      case 'note': return `<i class="tn" style="background:${it.color}"></i>`;
      case 'swatch': return `<i class="tn" style="background:${it.color}"></i>`;
      case 'sketch': return `<svg viewBox="${it.vb || `0 0 ${it.vw} ${it.vh}`}" preserveAspectRatio="xMidYMid meet" class="k-${it.tool || 'pen'}"><path d="${P.esc(it.d)}" style="${it.tool === 'spray' ? `fill:${it.color}` : `stroke:${it.color || '#1d1b18'};stroke-width:${it.size || 2.6}`}"/></svg>`;
      case 'web': case 'link': return P.icon('globe');
      case 'video': case 'embed': return P.icon('play');
      default: return P.icon('text');
    }
  };
  const titleOf = (it) => {
    if (['note', 'text', 'label'].includes(it.type)) return `<span class="w" style="font-family:${handOf(it)}">${P.esc((it.text || '').split('\n')[0])}</span>`;
    if (it.type === 'swatch') return P.esc(it.color);
    if (it.type === 'type') return P.esc(it.text);
    if (it.type === 'sketch') return 'Drawing';
    if (it.type === 'image' && it.why && !it.title) return `<span class="w" style="font-family:${handOf(it)}">${P.esc(it.why)}</span>`;
    if (it.type === 'image' && it.ocr && !it.title) return `“${P.esc(it.ocr)}”`;
    return P.esc(it.title || P.domain(it.url || it.src) || P.TYPE_NAMES[it.type]);
  };
  P.card = (it, o = {}) => {
    const idea = it.ideaId && P.idea(it.ideaId);
    let body;
    switch (it.type) {
      case 'image': body = `<img src="${P.esc(P.srcOf(it))}" alt="" loading="lazy" draggable="false">`; break;
      case 'note': body = `<div class="c-note" style="background:${it.color};font-family:${handOf(it)}">${P.esc(it.text)}</div>`; break;
      case 'text': case 'label': body = `<div class="c-body c-write" style="font-family:${handOf(it)}">${P.esc(it.text)}</div>`; break;
      case 'swatch': body = `<div class="c-sw" style="background:${it.color}"></div><div class="c-body c-meta">${P.esc(it.color)}</div>`; break;
      case 'type': { const f = P.FACES[it.face] || P.FACES.serif; body = `<div class="c-body c-type" style="font-family:${P.esc(f[1])}">${P.esc(it.text)}</div>`; break; }
      case 'sketch': body = `<div class="c-sk">${thumb(it)}</div>`; break;
      default: body = `<div class="c-body c-link">${thumb(it)}<div><b>${titleOf(it)}</b><small>${P.esc(P.domain(it.url || it.src) || P.TYPE_NAMES[it.type])}</small></div></div>`;
    }
    if (it.why) body += `<div class="c-why" style="font-family:${handOf(it)}">${P.esc(it.why)}</div>`;
    if (it.ai) body += '<span class="badge ai">AI</span>';
    const foot = `<div class="c-foot"><span>${idea ? P.esc(idea.name) : 'Pile'}</span><span>${P.ago(it.created)}</span></div>`;
    const move = o.pile ? `<div class="c-move"><select data-file="${it.id}" aria-label="Move to an idea"><option value="">Move to…</option>${P.ideasByRecent().map((i) => `<option value="${i.id}">${P.esc(i.name)}</option>`).join('')}</select><button class="ib" data-del="${it.id}" title="Delete" aria-label="Delete">${P.icon('trash')}</button></div>` : '';
    return `<div class="card" data-item="${it.id}">${body}${foot}${move}</div>`;
  };
  const filterRow = () => `<div class="chips">${GROUP_NAMES.map(([v, l]) => `<button class="chip${F.group === v ? ' on' : ''}" data-group="${v}">${l}</button>`).join('')}</div>
    <div class="chips">${TIMES.map(([v, l]) => `<button class="chip${F.days === v ? ' on' : ''}" data-days="${v}">${l}</button>`).join('')}
    <span class="hues">${P.HUES.map(([n, c]) => `<button data-hue="${n}" class="${F.hue === n ? 'on' : ''}" style="background:${c}" title="${n}" aria-label="${n}"></button>`).join('')}</span></div>`;
  const onFilter = (e) => {
    const g = e.target.closest('[data-group]'), d = e.target.closest('[data-days]'), h = e.target.closest('[data-hue]');
    if (g) F.group = g.dataset.group;
    else if (d) F.days = d.dataset.days;
    else if (h) F.hue = F.hue === h.dataset.hue ? '' : h.dataset.hue;
    else return false;
    return true;
  };

  // ---------- ⌘K palette ----------
  let pal = null;
  P.palette = {
    open(q = '') {
      if (pal) { pal.querySelector('input').focus(); return; }
      pal = document.createElement('div');
      pal.className = 'scrim light';
      pal.innerHTML = `<div class="palette" role="dialog" aria-label="Search">
        <label class="pal-in">${P.icon('search')}<input placeholder="Search ideas, notes, colours, or “last week”" autocomplete="off" value="${P.esc(q)}"><kbd>esc</kbd></label>
        <div class="pal-f"></div><div class="pal-res" role="listbox"></div>
        <div class="pal-foot"><span>↑↓ move · ↵ open</span><button class="link" data-all>See everything as a grid ⌘↵</button></div></div>`;
      P.$('#layer').appendChild(pal);
      const input = pal.querySelector('input');
      let act = 0;
      const draw = () => {
        const v = input.value, ideas = matchIdeas(v).slice(0, 4), items = P.search(v, F).slice(0, 8);
        pal.querySelector('.pal-f').innerHTML = filterRow();
        pal.querySelector('.pal-res').innerHTML = (ideas.length ? `<h3>Ideas</h3>${ideas.map((i) => `<button class="pr" data-idea="${i.id}"><span class="th">${P.icon('stack')}</span><span class="pt">${P.esc(i.name)}</span><span class="pm"><span class="stage s-${i.stage.toLowerCase()}">${i.stage}</span></span></button>`).join('')}` : '')
          + (items.length ? `<h3>Things</h3>${items.map((it) => `<button class="pr" data-item="${it.id}"><span class="th">${thumb(it)}</span><span class="pt">${titleOf(it)}</span><span class="pm">${it.ideaId ? P.esc(P.idea(it.ideaId).name) : 'Pile'} · ${P.ago(it.created)}</span></button>`).join('')}` : '')
          + (!ideas.length && !items.length ? '<p class="none">Nothing matches. Try fewer words, or a colour.</p>' : '');
        act = 0;
        mark();
      };
      const rows = () => [...pal.querySelectorAll('.pr')];
      const mark = () => rows().forEach((r, i) => { r.classList.toggle('act', i === act); if (i === act) r.scrollIntoView({ block: 'nearest' }); });
      const choose = (r) => {
        if (!r) return;
        const it = r.dataset.item && P.item(r.dataset.item), id = r.dataset.idea;
        P.palette.close();
        if (it) open(it); else if (id) P.go('idea', id);
      };
      const all = () => { const v = input.value; P.palette.close(); P.go('library', null, { q: v }); };
      input.addEventListener('input', draw);
      pal.addEventListener('pointerdown', (e) => { if (e.target === pal) P.palette.close(); });
      pal.addEventListener('click', (e) => {
        if (onFilter(e)) { draw(); input.focus(); return; }
        if (e.target.closest('[data-all]')) return all();
        choose(e.target.closest('.pr'));
      });
      pal.addEventListener('keydown', (e) => {
        e.stopPropagation();
        if (e.key === 'Escape') { e.preventDefault(); P.palette.close(); }
        else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); act = P.clamp(act + (e.key === 'ArrowDown' ? 1 : -1), 0, rows().length - 1); mark(); }
        else if (e.key === 'Enter') { e.preventDefault(); (e.metaKey || e.ctrlKey) ? all() : choose(rows()[act]); }
      });
      draw();
      input.focus();
      input.select();
    },
    close() { if (pal) { pal.remove(); pal = null; } },
  };

  // ---------- Everything ----------
  let ac, query = '';
  P.views.library = {
    mount(view, id, opts = {}) {
      view.className = 'v-library';
      query = opts.q || '';
      ac = new AbortController();
      const sig = { signal: ac.signal };
      view.addEventListener('input', (e) => { if (e.target.id === 'libq') { query = e.target.value; this.results(); } }, sig);
      view.addEventListener('click', (e) => {
        if (onFilter(e)) return this.render();
        const c = e.target.closest('[data-item]');
        if (c) open(P.item(c.dataset.item));
      }, sig);
      this.render();
      view.querySelector('#libq').focus();
    },
    unmount() { ac && ac.abort(); },
    render() {
      P.$('#view').innerHTML = `${P.topBar({ title: 'Everything' })}
        <section class="page">
          <label class="bigsearch">${P.icon('search')}<input id="libq" value="${P.esc(query)}" placeholder="Search ideas, notes, colours, or “last week”" autocomplete="off"></label>
          <div class="filters">${filterRow()}</div>
          <div class="count"></div><div class="grid"></div>
        </section>`;
      const q = P.$('#libq');
      q.focus(); q.setSelectionRange(q.value.length, q.value.length);
      this.results();
    },
    results() {
      const res = P.search(query, F);
      P.$('#view .count').textContent = `${res.length} ${res.length === 1 ? 'thing' : 'things'}`;
      P.$('#view .grid').innerHTML = res.length ? `<div class="cards">${res.map((it) => P.card(it)).join('')}</div>` : '<p class="none">Nothing matches. Try fewer words, or a colour.</p>';
    },
  };

  // ---------- Pile ----------
  let pac;
  P.views.pile = {
    mount(view) {
      view.className = 'v-pile';
      pac = new AbortController();
      const sig = { signal: pac.signal };
      view.addEventListener('change', (e) => { const id = e.target.dataset.file; if (id && e.target.value) P.fileItem(id, e.target.value); }, sig);
      view.addEventListener('click', (e) => {
        const d = e.target.closest('[data-del]');
        if (d) { P.checkpoint(); P.removeItems([d.dataset.del]); P.save(); P.refresh(); P.toast('Deleted', { label: 'Undo', run: P.undo }); return; }
        if (e.target.closest('[data-suggest]')) P.ai.open('pile');
      }, sig);
      this.render();
    },
    unmount() { pac && pac.abort(); },
    render() {
      const items = P.itemsOf(null).sort((a, b) => b.created - a.created);
      P.$('#view').innerHTML = `${P.topBar({ title: 'Pile' })}
        <section class="page">
          <header class="home-head"><div><h1>Pile</h1><p class="sub">Things you dumped without picking an idea. Move them when you have the energy. No rush.</p></div><span class="spacer"></span>${items.length ? `<button class="btn" data-suggest>${P.icon('spark')} Suggest homes</button>` : ''}</header>
          ${items.length ? `<div class="cards">${items.map((it) => P.card(it, { pile: true })).join('')}</div>` : '<p class="none">Nothing waiting. Everything has a home.</p>'}
        </section>`;
    },
  };
})();
