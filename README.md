# Skull Salad: HTML prototype

An endless sketchbook for every idea you have: dump it in seconds, make sense of it on the page, find it again fast. The full product plan is in `PLAN.md`.

## Open it

Double-click `prototype/index.html` (Chrome works best). Everything you add is saved in that browser on this Mac.

If it doesn't load properly from the file, serve it from Terminal instead, then open http://localhost:8731:

```bash
python3 -m http.server 8731 --directory ~/Downloads/"SKULL SALAD"/prototype
```

**Logo:** the app uses `prototype/assets/logo.png` if it exists, otherwise a simple vector version of the logo. Save your logo there to use the real one.

## What you can do on a page

| Tool | Key | What it does |
|---|---|---|
| Select | V | Move, resize, rotate (⇧ snaps), marquee-select. Release fast and things glide. |
| Hand | H or hold Space | Pan. Pinch or ⌘-scroll to zoom, ⌘0 to fit. |
| Draw | P | Pen, marker, pencil, highlighter and spray from the brush wheel. 1, 2, 3 set size. Hold still at the end of a stroke to snap it to a clean line, box or circle. |
| Eraser | E | Rub out strokes. |
| Write | T or double-click | Your handwriting, anywhere. Switch any text to Typewriter or Plain from the bar above it. |
| Sticky | S | Square stickies in your handwriting (try the Permanent Marker hand). |
| Label | L | Black or white pill labels for annotating. |
| Connector | X | Drag from one thing to another. Dot ends or arrow. |
| Section | F | Group part of a page under a name. |
| Tape | G | Drag to lay a strip of washi tape. |
| Media | I | Image or video files, live websites, YouTube and Vimeo. Double-click a page or video to use it. |

Select an image and use the scissors to cut it out with a lasso; its shadow follows the cut. Undo cut puts it back.

## Capture and search

- **⌥Space** opens quick capture: Write, Grab, Sketch or Speak. `#gym` files it into that idea; an unknown `#tag` starts a new idea. It lands in the idea's Unsorted section.
- **Paste or drop** images, links and text onto a page, a folder or the capture panel.
- **⌘K** searches everything: words, colours ("orange"), idea names and time ("last week").
- The arrow next to **Capture** has previews of the browser extension, Pinterest import, screenshots and menu bar drop zones.
- **✦** opens the AI panel (summarise, outline, tidy, brief).

## Real vs preview

Real: folders, pages, every tool above, cut-outs, live web pages and video, search, undo/redo, local saving, copy and export as text.

Previews of Mac app and plugin features: the system-wide hotkey, menu bar, region screenshots, browser extension, Pinterest, text inside images, and the AI panel (simple rules standing in for an assistant connected through a local MCP server). Voice uses the browser's speech recognition in place of on-device transcription. A few websites refuse to be shown inside other pages; open those with the ↗ button.

## Mac app

`mac/` is the native Mac app (SwiftUI), built from the Figma frame "MacBook Pro 14' - 1". So far:

- **Launch:** the app opens like Discord. A small splash card (the Figma frame "Frame 1") appears in the middle of the screen and plays the logo loader from `brand/loader`, the same motion as the web version. The bowl lands, the leaves sprout and the skull pops up, then the salad makes one big toss while the bar fills. Then the logo bursts apart, the card fades and the main window fades in behind it. It takes about 2.5 s; a click, Return, Space or Esc skips it. With Reduce Motion on, it fades instead.
- **Home:** a slightly grey canvas floating in a black window frame, with the 10-point dot grid shown through the design's radial mask (hovering brightens the dots around the pointer) and your projects on an invisible grid. The grid reflows to fit the window and scrolls once it's taller than the window. There are two kinds of project:
  - **Idea** (brainstorming and moodboards): a bundle of about fifteen loose sheets held by a steel paper clip. Plain, aged, graph, lined, yellow legal and kraft sheets and a glossy photo fan out underneath, edges stepping out on every side, the deeper ones a little darker. The dotted top sheet has the name stamped in heavy ink with a lime star sticker behind it, a "BY YOU" ring, a highlighted "TYPE: IDEA" and a typewritten date. On hover the top sheet lifts off the stack.
  - **Book** (notes to remember and summarise): a spiral notebook with a coated grey card cover, the name printed big in white, page edges showing, and a glossy green plastic coil looping through punched holes. On hover the cover lifts.

  Both are real 3D objects (`mac/Sources/Objects.swift`), not drawings. Each is modelled in SceneKit (curled sheets of grainy paper, a wire clip, a card cover, a plastic coil), lit by a soft key light and a studio environment, and rendered with cast shadows. The name and date are printed into the paper and card textures. Renders happen in the background and are kept while the app runs.

  Drag a project to rearrange; the others slide aside to show where it will land. The dashed **+ New** tile at the end of the grid (or ⌘N) asks Idea or Book and adds an "Untitled" one. Projects and their order are saved between launches. Right-click a project to rename or delete it (⌘⌫ also deletes, after a confirmation).
- **Empty Home:** with no projects (as on a first launch), Home shows a die-cut sticker instead: "GO MAKE SOMETHING *f\*\*\*ing* GREAT" in chunky outlined capitals with "f\*\*\*ing" in pink script, and a "+ new idea or book" pill below it that opens the same chooser. Three keycap stickers and the Skull Salad mark are stuck around it, and they pop on one after another (they just appear with Reduce Motion on).
- **Quote skull:** the pink skull from the logo sits in the bottom-left corner of Home with a speech bubble. It says the notes you write in a project called "Quotes" (rename a project from its right-click menu); until there is one, it says a few lines of its own. Click it for the next quote; it also moves on every two minutes.
- **Workbench:** double-click a project (or select it and press Return) and it grows into a black-and-white cutting mat with a barely visible half-inch grid. The mat is always exactly as wide as the window (no sideways scrolling) and never ends downwards: it grows as you scroll. The ruler across the top stays pinned, and the rulers down each side scroll with the mat and keep counting inches. Go back with the breadcrumb, Esc, ⌘[ or ⌘↑.
- **Tool tray:** docked along the bottom edge of every folder, like the tray on a drawing desk. On the left the tools stand up out of it (the one in use rises higher): **Select** (V), a round black puck; **Write** (T), a felt-tip marker; **Highlighter** (H), a fat fluorescent marker. On the right sit the settings for what you're using: the face (Handwriting, Typewriter, Plain), weight (regular to bold), size (− / +) and ink of the selected note, or of the next one when nothing is selected (new notes start in whatever you used last); with the highlighter in hand, its five colours. A trash button appears when something is selected.
- **Notes:** pick the marker (or press T), click anywhere on the mat and type. The default face is Caveat (bundled in `mac/Resources/Fonts`, SIL Open Font License). Notes grow sideways as you type and wrap at about 6 inches. Click away or press Esc to finish; an empty note is thrown away. Drag a note to move it, double-click to edit it, select it and press ⌫ to delete it.
- **Highlighter:** pick it (or press H) and sweep across the mat; the stroke sits under the writing so the ink stays crisp, and a nearly straight sweep snaps straight. Click a stroke with Select to pick it, ⌫ to delete it. Notes and strokes are saved with each folder.
- **Side toolbar:** a black pill on the right of every folder with Select, Pencil, Fill and Eraser; the chosen one sits in a white circle and each shows its name on hover. A placeholder for now: picking one only moves the highlight.

Rebuild and reinstall after changes (no Xcode needed, only the Command Line Tools):

```bash
~/Downloads/"SKULL SALAD"/mac/install.sh
```

It installs to `~/Applications/Skull Salad.app` (or `/Applications` when that folder is writable) and opens it. `mac/snapshots/` holds offscreen renders at the design's size; regenerate one with `~/Applications/"Skull Salad.app"/Contents/MacOS/SkullSalad --snapshot out.png [--hover x,y]`. `--empty` renders Home with no projects; `--launch 1.5` renders the splash card 1.5 s into its loader instead; add `--exit-at 2.06` as well to catch its exit. The install script deletes its build copy afterwards, so only one Skull Salad shows up in Launchpad.

## Files

- `PLAN.md`: the product plan.
- `prototype/`: the app (`index.html`, `styles.css`, `js/`, `assets/`).
- `screenshots/`: Home, a sketchbook page, a structured board, search and quick capture.
