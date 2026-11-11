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

- **Home:** a slightly grey canvas floating in a black window frame, with the 10-point dot grid shown through the design's radial mask (hovering brightens the dots around the pointer) and one placeholder folder, "Untitled".
- **Workbench:** double-click the folder (or select it and press Return) and it grows into a black-and-white cutting mat: ruler ticks and inch numbers round the edge, a barely visible half-inch grid. Go back with the breadcrumb, Esc, ⌘[ or ⌘↑.
- **Floating toolbar:** a placeholder for the tools to come.

Rebuild and reinstall after changes (no Xcode needed, only the Command Line Tools):

```bash
~/Downloads/"SKULL SALAD"/mac/install.sh
```

It installs to `~/Applications/Skull Salad.app` (or `/Applications` when that folder is writable) and opens it. `mac/snapshots/` holds offscreen renders at the design's size; regenerate one with `~/Applications/"Skull Salad.app"/Contents/MacOS/SkullSalad --snapshot out.png [--hover x,y]`. The install script deletes its build copy afterwards, so only one Skull Salad shows up in Launchpad.

## Files

- `PLAN.md`: the product plan.
- `prototype/`: the app (`index.html`, `styles.css`, `js/`, `assets/`).
- `screenshots/`: Home, a sketchbook page, a structured board, search and quick capture.
