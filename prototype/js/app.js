// App shell: routing, the floating top pills, popovers, sheets, toasts, global shortcuts, and start-up.
(() => {
  const P = window.P;
  P.route = { view: 'home', id: null };
  P.sheets = [];
  let current = null;

  // ---------- routing ----------
  P.go = (view, id = null, opts = {}) => {
    if (view === 'idea' && !P.idea(id)) { view = 'home'; id = null; }
    P.closePopover();
    if (current && current.unmount) current.unmount();
    P.route = { view, id };
    P.state.route = { view, id };
    if (view === 'idea') P.state.lastIdea = id;
    const v = P.$('#view');
    v.scrollTop = 0;
    v.innerHTML = '';
    current = P.views[view];
    current.mount(v, id, opts);
    P.save();
  };
  P.refresh = () => {
    if (P.route.view === 'idea' && !P.idea(P.route.id)) return P.go('home');
    if (current) current.render();
  };
  P.renderChrome = () => current && current.chrome && current.chrome();

  // The same small cluster of pills sits at the top of every screen.
  P.topBar = (o = {}) => `<div class="topc">
      <button class="pill round home-pill" data-act="home" title="All ideas" aria-label="All ideas">${P.logo()}</button>
      ${o.board ? `<button class="pill name-pill" aria-haspopup="true"><span class="stage-dot"></span><span class="nm"></span>${P.icon('chev')}</button>` : `<span class="pill title-pill">${P.esc(o.title || 'Skull Salad')}</span>`}
      <button class="pill search-pill" data-act="search" title="Search everything (⌘K)">${P.icon('search')}<span>Search</span><kbd>⌘K</kbd></button>
      <button class="pill round" data-act="ai" title="Work with AI" aria-label="Work with AI">${P.icon('spark')}</button>
      <span class="pill split"><button class="cap-main" data-act="capture" title="Capture an idea (⌥Space)">${P.icon('plus')}<span>Capture</span></button><button data-act="routes" title="More ways to capture" aria-label="More ways to capture">${P.icon('chev')}</button></span>
    </div>`;
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b || b.closest('.pop, .sheet, .ai')) return;
    const act = b.dataset.act;
    if (act === 'home') P.go('home');
    if (act === 'search') P.palette.open();
    if (act === 'ai') P.ai.open();
    if (act === 'capture') P.capture.toggle({ trigger: b });
    if (act === 'routes') P.routesMenu(b);
  });

  // ---------- popovers ----------
  let pop = null;
  P.popover = (anchor, html, o = {}) => {
    // Clicking the same trigger again closes it; callers get a detached element so their wiring is harmless.
    if (pop && pop.anchor === anchor) { P.closePopover(); return document.createElement('div'); }
    P.closePopover();
    const el = document.createElement('div');
    el.className = 'pop ' + (o.cls || '');
    el.innerHTML = html;
    P.$('#layer').appendChild(el);
    const r = anchor.getBoundingClientRect(), w = el.offsetWidth, h = el.offsetHeight;
    let left, top;
    if (o.side === 'right') { left = r.right + 10; top = P.clamp(r.top - 8, 8, innerHeight - h - 8); el.style.transformOrigin = '0 20px'; }
    else { left = P.clamp(r.left + r.width / 2 - w / 2, 8, innerWidth - w - 8); top = r.bottom + 8; el.style.transformOrigin = `${r.left + r.width / 2 - left}px 0`; }
    el.style.left = left + 'px';
    el.style.top = top + 'px';
    anchor.classList.add('on');
    const off = (e) => { if (!el.contains(e.target) && !anchor.contains(e.target)) P.closePopover(); };
    setTimeout(() => document.addEventListener('pointerdown', off, true));
    pop = { el, anchor, off };
    return el;
  };
  P.closePopover = () => {
    if (!pop) return;
    pop.el.remove();
    pop.anchor.classList.remove('on');
    document.removeEventListener('pointerdown', pop.off, true);
    pop = null;
  };

  // ---------- sheets and toasts ----------
  P.sheet = (html, o = {}) => {
    const scrim = document.createElement('div');
    scrim.className = 'scrim';
    scrim.innerHTML = `<div class="sheet ${o.cls || ''}" role="dialog" aria-modal="true">${html}</div>`;
    P.$('#layer').appendChild(scrim);
    const el = scrim.firstElementChild;
    const s = { el, close: () => { scrim.remove(); P.sheets = P.sheets.filter((x) => x !== s); o.onClose && o.onClose(); } };
    P.sheets.push(s);
    scrim.addEventListener('pointerdown', (e) => { if (e.target === scrim) s.close(); });
    el.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) s.close(); });
    return s;
  };
  P.toast = (msg, o = {}) => {
    const box = P.$('.toasts');
    let t = o.id && box.querySelector(`[data-tid="${o.id}"]`);
    if (!t) {
      t = document.createElement('div');
      t.className = 'toast';
      if (o.id) t.dataset.tid = o.id;
      box.appendChild(t);
      while (box.children.length > 3) box.firstElementChild.remove();
    }
    t.innerHTML = `<span>${P.esc(msg)}</span>${o.label ? `<button>${P.esc(o.label)}</button>` : ''}`;
    if (o.label) t.querySelector('button').onclick = () => { t.remove(); o.run(); };
    clearTimeout(t._t);
    t._t = setTimeout(() => t.remove(), o.ms || 5000);
  };
  P.deleteIdea = (id) => {
    const i = P.idea(id), n = P.itemsOf(id).filter((o) => o.type !== 'zone' && o.type !== 'arrow').length;
    const s = P.sheet(`<h2>Delete “${P.esc(i.name)}”?</h2><p class="sub">This removes the idea and its ${n} items. You can undo straight after.</p><div class="actions"><button class="btn" data-close>Cancel</button><button class="btn destructive" data-ok>Delete idea</button></div>`, { cls: 'pad' });
    s.el.querySelector('[data-ok]').onclick = () => {
      P.checkpoint();
      P.state.ideas = P.state.ideas.filter((x) => x.id !== id);
      P.state.items = P.state.items.filter((o) => o.ideaId !== id);
      if (P.state.lastIdea === id) P.state.lastIdea = null;
      P.save();
      s.close();
      P.go('home');
      P.toast('Idea deleted', { label: 'Undo', run: P.undo });
    };
  };

  // ---------- keyboard ----------
  document.addEventListener('keydown', (e) => {
    const mod = e.metaKey || e.ctrlKey, k = e.key.toLowerCase();
    if (e.altKey && e.code === 'Space') { e.preventDefault(); return P.capture.toggle(); }
    if (P.capture.isOpen()) return;
    if (P.sheets.length) {
      if (e.key === 'Escape') { e.preventDefault(); P.sheets[P.sheets.length - 1].close(); }
      return;
    }
    if (mod && (k === 'k' || k === 'f')) { e.preventDefault(); return P.palette.open(); }
    if (e.altKey && e.code === 'KeyN') { e.preventDefault(); return P.newIdeaSheet(); }
    if (e.key === 'Escape' && document.querySelector('.pop')) { e.preventDefault(); return P.closePopover(); }
    if (P.isTyping(e.target)) return;
    if (mod && k === 'z') { e.preventDefault(); return e.shiftKey ? P.redo() : P.undo(); }
    if (P.route.view === 'idea' && P.views.idea.key(e)) { e.preventDefault(); return; }
    if (e.key === 'Escape') P.ai.close();
  });

  // ---------- start ----------
  addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') P.flush(); });
  addEventListener('pagehide', () => P.flush());
  (async () => {
    const had = await P.load();
    if (!had) { await P.seed(); await P.flush(); }
    const r = P.state.route;
    P.go(r && r.view ? r.view : 'home', r && r.id);
  })();
})();
