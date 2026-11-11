// Previews of capture routes that need the Mac app or a plugin: browser extension (with silent saves),
// Pinterest import, region screenshot, and the menu bar drop zones. All live in the Capture menu.
(() => {
  const P = window.P;
  P.sim = P.sim || {};
  const ideaOptions = (cur) => P.ideasByRecent().map((i) => `<option value="${i.id}"${i.id === cur ? ' selected' : ''}>${P.esc(i.name)}</option>`).join('') + `<option value=""${!cur ? ' selected' : ''}>Pile</option>`;
  const defaultDest = () => (P.route.view === 'idea' ? P.route.id : P.idea(P.state.lastIdea) ? P.state.lastIdea : P.ideasByRecent()[0]?.id || '');
  const imgProps = async (seed, pal, ar, extra) => {
    const info = await P.ingestImage(P.art(seed, pal, 480, Math.round(480 * ar)));
    return { type: 'image', ...info, w: 240, h: Math.round(240 * ar), ...extra };
  };

  // ---------- Capture menu ----------
  P.routesMenu = (anchor) => {
    const last = P.idea(defaultDest());
    const pop = P.popover(anchor, `<div class="rm">
      <button class="mi" data-r="cap">${P.icon('plus')} Quick capture <kbd>⌥Space</kbd></button>
      <button class="mi" data-r="shot">${P.icon('grab')} Capture part of the screen</button>
      <hr><p class="meta">Previews of the Mac app and browser plugin</p>
      <button class="mi" data-r="web">${P.icon('globe')} Save from a web page</button>
      <button class="mi" data-r="pin">${P.icon('grid')} Import from Pinterest</button>
      <div class="dzs"><div class="dz" data-drop="pile">Drop here<br><b>Pile</b></div>${last ? `<div class="dz" data-drop="${last.id}">Drop here<br><b>${P.esc(last.name)}</b></div>` : ''}</div>
      <p class="meta">In the Mac app these drop zones live in the menu bar.</p>
    </div>`);
    pop.addEventListener('click', (e) => {
      const r = e.target.closest('[data-r]')?.dataset.r;
      if (!r) return;
      P.closePopover();
      if (r === 'cap') P.capture.open({ trigger: anchor });
      if (r === 'shot') P.sim.shot().then((p) => p && P.capture.open({ grabbed: [p] }));
      if (r === 'web') P.sim.web();
      if (r === 'pin') P.sim.pinterest();
    });
    pop.addEventListener('drop', () => setTimeout(P.closePopover, 50));
  };

  // ---------- browser extension ----------
  const PAGE = {
    url: 'https://spaces-journal.example/boutique-gyms-that-feel-like-cafes',
    title: '12 boutique gyms that feel like cafés',
    text: ['Small gyms are borrowing from coffee shops: warm timber, low pendant lights, plants, and a counter at the front where members linger after a session.',
      'The best ones keep the training floor visible from the street. Passers-by see the energy; members feel part of a neighbourhood rather than a chain.',
      'Most of the spaces below run the café as its own business, open to the public, which smooths out income across quiet months.'],
    imgs: [[71, 'warm', 0.75, 'Timber and concrete in Lisbon'], [72, 'green', 1.25, 'Plants on every wall'], [73, 'amber', 0.8, 'Counter at the entrance'], [74, 'stone', 1.0, 'Changing rooms, done simply'], [75, 'red', 0.7, 'Neon at night'], [76, 'teal', 1.2, 'A quiet stretching corner']],
  };
  P.sim.web = async () => {
    let dest = defaultDest();
    const srcs = PAGE.imgs.map(([seed, pal, ar]) => P.art(seed, P.PALETTES[pal], 480, Math.round(480 * ar)));
    const s = P.sheet(`<div class="bbar">
        <span class="url">${P.esc(PAGE.url)}</span>
        <span class="ext">${P.logo()} Skull Salad</span>
        <label>Save to <select data-dest>${ideaOptions(dest)}</select></label>
        <label title="One click saves straight to the chosen idea, with a small tick"><input type="checkbox" data-silent checked> Silent saves</label>
        <button class="ib" data-close aria-label="Close">${P.icon('x')}</button>
      </div>
      <article class="webpage">
        <p class="prev">Preview of the browser extension</p>
        <h1>${PAGE.title}</h1>
        <p>${PAGE.text[0]}</p>
        <div class="imgs">${PAGE.imgs.map((m, i) => `<figure data-img="${i}"><img src="${srcs[i]}" alt="${P.esc(m[3])}"><button class="save-pill" data-save="${i}">${P.icon('plus')} Save</button><figcaption>${P.esc(m[3])}</figcaption></figure>`).join('')}</div>
        <p>${PAGE.text[1]}</p><p>${PAGE.text[2]}</p>
        <p class="tip">Try: hover an image and click Save · right-click an image · select some text and right-click · untick Silent saves to choose an idea and add a note each time.</p>
      </article>`, { cls: 'web' });
    let count = 0;
    const destName = () => (dest ? P.idea(dest).name : 'the Pile');
    const tick = (fig) => { fig.querySelector('.tick')?.remove(); fig.insertAdjacentHTML('beforeend', `<div class="tick">${P.icon('check')}</div>`); setTimeout(() => fig.querySelector('.tick')?.remove(), 1400); };
    const saveImage = async (i, ask) => {
      const [seed, pal, ar, cap] = PAGE.imgs[i];
      const props = await imgProps(seed, P.PALETTES[pal], ar, { src: PAGE.url, title: cap, page: PAGE.text.join('\n\n') });
      if (ask || !s.el.querySelector('[data-silent]').checked) return P.capture.open({ grabbed: [props], ideaId: dest || null });
      P.saveMany([props], dest || null, null, { quiet: true });
      count++;
      tick(s.el.querySelector(`[data-img="${i}"]`));
      P.toast(`${count} saved to ${destName()}`, { id: 'spree' });
    };
    const saveText = (text) => {
      P.saveMany([{ type: 'note', text, color: P.NOTE_COLORS[7], src: PAGE.url, why: 'from ' + P.domain(PAGE.url), ...P.noteSize(text) }], dest || null, null, { quiet: true });
      P.toast(`Selection saved to ${destName()}`, { id: 'spree' });
    };
    const savePage = () => {
      P.saveMany([{ type: 'web', url: PAGE.url, title: PAGE.title, page: PAGE.text.join('\n\n'), w: 560, h: 400 }], dest || null, null, { quiet: true });
      P.toast(`Page saved to ${destName()}`, { id: 'spree' });
    };
    s.el.addEventListener('change', (e) => { if (e.target.matches('[data-dest]')) dest = e.target.value; });
    s.el.addEventListener('click', (e) => { const b = e.target.closest('[data-save]'); if (b) saveImage(+b.dataset.save); });
    s.el.addEventListener('contextmenu', (e) => {
      const fig = e.target.closest('[data-img]'), text = String(getSelection()).trim();
      if (!fig && !text) return;
      e.preventDefault();
      const items = fig
        ? [[`Save image to ${destName()}`, () => saveImage(+fig.dataset.img)], ['Save image to…', () => saveImage(+fig.dataset.img, true)], ['Save this page', savePage]]
        : [[`Save selection to ${destName()}`, () => saveText(text)], ['Save this page', savePage]];
      P.contextMenu(e.clientX, e.clientY, 'Skull Salad', items);
    });
  };

  // ---------- Pinterest import ----------
  const BOARDS = [['Gym interiors', 'warm', [0.75, 1.3, 1, 1.4, 0.8, 1.1, 1.25, 0.9]], ['Film stills', 'night', [0.56, 0.56, 0.75, 0.56, 1.2, 0.56, 0.8]], ['Packaging', 'pastel', [1, 1.3, 0.8, 1.2, 1, 1.4]]];
  P.sim.pinterest = () => {
    let board = 0, picked = new Set(), dest = defaultDest();
    const s = P.sheet(`<div class="bbar"><b style="flex:1">Import from Pinterest</b><span class="meta">Preview · your boards</span><button class="ib" data-close aria-label="Close">${P.icon('x')}</button></div>
      <div class="pinwrap"><nav class="boards"></nav><div class="pins"></div></div>
      <div class="bbar foot"><button class="btn" data-all>Select all</button><span class="meta" style="flex:1" data-count></span><label>Into <select data-dest>${ideaOptions(dest)}</select></label><button class="btn primary" data-import>Import</button></div>`, { cls: 'pin' });
    const draw = () => {
      const [name, pal, ars] = BOARDS[board];
      s.el.querySelector('.boards').innerHTML = BOARDS.map(([n, , a], i) => `<button class="mi${i === board ? ' on' : ''}" data-board="${i}">${n}<span>${a.length}</span></button>`).join('');
      s.el.querySelector('.pins').innerHTML = ars.map((ar, i) => `<figure data-pin="${i}" class="${picked.has(i) ? 'on' : ''}"><img src="${P.art(100 + board * 20 + i, P.PALETTES[pal], 300, Math.round(300 * ar))}" alt="Pin ${i + 1} from ${P.esc(name)}"></figure>`).join('');
      s.el.querySelector('[data-count]').textContent = picked.size ? `${picked.size} selected from ${name}` : 'Click pins to select them';
    };
    draw();
    s.el.addEventListener('change', (e) => { if (e.target.matches('[data-dest]')) dest = e.target.value; });
    s.el.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-board]');
      if (b) { board = +b.dataset.board; picked = new Set(); return draw(); }
      const p = e.target.closest('[data-pin]');
      if (p) { const i = +p.dataset.pin; picked.has(i) ? picked.delete(i) : picked.add(i); return draw(); }
      if (e.target.closest('[data-all]')) { BOARDS[board][2].forEach((_, i) => picked.add(i)); return draw(); }
      if (e.target.closest('[data-import]')) {
        if (!picked.size) return;
        const [name, pal, ars] = BOARDS[board];
        const list = [];
        for (const i of [...picked].sort()) list.push(await imgProps(100 + board * 20 + i, P.PALETTES[pal], ars[i], { src: `https://pinterest.com/pin/${100000 + board * 100 + i}`, tags: ['pinterest', name.toLowerCase()] }));
        s.close();
        P.saveMany(list, dest || null);
      }
    });
  };

  // ---------- shared context menu ----------
  P.contextMenu = (x, y, title, items) => {
    document.querySelector('.ctx')?.remove();
    const m = document.createElement('div');
    m.className = 'ctx';
    m.innerHTML = `<div>${P.esc(title)}</div>` + items.map(([l], i) => `<button data-i="${i}">${P.esc(l)}</button>`).join('');
    P.$('#layer').appendChild(m);
    const r = m.getBoundingClientRect();
    m.style.left = Math.min(x, innerWidth - r.width - 8) + 'px';
    m.style.top = Math.min(y, innerHeight - r.height - 8) + 'px';
    const done = () => { m.remove(); document.removeEventListener('pointerdown', off, true); };
    const off = (e) => { if (!m.contains(e.target)) done(); };
    m.addEventListener('click', (e) => { const b = e.target.closest('[data-i]'); if (b) { done(); items[+b.dataset.i][1](); } });
    setTimeout(() => document.addEventListener('pointerdown', off, true));
  };
})();
