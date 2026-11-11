// Sample ideas so the prototype opens with something to explore. Imagery is generated locally:
// flat printed posters, and transparent cut-out shapes for collage.
(() => {
  const P = window.P;
  const rng = (seed) => { let s = seed * 9301 + 49297; return () => (s = (s * 9301 + 49297) % 233280) / 233280; };
  const isDark = (hex) => { const n = parseInt(hex.slice(1), 16); return ((n >> 16) * 299 + ((n >> 8) & 255) * 587 + (n & 255) * 114) / 1000 < 140; };
  const svgUrl = (w, h, body) => 'data:image/svg+xml;utf8,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`);
  // Print grain, kept inside the shape it is applied to (so cut-outs stay transparent around the edges).
  const GRAIN = '<filter id="g"><feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .22 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>';

  // Flat printed poster: bold shapes, one optional label, a little print grain.
  P.art = (seed, cols, w = 480, h = 360, text = '') => {
    const r = rng(seed), [bg, a, b, c] = cols, m = Math.min(w, h);
    let s = `<defs>${GRAIN}</defs><rect width="${w}" height="${h}" fill="${bg}"/>`;
    switch (seed % 5) {
      case 0:
        s += `<circle cx="${w * (0.5 + r() * 0.2)}" cy="${h * 0.42}" r="${m * 0.3}" fill="${a}"/><rect y="${h * 0.66}" width="${w}" height="${h * 0.12}" fill="${b}"/><rect y="${h * 0.78}" width="${w}" height="${h * 0.22}" fill="${c}"/>`;
        break;
      case 1:
        for (let i = 0; i < 7; i++) s += `<rect x="${(i * w) / 7}" width="${w / 14}" height="${h}" fill="${i % 2 ? a : b}"/>`;
        s += `<circle cx="${w * 0.7}" cy="${h * 0.35}" r="${m * 0.18}" fill="${c}"/>`;
        break;
      case 2:
        [a, b, c].forEach((col, i) => { const aw = w / 4, x = w * 0.1 + i * (aw + w * 0.05), y = h * (0.35 + r() * 0.15); s += `<path d="M${x} ${h}V${y + aw / 2}a${aw / 2} ${aw / 2} 0 0 1 ${aw} 0V${h}z" fill="${col}"/>`; });
        break;
      case 3:
        s += `<rect width="${w * 0.58}" height="${h * 0.62}" y="${h * 0.38}" fill="${a}"/>`;
        for (let x = w * 0.62; x < w; x += m * 0.07) for (let y = h * 0.1; y < h * 0.9; y += m * 0.07) s += `<circle cx="${x}" cy="${y}" r="${m * 0.014}" fill="${c}"/>`;
        s += `<circle cx="${w * 0.3}" cy="${h * 0.26}" r="${m * 0.13}" fill="${b}"/>`;
        break;
      default:
        s += `<path d="M0 0H${w}V${h * 0.7}z" fill="${a}"/><circle cx="${w * 0.32}" cy="${h * 0.62}" r="${m * 0.2}" fill="${b}"/><rect x="${w * 0.66}" y="${h * 0.62}" width="${w * 0.2}" height="${h * 0.2}" fill="${c}"/>`;
    }
    if (text) s += `<text x="${w * 0.06}" y="${h * 0.9}" font-family="Helvetica Neue,Helvetica,Arial,sans-serif" font-weight="800" font-size="${m * 0.16}" letter-spacing="-1" fill="${isDark(bg) && seed % 5 !== 4 ? '#fff' : '#111'}">${text}</text>`;
    s += `<rect width="${w}" height="${h}" filter="url(#g)"/>`;
    return svgUrl(w, h, s);
  };
  // Transparent cut-out pieces, like shapes snipped from magazines.
  P.cutout = (kind, color) => {
    const body = {
      sun: `<defs>${GRAIN}</defs><circle cx="150" cy="150" r="146" fill="${color}"/><circle cx="150" cy="150" r="146" filter="url(#g)"/>`,
      star: `<path d="M150 8l22 96 96-30-68 74 68 74-96-30-22 96-22-96-96 30 68-74-68-74 96 30z" fill="${color}"/>`,
      leaf: `<path d="M20 280C20 120 120 20 280 20 280 180 180 280 20 280z" fill="${color}"/><path d="M40 260 250 50" stroke="#fff" stroke-opacity=".5" stroke-width="5"/>`,
      arch: `<path d="M30 290V150a120 120 0 0 1 240 0v140z" fill="${color}"/><path d="M90 290V160a60 60 0 0 1 120 0v130z" fill="#fff" fill-opacity=".25"/>`,
    }[kind];
    return svgUrl(300, 300, body);
  };

  P.PALETTES = {
    warm: ['#f3e9dc', '#e2603b', '#1f2a24', '#f2b544'],
    green: ['#e8f1e4', '#2f7d4f', '#a6d99b', '#14321f'],
    amber: ['#1c1408', '#f2a33a', '#ffe0a3', '#b8501e'],
    night: ['#0d1530', '#3d5afe', '#ff5a5f', '#f7d774'],
    red: ['#f7e6e1', '#d6372e', '#2b1b17', '#f29b8b'],
    teal: ['#e3f4f1', '#147a73', '#f2c14e', '#0e2e2b'],
    pastel: ['#f6f0ff', '#b79cff', '#ffb8e2', '#9fd8ff'],
    stone: ['#edeae3', '#8c8473', '#2e2b26', '#d9c9a8'],
    violet: ['#1a1033', '#8b5cf6', '#f25fc4', '#3ddc97'],
  };

  P.seed = async () => {
    const now = Date.now(), D = P.DAY, S = P.state, PAL = P.PALETTES;
    S.ideas = []; S.items = []; S.zc = 10; S.lastIdea = null;
    const idea = (name, kind, stage, days, o = {}) => {
      const i = { id: P.uid(), name, kind, stage, next: '', surface: 'dot', font: 'caveat', created: now - (days + 30) * D, touched: now - days * D, ...o };
      S.ideas.push(i); return i.id;
    };
    const add = (ideaId, type, x, y, w, h, o = {}, days = 3) => {
      const it = { id: P.uid(), ideaId, type, x, y, w, h, rot: 0, z: type === 'zone' ? 0 : ++S.zc, created: now - days * D - Math.random() * D * 0.5, tags: [], ...o };
      P.autoTag(it); S.items.push(it); return it;
    };
    const img = async (ideaId, x, y, w, seed, pal, ar, o = {}, days = 3) => {
      const { label, ...rest } = o;
      const info = await P.ingestImage(P.art(seed, pal, 480, Math.round(480 * ar), label || ''));
      return add(ideaId, 'image', x, y, w, Math.round(w * ar), { ...info, ...rest }, days);
    };
    const cut = async (ideaId, x, y, size, kind, color, o = {}, days = 3) => {
      const info = await P.ingestImage(P.cutout(kind, color));
      return add(ideaId, 'image', x, y, size, size, { ...info, ...o }, days);
    };
    const note = (id, x, y, text, c = 0, days = 3, o = {}) => add(id, 'note', x, y, o.w || 200, o.h || 200, { text, color: P.NOTE_COLORS[c], ...o }, days);
    const sw = (id, x, y, color, days = 5) => add(id, 'swatch', x, y, 96, 116, { color }, days);
    const zone = (id, x, y, w, h, label) => add(id, 'zone', x, y, w, h, { label }, 20);
    const link = (id, a, b, ends = 'dot') => add(id, 'arrow', 0, 0, 0, 0, { from: a.id, to: b.id, ends }, 2);
    const stroke = (id, pts, tool, color, size, days = 3) => {
      const s = tool === 'hl' ? { d: `M${pts[0].x} ${pts[0].y}L${pts[1].x} ${pts[1].y}`, b: { x1: Math.min(pts[0].x, pts[1].x), y1: Math.min(pts[0].y, pts[1].y), x2: Math.max(pts[0].x, pts[1].x), y2: Math.max(pts[0].y, pts[1].y) }, shape: 'line' } : P.ink.shape(pts);
      const g = P.ink.toItem([s], size / 2 + 4);
      return add(id, 'sketch', g.x, g.y, g.w, g.h, { ...g, tool, color, size }, days);
    };
    const speckle = (id, x, y, w, h, n, seed) => {
      const r = rng(seed), dots = [];
      for (let i = 0; i < n; i++) dots.push([x + r() * w, y + r() * h, 0.6 + r() * 1.8]);
      const b = { x1: x, y1: y, x2: x + w, y2: y + h };
      const g = P.ink.toItem([{ d: P.ink.dots(dots), b, shape: 'free' }], 4);
      return add(id, 'sketch', g.x, g.y, g.w, g.h, { ...g, tool: 'spray', color: '#1d1b18', size: 20 }, 6);
    };

    // ---- Gym + café: sections, stickies, a live page, a labelled connector ----
    const gym = idea('Gym + café', 'Business', 'Doing', 1, { next: 'Visit two spaces in Indiranagar' });
    zone(gym, 0, 0, 780, 340, 'Space & mood');
    await img(gym, 32, 44, 280, 10, PAL.warm, 0.72, { why: 'raw concrete + warm light', src: 'https://designinspo.example/boutique-gyms' }, 9);
    await img(gym, 344, 44, 170, 16, PAL.green, 1.3, { why: 'plants everywhere' }, 8);
    await img(gym, 546, 44, 200, 13, PAL.amber, 1, { label: 'OPEN 6AM', ocr: 'OPEN 6AM' }, 6);
    zone(gym, 820, 0, 470, 360, 'Brand');
    ['#1f2a24', '#e2603b', '#e9e4da', '#7a8b5a'].forEach((c, i) => sw(gym, 852 + i * 104, 44, c));
    add(gym, 'type', 852, 196, 220, 124, { text: 'Lift & Latte', face: 'serif' }, 5);
    note(gym, 1092, 196, 'Name ideas:\nLift & Latte\nRep Café\nGround Floor', 1, 5, { w: 170, h: 150 });
    zone(gym, 0, 420, 1290, 300, 'Concept & money');
    const n1 = note(gym, 32, 464, 'Café at the front, gym behind glass. People see the energy while they wait for coffee.', 0, 7);
    const n2 = note(gym, 280, 464, 'Membership 2.5k a month. Café open to the public = second income.', 3, 4);
    note(gym, 528, 464, 'Break-even at ~180 members?', 2, 2);
    note(gym, 776, 464, 'Morning-only membership for people who work from home', 1, 2);
    add(gym, 'web', 1024, 452, 240, 236, { url: 'https://en.wikipedia.org/wiki/Third_place', title: 'Third place' }, 2);
    const lb = add(gym, 'label', 330, 770, 132, 28, { text: 'the real business?' }, 2);
    link(gym, n1, n2);
    link(gym, n2, lb);

    // ---- Night bus: collage, typewriter letter, highlighter, labels, speckles ----
    const film = idea('Night bus', 'Film', 'Exploring', 3, { font: 'reenie', surface: 'paper', next: 'Write the last scene first' });
    const poster = await img(film, 0, 0, 300, 15, PAL.night, 0.66, { label: 'NIGHT BUS', ocr: 'NIGHT BUS', why: 'title card mood' }, 16);
    await cut(film, 222, -54, 128, 'sun', '#e0392b', { why: '' }, 15);
    add(film, 'tape', -26, -10, 104, 28, { color: P.TAPES[0], rot: -14 }, 15);
    await img(film, 372, 18, 180, 21, PAL.red, 1.2, { why: 'tail lights in rain' }, 12);
    add(film, 'tape', 420, 4, 84, 26, { color: P.TAPES[3], rot: 4 }, 12);
    speckle(film, -60, -80, 660, 380, 140, 7);
    const letter = add(film, 'text', 0, 300, 540, 210, { font: 'type', text: 'Dear me,\nWhat if the whole film is one night route? Every passenger is someone the conductor once let down. Sodium light outside, tube light inside. Almost no dialogue for the first ten minutes.' }, 10);
    // Highlights sit on measured text positions for the typewriter face at 18px.
    stroke(film, [{ x: 236, y: 344 }, { x: 390, y: 344 }], 'hl', '#ffd23f', 22, 10);
    stroke(film, [{ x: 384, y: 399 }, { x: 486, y: 399 }], 'hl', '#f25fc4', 22, 10);
    const l1 = add(film, 'label', 640, 330, 70, 28, { text: 'logline' }, 9);
    const l2 = add(film, 'label', 110, -150, 90, 28, { text: 'the look', light: true }, 9);
    link(film, letter, l1);
    link(film, l2, poster);
    note(film, 640, 420, 'Ending: he drives the empty bus home at dawn.', 2, 11);
    ['#0d1530', '#e0392b', '#f7d774'].forEach((c, i) => sw(film, i * 108, 560, c, 12));

    // ---- One habit ----
    const app = idea('One habit', 'App', 'Spark', 6, { font: 'kalam' });
    note(app, 0, 0, 'Only one habit at a time. Unlock the next after 21 days.', 0, 6);
    note(app, 232, 24, "No streak shame. Missing a day bends the line, it doesn't break it.", 5, 6);
    await img(app, 10, 240, 190, 31, PAL.pastel, 1.5, { why: 'soft, calm home screen' }, 6);
    sw(app, 240, 260, '#b79cff', 6); sw(app, 348, 260, '#ffb8e2', 6);
    add(app, 'type', 240, 404, 204, 120, { text: 'one.', face: 'round' }, 6);
    await cut(app, 380, 186, 96, 'star', '#f25fc4', {}, 6);

    // ---- resting ideas ----
    const pod = idea('Side-project podcast', 'Other', 'Parked', 41, { font: 'shadows' });
    note(pod, 0, 0, '20-minute chats with people who shipped something on weekends.', 1, 45);
    note(pod, 232, 20, 'First guests: Ravi (game), Meera (zine), Arjun (bike rack)', 3, 44);
    await img(pod, 40, 240, 220, 44, PAL.violet, 1, { label: 'EP. 01', ocr: 'EP. 01' }, 43);

    const scr = idea('The lighthouse', 'Script', 'Exploring', 24);
    ['Act 1', 'Act 2', 'Act 3'].forEach((a, i) => zone(scr, i * 300, 0, 270, 520, a));
    note(scr, 34, 40, 'Keeper finds a second set of footprints.', 0, 30);
    note(scr, 34, 270, 'Supply boat is three days late.', 6, 29);
    note(scr, 334, 40, 'The light starts answering back.', 4, 27);
    await img(scr, 344, 280, 180, 52, PAL.stone, 1, { why: 'fog, no horizon' }, 26);
    note(scr, 634, 40, 'He was the one signalling all along.', 2, 25);

    // ---- Pile ----
    add(null, 'note', 0, 0, 200, 200, { text: 'Rooftop cinema nights for apartment complexes?', color: P.NOTE_COLORS[0] }, 0);
    await img(null, 0, 0, 220, 23, PAL.amber, 0.7, { why: 'this grain' }, 1);
    add(null, 'link', 0, 0, 240, 72, { title: 'How self-healing cutting mats work', src: 'https://makerdesk.example/cutting-mats' }, 2);

    S.lastIdea = gym;
  };
})();
