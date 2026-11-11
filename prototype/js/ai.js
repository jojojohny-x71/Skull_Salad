// Mock of working with an AI assistant. In the Mac app a local MCP server exposes the same four abilities
// (read, add, organise with approval, develop) to Claude or another assistant. Here they run on simple local rules.
(() => {
  const P = window.P;
  const STOP = new Set('a an and are about all any anything collected did do does everything find for from got have i in into is it me my of on or saved show stuff that the things this to what which with ideas notes'.split(' '));
  const stem = (w) => w.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '').replace(/(ies|es|s)$/, (m) => (m === 'ies' ? 'y' : ''));
  const words = (s) => (s || '').split(/\s+/).map(stem).filter((w) => w.length > 2 && !STOP.has(w));
  // Only what a person wrote or saved: automatic tags (item type, source domain) would make everything match.
  const AUTO = new Set(['note', 'text', 'image', 'video', 'link', 'sketch', 'swatch', 'type', 'zone', 'arrow', 'ai', 'voice', 'screenshot', 'pinterest']);
  const textOf = (it) => [it.text, it.title, it.why, it.label, it.ocr, (it.tags || []).filter((t) => !AUTO.has(t) && !t.includes('.')).join(' ')].filter(Boolean).join(' ');
  const label = (it) => oneLine(it.text || it.title || it.why || '') || P.TYPE_NAMES[it.type];
  const firstLine = (t) => (t || '').split('\n')[0].replace(/^•\s*/, '');
  const oneLine = (t) => (t || '').replace(/:\s*\n/g, ': ').replace(/\s*\n+\s*/g, ', ');
  const plural = (n, w) => `${n} ${w.toLowerCase()}${n > 1 ? (/(s|sh|ch|x)$/i.test(w) ? 'es' : 's') : ''}`;
  const hueNames = (items) => [...new Set(items.map((o) => (o.type === 'image' || o.type === 'swatch') && P.hue(o.color)).filter(Boolean))];

  let panel = null, scope = null;
  const close = () => { panel && panel.remove(); panel = null; };
  const out = (html) => { panel.querySelector('.out-wrap').innerHTML = `<div class="out">${html}</div>`; };

  P.ai = {
    open(mode) {
      if (panel && !mode) return close();
      if (!panel) build();
      if (mode === 'pile') suggestHomes();
    },
    close,
  };

  function build() {
    scope = P.route.view === 'idea' ? P.route.id : null;
    const i = scope && P.idea(scope);
    panel = document.createElement('aside');
    panel.className = 'ai';
    panel.setAttribute('aria-label', 'Work with AI');
    panel.innerHTML = `<header>${P.icon('spark')}<b>Work with AI</b><span class="meta">Preview</span><button class="ib" data-x aria-label="Close">${P.icon('x')}</button></header>
      <div class="ai-body">
        <p class="sub">In the Mac app, Skull Salad runs a local MCP server so Claude or another assistant on your Mac can read and work on your ideas. Here, simple rules stand in for it.</p>
        <label class="bigsearch small">${P.icon('search')}<input id="ai-ask" placeholder="Ask, e.g. what have I saved about pricing?"></label>
        <p class="meta">Working on: <b>${i ? P.esc(i.name) : 'All ideas'}</b></p>
        <div class="acts">
          <button data-a="summary"><b>Summarise ${i ? 'this idea' : 'my ideas'}</b><small>Read</small></button>
          <button data-a="outline"${i ? '' : ' disabled'}><b>Add an outline to the board</b><small>Add · marked as AI-added${i ? '' : ' · open an idea first'}</small></button>
          <button data-a="${i ? 'organise' : 'homes'}"><b>${i ? 'Tidy the Unsorted section' : 'Suggest homes for Pile items'}</b><small>Organise · nothing moves until you approve</small></button>
          <button data-a="brief"${i ? '' : ' disabled'}><b>Turn this into a brief</b><small>Develop · saved back as a note${i ? '' : ' · open an idea first'}</small></button>
        </div>
        <div class="out-wrap"></div>
      </div>`;
    P.$('#layer').appendChild(panel);
    panel.addEventListener('click', (e) => {
      if (e.target.closest('[data-x]')) return close();
      const a = e.target.closest('[data-a]')?.dataset.a;
      if (a === 'summary') summary();
      if (a === 'outline') outline();
      if (a === 'organise') organise();
      if (a === 'homes') suggestHomes();
      if (a === 'brief') brief();
      const go = e.target.closest('[data-go-item]');
      if (go) { const it = P.item(go.dataset.goItem); if (it) it.ideaId ? P.go('idea', it.ideaId, { focus: it.id }) : P.go('pile'); }
    });
    panel.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter' && e.target.id === 'ai-ask') ask(e.target.value);
      if (e.key === 'Escape') close();
    });
  }

  const addNote = (text, props = {}) => {
    const size = P.noteSize(text, true, 320);
    const [it] = P.saveMany([{ type: 'note', text, color: '#FFFFFF', font: 'sys', ai: true, ...size, ...props }], scope, null, { quiet: true });
    P.autoTag(it);
    if (P.route.view === 'idea') P.views.idea.focus(it.id);
    P.toast('Added to the board, marked AI', { label: 'Undo', run: P.undo });
    return it;
  };

  // ---------- read ----------
  function ask(q) {
    const ws = words(q);
    if (!ws.length) return out('Ask about something specific, like a topic, a colour or a place.');
    const pool = P.state.items.filter((o) => !['zone', 'arrow'].includes(o.type) && (!scope || o.ideaId === scope));
    const hits = pool.map((o) => { const t = words(textOf(o) + ' ' + (P.idea(o.ideaId)?.name || '')); return [o, ws.filter((w) => t.some((x) => x.startsWith(w) || w.startsWith(x))).length]; })
      .filter(([, n]) => n).sort((a, b) => b[1] - a[1] || b[0].created - a[0].created).slice(0, 6);
    if (!hits.length) return out(`Nothing mentions “${P.esc(ws.join(' '))}”${scope ? ' in this idea' : ''}.`);
    const where = [...new Set(hits.map(([o]) => (o.ideaId ? P.idea(o.ideaId).name : 'the Pile')))];
    out(`Found ${hits.length} ${hits.length === 1 ? 'thing' : 'things'}, in ${where.map(P.esc).join(', ')}:<div class="ai-hits">${hits.map(([o]) => `<button class="row" data-go-item="${o.id}"><span class="nm">${P.esc(label(o))}</span></button>`).join('')}</div>`);
  }
  function summary() {
    if (!scope) {
      const ideas = P.ideasByRecent(), live = ideas.filter((i) => !P.isStale(i)), stale = ideas.filter(P.isStale);
      return out(`You have ${ideas.length} ideas: ${live.length} active and ${stale.length} resting.\n\n${live.map((i) => `• ${P.esc(i.name)} (${i.stage})${i.next ? ' · next: ' + P.esc(i.next) : ''}`).join('\n')}\n\nResting longest: ${stale.map((i) => `${P.esc(i.name)} (${P.ago(i.touched)})`).join(', ') || 'none'}.\n${P.itemsOf(null).length} things are waiting in the Pile.`);
    }
    const i = P.idea(scope), items = P.itemsOf(scope).filter((o) => !['zone', 'arrow'].includes(o.type));
    const counts = Object.entries(items.reduce((m, o) => ((m[P.TYPE_NAMES[o.type]] = (m[P.TYPE_NAMES[o.type]] || 0) + 1), m), {})).map(([k, n]) => plural(n, k)).join(', ');
    const notes = items.filter((o) => o.type === 'note' || o.type === 'text').sort((a, b) => a.y - b.y || a.x - b.x).slice(0, 5);
    const whys = items.filter((o) => o.why).map((o) => o.why).slice(0, 4);
    const doms = [...new Set(items.map((o) => P.domain(o.src)).filter(Boolean))];
    out(`${P.esc(i.name)} is a ${i.kind.toLowerCase()} idea at the ${i.stage} stage, last touched ${P.ago(i.touched)}.\n\nWhat's here: ${counts || 'nothing yet'}.${notes.length ? `\n\nKey points:\n${notes.map((o) => '• ' + P.esc(oneLine(o.text))).join('\n')}` : ''}${hueNames(items).length ? `\n\nLook: ${hueNames(items).join(', ')}${whys.length ? ' · ' + whys.map(P.esc).join('; ') : ''}.` : ''}${doms.length ? `\nSources: ${doms.join(', ')}` : ''}\nNext step: ${P.esc(i.next || 'not set')}`);
  }

  // ---------- add ----------
  const HEADINGS = {
    Business: ['Problem', 'Offer', 'Customers', 'Money', 'Open questions'],
    Film: ['Logline', 'Look and feel', 'Scenes', 'Open questions'],
    Script: ['Premise', 'Beats', 'Open questions'],
    App: ['Core idea', 'Key features', 'Look and feel', 'Open questions'],
    Other: ['What it is', 'Pieces so far', 'Open questions'],
  };
  function outline() {
    const i = P.idea(scope), items = P.itemsOf(scope);
    const notes = items.filter((o) => (o.type === 'note' || o.type === 'text') && !o.ai).map((o) => firstLine(o.text)).filter(Boolean);
    const qs = notes.filter((t) => t.trim().endsWith('?'));
    const money = notes.filter((t) => /\d|price|membership|income|revenue|cost|₹|\$|£|break-even/i.test(t) && !qs.includes(t));
    const rest = notes.filter((t) => !qs.includes(t) && !money.includes(t));
    const look = items.filter((o) => o.why).map((o) => o.why);
    const fill = (h) => {
      if (h === 'Open questions') return qs.length ? qs : ['Who is this for, exactly?'];
      if (h === 'Money') return money.length ? money : ['How does it make money?'];
      if (h === 'Look and feel') return look.length ? look.slice(0, 3) : ['Add a few images'];
      if (/Problem|Logline|Premise|Core idea|What it is/.test(h)) return rest.slice(0, 1).concat(rest.length ? [] : ['One sentence on the idea']);
      return rest.slice(1, 4).length ? rest.slice(1, 4) : ['…'];
    };
    const text = `Outline: ${i.name}\n\n` + (HEADINGS[i.kind] || HEADINGS.Other).map((h) => `${h}\n${fill(h).map((t) => '• ' + t).join('\n')}`).join('\n\n');
    out(`Outline added to the board from ${notes.length} of your notes.`);
    addNote(text);
  }

  // ---------- organise (with approval) ----------
  function organise() {
    const items = P.itemsOf(scope);
    const zone = items.find((o) => o.type === 'zone' && o.unsorted);
    const inZ = (o) => zone && o.type !== 'zone' && o.type !== 'arrow' && o.x + o.w / 2 > zone.x && o.x + o.w / 2 < zone.x + zone.w && o.y + o.h / 2 > zone.y && o.y + o.h / 2 < zone.y + zone.h;
    const mem = items.filter(inZ);
    if (!mem.length) return out('Nothing in Unsorted right now. New captures land there.');
    const groups = {};
    for (const o of mem) { const g = o.type === 'image' || o.type === 'video' ? 'References' : o.type === 'link' ? 'Links' : o.type === 'swatch' || o.type === 'type' ? 'Style' : 'Thoughts'; (groups[g] ||= []).push(o); }
    out(`Proposal: split Unsorted (${mem.length} items) into ${plural(Object.keys(groups).length, 'zone')}.\n\n${Object.entries(groups).map(([g, l]) => `• ${g}: ${l.length}`).join('\n')}\n<button class="btn primary" data-apply>Apply</button> <button class="btn" data-skip>Not now</button>`);
    panel.querySelector('[data-skip]').onclick = () => out('Left as it is.');
    panel.querySelector('[data-apply]').onclick = () => {
      P.checkpoint();
      let x = zone.x;
      for (const [g, l] of Object.entries(groups)) {
        const z = P.newItem({ ideaId: scope, type: 'zone', label: g, x, y: zone.y, w: 300, h: 200 });
        P.layoutZone(z, l);
        x += z.w + 40;
      }
      P.removeItems([zone.id]);
      P.touch(scope); P.save(); P.refresh();
      out('Done. Unsorted is split into zones.');
      P.toast('Organised', { label: 'Undo', run: P.undo });
    };
  }
  function suggestHomes() {
    if (!panel) build();
    const pile = P.itemsOf(null);
    if (!pile.length) return out('The Pile is empty.');
    const ideas = P.state.ideas.map((i) => {
      const its = P.itemsOf(i.id);
      return { i, words: new Set(words(i.name + ' ' + i.kind + ' ' + its.map(textOf).join(' '))), hues: new Set(hueNames(its)) };
    });
    const props = pile.map((o) => {
      const ws = words(textOf(o)), h = (o.type === 'image' || o.type === 'swatch') && P.hue(o.color);
      let best = null, score = 0, why = '';
      for (const c of ideas) {
        const shared = ws.filter((w) => [...c.words].some((x) => x.startsWith(w) || w.startsWith(x)));
        const s = shared.length + (h && c.hues.has(h) ? 0.6 : 0);
        if (s > score) { score = s; best = c.i; why = shared.length ? `shares “${shared.slice(0, 2).join('”, “')}”` : `same ${h} tones`; }
      }
      return { o, best: score >= 0.6 ? best : null, why };
    });
    const sugg = props.filter((p) => p.best);
    out(`${sugg.length ? 'Suggested homes. Untick any you disagree with.' : 'No clear homes; these can stay in the Pile.'}\n<div class="ai-hits">${props.map((p, n) => `<label class="row" style="height:auto;padding:6px 8px;align-items:flex-start"><input type="checkbox" data-n="${n}" ${p.best ? 'checked' : 'disabled'}><span class="nm" style="white-space:normal">${P.esc(label(p.o))}<br><small class="meta">${p.best ? `→ ${P.esc(p.best.name)} · ${P.esc(p.why)}` : 'stays in the Pile'}</small></span></label>`).join('')}</div>${sugg.length ? '<button class="btn primary" data-apply>File ticked items</button>' : ''}`);
    const ap = panel.querySelector('[data-apply]');
    if (ap) ap.onclick = () => {
      P.checkpoint();
      let n = 0;
      panel.querySelectorAll('[data-n]:checked').forEach((c) => { const p = props[+c.dataset.n]; p.o.ideaId = p.best.id; P.autoPlace(p.o); P.touch(p.best.id); n++; });
      P.save(); P.refresh();
      out(`Filed ${n} ${n === 1 ? 'item' : 'items'}.`);
      P.toast(`Filed ${n} from the Pile`, { label: 'Undo', run: P.undo });
    };
  }

  // ---------- develop ----------
  function brief() {
    const i = P.idea(scope), items = P.itemsOf(scope).filter((o) => !['zone', 'arrow'].includes(o.type) && !o.ai);
    const notes = items.filter((o) => o.type === 'note' || o.type === 'text').sort((a, b) => a.created - b.created).map((o) => oneLine(o.text));
    const qs = notes.filter((t) => t.trim().endsWith('?'));
    const facts = notes.filter((t) => !qs.includes(t));
    const look = [...hueNames(items), ...items.filter((o) => o.why).map((o) => o.why)].slice(0, 5);
    const text = `Brief: ${i.name}\n\nWhat it is\n${facts[0] || 'One sentence on the idea.'}\n\nWhat we know\n${facts.slice(1, 5).map((t) => '• ' + t).join('\n') || '• Not much yet'}\n\nLook and feel\n${look.length ? look.join(', ') : 'Add a few references'}\n\nOpen questions\n${(qs.length ? qs : ['Who is this for?', 'What would prove it works?']).map((t) => '• ' + t).join('\n')}\n\nNext step\n${i.next || 'Pick one small thing to test this week.'}`;
    out('Brief drafted from your notes and saved to the board.');
    addNote(text);
  }
})();
