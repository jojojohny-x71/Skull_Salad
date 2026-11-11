# Skull Salad: an idea sketchbook for Mac

Name: **Skull Salad** (earlier working name: Pile). "Pile" now means only the inbox of unfiled captures.

## Design direction (revised after the first prototype)

The first prototype was too heavy: dark, a sidebar, an inspector panel, a fake menu bar, handwriting on the interface itself. The direction now, which supersedes the look and layout sections below:

- **A giant sketchbook, not a whiteboard and not a book UI.** Anything you can do in a sketchbook works: draw (pen, marker, pencil, highlighter, spray), erase, write anywhere, sticky notes, collage with lasso cut-outs, washi tape, black pill labels on dot-ended leader lines, sections. Plus live websites and video on the page.
- **Light, warm paper** with dots, grid or plain; colour accents from the logo (indigo for selection and buttons, pink and green for stickies and tape).
- **Handwriting only for what you write** (stickies, writing, captions). Every label, menu and button uses the system font. Typewriter and plain faces are optional per item.
- **Minimal chrome:** a small cluster of pills top-centre (home, idea name, search, AI, Capture), a slim tool rail on the left with a round brush wheel, and options floating above the selection. No sidebar or inspector.
- **Home is frosted glass folders** on paper, one per idea; the Pile is the dark folder.
- **⌘K** search palette for retrieval across everything.

## Context

Ideas arrive at random (an app, a film, a script, a gym business) and get lost. Past tools (Notes, Notion, Pinterest, Figma boards) failed for four reasons: they were repurposed and not native, things couldn't be found again, content was scattered across apps, and upkeep became a chore.

Pile is a native-feeling Mac workbench with two jobs: **dump an idea in seconds** and **get it back fast**. Each idea gets one home for every kind of media, laid out on a free canvas, and needs no maintenance to stay useful.

Agreed sequence: ideate (done), plan (this file), HTML prototype, approval, native Mac app, then plugins, then iPhone app.

## Principles

1. Capture in under three seconds, without leaving what you're doing.
2. Retrieval is the headline feature: by words, by look, by idea, by time.
3. One home per idea for images, video, links, notes, sketches and voice.
4. Zero required upkeep: no mandatory tags or folders; the app auto-tags and auto-places.
5. Mac chrome follows Apple's conventions; the canvas and folders carry the personality.

## Look and feel

- **Home**: frosted-glass folders, one per idea, with the latest images peeking out of the top; shows name, stage and last-touched date, and a + button to dump straight in. Search bar above.
- **Canvas surface**: black dot grid by default; cutting mat green and warm paper as per-idea options.
- **Items**: subtle texture. Clean cards, soft shadows, slight rotation. Hand-drawn scribbles and arrows. No torn edges or paper clips.
- **Handwritten fonts** for idea names, sticky notes, zone labels, annotations and the "why I saved it" line. Three or four hands to choose from (Caveat, Kalam, Reenie Beanie, Shadows Into Light), set per idea or per note.
- **System font** for toolbar, sidebar, search and results, inspector and long text. Any note can be switched to it.
- **Chrome**: translucent sidebar and toolbar, standard window controls, standard Mac shortcuts.

## Structure

| Place | Purpose |
|---|---|
| **Home** | Glass folders for active ideas, global search, and a "Haven't touched in a while" row. |
| **Idea canvas** | Free Figma-style workspace per idea, opened exactly as left. |
| **Pile** | Inbox for captures with no idea chosen. Drag onto a folder to file. |
| **Library** | Every item from every idea in one visual grid with filters and a timeline. |

**Idea properties**: name, kind (App, Film, Script, Business, Other), stage (Spark, Exploring, Doing, Parked), optional next step, surface, handwriting font.

**Item types**: image, video file, link card, sticky note, text block, sketch, colour swatch, type sample, arrow, zone (labelled group).

**Templates**: Blank, Moodboard, Stylescape (strip of palette, type, imagery, texture), Script beats, Business canvas.

## Use cases

### Dumping

- **One capture panel, four modes**: type a sentence, grab what's on screen, sketch, speak.
- **Idea picker in one keystroke**: type-ahead with the last-used idea preselected. Skipping it sends the item to the Pile.
- **Grabs keep**: the visual, the source link, a skippable one-line "why I saved it", and an offline copy (page text, or your own video file).
- **Voice**: saved as tidied text; audio discarded.
- **Sketch**: trackpad or mouse. Strokes are smoothed; obvious circles, boxes, arrows and lines snap clean.
- **Browsing sprees**: pick the idea once, then each save is one silent click with a small tick.
- **Mid-work**: the panel never steals focus from the app you're in and closes on Enter.
- **Arrival**: a new item auto-places in an "Unsorted" zone on that idea's canvas, in free space near your last view.

### Capture routes

- Global hotkey panel.
- Menu bar drop zone and region screenshot.
- Paste and drag-drop onto a folder, the Pile or a canvas.
- Browser extension (Chrome and Safari): right-click save with source link.
- Pinterest import of your own boards.
- Mac Share menu.
- Video: your own files stored in full. Streaming-site links saved as link, thumbnail and timestamped notes only; no downloading from those sites.

### Retrieving

- **Words**: note text, link titles, tags, saved page text; later, text inside images and handwriting.
- **Look**: visual grid, colour filter; later, "find things that look like this".
- **Idea**: filter by idea, kind or stage.
- **Time**: a timeline scrubber ("last week", "around Diwali").
- Auto-tags by type and source; manual tags optional.

### Keeping ideas alive

- Stage and next step on every folder so live ideas stand out.
- "Haven't touched in a while" row resurfaces forgotten ideas.

### Working with AI

The Mac app runs a local MCP server so Claude or another assistant can:

- read, search and summarise your ideas;
- add notes, references or outlines to a board, marked AI-added;
- propose organisation (cluster Unsorted, suggest tags, file Pile items), applied only when you approve;
- develop a board into a brief, script outline, business plan or next steps, saved back as a note.

### Output

Mainly personal. Copy items out to Figma, Notion or a doc; export notes as text. Image/PDF export and presenting are not needed now.

## Storage

- Local only on the Mac: plain files in one folder, works offline, no account.
- Laid out so a later move to synced storage (for the iPhone app) does not need a rewrite.

## Phase 1: HTML prototype (next)

A working single-page app, no build step, in `prototype/` inside the session folder.

**Files**

- `prototype/index.html`: window shell (controls, toolbar, sidebar, main area, inspector).
- `prototype/styles.css`: tokens, materials, glass folders, item styles, fonts.
- `prototype/js/store.js`: data model, IndexedDB persistence (images as blobs), undo history.
- `prototype/js/home.js`: glass folders, stages, forgotten row, new-idea sheet.
- `prototype/js/canvas.js`: pan, zoom, select, drag, resize, rotate, sketch with smoothing, arrows, zones, auto-placement.
- `prototype/js/capture.js`: capture panel (four modes, idea picker), paste, drag-drop, silent-save mode, simulated flows.
- `prototype/js/library.js`: grid, search, filters, colour extraction, timeline.
- `prototype/js/seed.js`: sample ideas with generated placeholder imagery.

**Real in the prototype**

- Home with glass folders; create, rename, delete ideas; set kind, stage, next step, surface and font.
- Canvas: pan, zoom, marquee select, move, resize, rotate, layer order, duplicate, delete, undo/redo.
- Notes, text, swatches, type samples, smoothed sketches, arrows, zones, templates.
- Capture panel on a shortcut with the idea picker; paste and drag-drop of images, links and text.
- Auto-placement into the Unsorted zone.
- Search by words, colour, idea, kind, stage and time across everything.
- Local persistence across reloads.

**Simulated, and labelled as such**

- System-wide hotkey, menu bar drop zone, region screenshot.
- Browser extension and silent-save spree (a fake web page with "Save to Pile").
- Pinterest import (sample boards).
- Voice: browser speech recognition with a basic cleanup, standing in for on-device tidying.
- AI panel: a mock-up showing the read, add, organise and develop actions.
- Text-in-image and look-alike search.

**Design rules applied** (apple-design skill plus macOS conventions)

- Press feedback on pointer-down (`scale(0.97)`, 100ms).
- Dragging is 1:1 with the pointer, keeps grab offset, uses pointer capture; release velocity carries into a short settle.
- Spring-style motion; panels grow from their trigger and leave the same way; nothing blocks input mid-animation.
- Capture panel is non-modal (no scrim); delete and import are sheets (with scrim).
- Translucent materials via `backdrop-filter`, darker for sidebar, lighter for floating controls; never light glass on light glass.
- Only `transform` and `opacity` animate.
- `prefers-reduced-motion`, `prefers-reduced-transparency`, `prefers-contrast` handled.
- Shortcuts: ⌘N new idea, ⌘F search, ⌘Z / ⇧⌘Z, ⌘D duplicate, ⌫ delete, ⌘0 fit, ⌘+ / ⌘−.

Note: Apple's guideline pages returned no content when fetched (they render client-side), so the chrome follows existing knowledge of those guidelines. Check it by eye at review.

**Verification**

- Serve `prototype/` locally and open it in the browser pane.
- Core loop: capture a note into an idea with the picker, paste an image, confirm both auto-placed in Unsorted, arrange, sketch, connect with an arrow, reload and confirm persistence.
- Retrieval: find those items by word, by colour, by idea and on the timeline.
- Open, use and close each simulated flow.
- Check at 1280×800, with reduced motion on, and read the console for errors.
- Send screenshots of Home, a canvas, Library and the capture panel for review.

## Phase 2: native Mac app (after prototype approval; detailed plan then)

- SwiftUI with an AppKit-backed canvas.
- Real global hotkey panel, menu bar item, region screenshot, Share menu extension.
- On-device speech-to-text with tidying; text-in-image and handwriting search (Vision); look-alike search; Spotlight indexing.
- Plain-file storage in a single folder.

## Phase 3: plugins and AI

- Chrome and Safari extension talking to the app locally, including silent-save mode.
- Pinterest import (needs a Pinterest developer app and your sign-in).
- Local MCP server with read, add, organise (with approval) and develop tools.

## Phase 4: iPhone companion app

- Capture and browse on the phone.
- Moves storage from local-only to synced.

## Out of scope for now

Collaboration, image/PDF export, presentation mode, downloading video from streaming sites.
