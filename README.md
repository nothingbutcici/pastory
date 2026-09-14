<p align="center">
  <img src="Resources/Logo.png" width="96" alt="Pastory">
</p>

<h1 align="center">Pastory</h1>

<p align="center">
  Screenshots, screen recordings and everything you copy — kept on a paper shelf at the bottom of your Mac.<br>
  <a href="README.zh.md">中文说明</a>
</p>

<p align="center">
  <img src="docs/images/shelf-en.png" alt="The Pastory shelf" width="900">
</p>

Pastory is a small menu-bar app for macOS that does two things and does them together:

- **Capture** — press a shortcut, drag a region (or pick a window, or the whole screen), annotate with hand-drawn shapes, recognize text, or record the region as MP4 / GIF. The result goes straight to your clipboard.
- **Remember** — every copy you make, including those captures, lands on a shelf you can open with another shortcut. Click a card to copy it back. Pin what matters; the rest is cleaned up on a schedule you choose.

Everything stays on your Mac. No account, no network, no telemetry.

## Features

**Capture**
- Region / window / full-screen picker with resize handles; the front app keeps its menus and popovers open while you pick.
- Color-accurate: captures in the display's own color space (Display P3 stays P3, nothing is squashed to sRGB).
- Excalidraw-style annotations: rectangle, ellipse, arrow, line, pen, text, mosaic — seven colors, three weights, drag to move, handles to reshape.
- Text recognition (Vision, on-device) for Chinese and English; the text is editable before you copy it.
- Screen recording of the same region to MP4, or GIF with a size budget, with a preview before anything is copied.

**Shelf**
- Cards for text, links, images, files and recordings, with the source app and time. Search across text, titles and recognized text inside images.
- Click = copy and stay, double-click or ⏎ = copy and close, Space = Quick Look.
- Pin, give a card a handwritten title, edit text in place, re-annotate an image, save anything to disk.
- Screenshots from other tools (WeChat, Feishu, CleanShot…) are recognized as images too, thumbnail and OCR included.
- Copying something you copied before brings the old card back instead of making a twin.

**Retention you can reason about**
- Unpinned items live for *N* days (1 / 3 / 7 / 30 / 365 / forever), counted in calendar days with a cleanup time you set (04:00 by default). Pinned items are never auto-deleted. Deleting something by hand is final.

**Import**
- Bring history over from another clipboard manager's SQLite database (Paste is read exactly; other Core Data / SQLite layouts heuristically) or from a Pastory folder on another Mac. Imported history sorts behind your own.

**Bilingual** — 中文 / English, following the system or set in Settings.

<p align="center">
  <img src="docs/images/capture-en.png" alt="Capture and annotation" width="900">
</p>

## Install

Requires macOS 15 (Sequoia) or later, Intel or Apple silicon.

1. Download `Pastory-<version>.zip` from [Releases](../../releases), unzip, drag `Pastory.app` into Applications.
2. Open it. Until the app is notarized, macOS will say it cannot verify the app: click Done, then System Settings › Privacy & Security › **Open Anyway** (once).
3. Pastory has no main window — look for the handwritten **P** in the menu bar. The shelf opens by itself on first launch.
4. The first screenshot asks for Screen Recording permission; turn Pastory on and relaunch it.

Default shortcuts: **⌥⌘S** screenshot / record, **⇧⌘V** shelf, **⌥⌘F** shelf with search focused. Change them in the shelf › Settings.

## Where your data is

`~/Library/Application Support/Pastory/`

| | |
|---|---|
| `pastory.sqlite` | the index (SQLite, WAL): kind, time, source app, preview, recognized text, pin, title, content hash |
| `items/<id>.<ext>` | the payloads themselves — `.txt`, `.png`, `.mp4`, `.gif`, or a JSON list of file paths |
| `thumbs/<id>.png` | thumbnails for the shelf |

Plain files on purpose: you can look at them in Finder, back them up, or copy the folder to another Mac and import it.

## Build from source

```
git clone https://github.com/nothingbutcici/pastory.git
cd pastory
./build.sh          # → build/Pastory.app (this machine's architecture)
./dist.sh           # → dist/Pastory-<version>.zip (universal binary, first-open notes)
```

Swift Package Manager, macOS 15 SDK, Apple frameworks only (ScreenCaptureKit, Vision, AVFoundation, SQLite). `build.sh` signs with a local self-signed certificate when one exists (`tools/make-signing-cert.sh` creates it) so the Screen Recording permission survives rebuilds.

Offscreen self-tests render every surface and exercise retention, clipboard ingestion and import without touching your real data — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), which is also the project's rulebook (storage rules, retention rules, visual system, conventions).

## Privacy

Pastory reads the general pasteboard twice a second (it checks one integer, the change count, and only reads content when it changed). It skips items marked concealed or transient by password managers. Nothing leaves the machine.

## Acknowledgements

Typefaces: [Caveat](https://fonts.google.com/specimen/Caveat) and [Ysabeau Office](https://fonts.google.com/specimen/Ysabeau+Office) (SIL Open Font License, bundled in `Resources/Fonts`), Songti SC and HanziPen SC from macOS.
