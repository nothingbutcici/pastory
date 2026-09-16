<p align="center">
  <img src="Resources/Logo.png" width="104" alt="Pastory">
</p>

<h1 align="center">Pastory</h1>

<p align="center"><b>Pastory = Paste + History</b> · <a href="README.zh.md">中文</a></p>

<p align="center">
  <img src="docs/images/shelf-en.png" alt="The Pastory clipboard" width="920">
</p>

Everything on your computer has a history. Except the clipboard. It only remembers the last thing.

You press ⌘C dozens of times a day. More than half of those are things you've copied before.

So the stuff you use most — the prompt that finally worked, that link you meant to keep, the screenshot, the client's address, the invoice details — vanishes the moment you copy the next thing.

Pastory gives the clipboard a long-term memory: everything you copy — text, links, images, screenshots, recordings — lives in one panel where you can find it and use it again.

- Pin what you use often. Pinned items survive any cleanup schedule.
- Give important items a title so you recognize them at a glance.
- Click to copy, double-click to paste straight into the app you were in.

Everything stays on your Mac. No account, no network, your data is 100% yours.

## Install

macOS 15 or later, Intel or Apple silicon.

1. Download the [latest zip](../../releases/latest), unzip, drag `Pastory.app` into Applications.
2. Open it. A handwritten **P** appears in the menu bar and the clipboard panel opens once by itself. (Builds are notarized by Apple — no security warnings.)
3. The first screenshot asks for **Screen Recording** permission; turn it on and reopen Pastory.

Default shortcuts: **⌥⌘S** screenshot / record, **⇧⌘V** clipboard. Both can be changed in Settings.

Optional: with **Accessibility** permission, double-clicking a card pastes it straight into the app you came from; without it, double-click copies and closes.

Pastory tells you when a new version is out; one click updates it in place.

---

## Why I built it

### The clipboard — the real need

I copy text and take screenshots many times a day, and a good share of those are things I already did an hour ago (ADHD). Repeat, repeat, repeat.

The useful bits ended up in Notes sometimes, in Obsidian other times. Scattered everywhere.

So — this little app.

Every copy, screenshots included, lands in one place, waiting to be looked at again, reused, or edited.

Power move: if what you copy is information-dense, let an agent read your Pastory database now and then and turn it into a reviewable markdown knowledge base.

### Screenshots (a small indulgence)

I used two screenshot tools at once.

WeChat's shifts the colors, but I love its text recognition, so I'd call it when I needed the words.

Feishu's keeps the colors right and can record MP4 / GIF, so I'd call it for those.

Which shortcut to press was a decision I had to make every single time.

Both can annotate, but neither looks nice doing it. I care about how the font and the text box look while I'm marking something up (I need my small joys).

So Pastory folds all of that into one tool.

## What it does

### Clipboard history

Open it with a shortcut of your choosing or from the menu bar. Everything you copied is a card, with the app it came from and the time.

- **Copy:** click any card and it's on your clipboard, ready to paste.
- **Copy and paste in one go:** double-click a card and it lands in the input field of the app you were in.
- **Search:** by keyword, across text, titles, and the words recognized inside images.
- **Pin to keep:** pinned items stay for good; unpinned ones are cleaned up on a schedule you set.
- **Titles:** name the important ones so you spot them instantly.
- **Edit in place:** text and images can be edited; the result replaces the original on the same card.
- **Screenshots from other tools:** WeChat, Feishu, the system — anything that reaches the clipboard gets a card, searchable, pinnable, annotatable.

### Screenshot & recording

<p align="center"><img src="docs/images/capture-en.png" alt="Capture and annotation" width="920"></p>

Press your shortcut to capture or record.

Colors are taken in the display's own color space, so nothing shifts.

**Annotations look like Obsidian's Excalidraw plugin** (if you've used it, you'll smile): rectangle, ellipse, arrow, line, pen, text, mosaic, in seven low-saturation colors. Pictures you send out will look good.

**Recognize text:** Apple's on-device OCR; the recognized text is stored with the image so you can find it later.

**Record:** MP4 or GIF — pick the format after recording.

## Why you might want it

**Shipping addresses, invoice details, the sentences you type every day.**
We've all dug through chat history for the same piece of information again and again.

With Pastory: copy it once, title it "Client A address" or "Company invoice", pin it. Next time, double-click and it's pasted.

**Prompts that worked, links worth keeping.**
The moment you copy it, it's in Pastory — no need to force a "save it to notes" habit. And no more scrolling back through fifty turns of conversation wondering which session it was in.

With Pastory: search a keyword, it's there.

**A visual reference board.**
When you vibe-code a product, visuals matter. I used to screenshot references frantically and file each one by hand — ten seconds a picture, at least.

With Pastory: screenshot, and they line up in a row to compare and choose from. Pin the ones you like, annotate when needed, and save to disk — always a full-resolution PNG.

## Privacy

- Everything lives in `~/Library/Application Support/Pastory/`: plain files plus one SQLite index. Look at it, back it up, copy it to another Mac and import it.
- No account, no analytics. The only network request is a daily update check; it carries no identifier and can be turned off in Settings.
- Items that password managers mark as concealed are never recorded.

## Build from source

```
git clone https://github.com/nothingbutcici/pastory.git
cd pastory
./build.sh          # → build/Pastory.app
```

Swift Package Manager, Apple frameworks only. Project conventions live in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Credits & license

Typefaces [Caveat](https://fonts.google.com/specimen/Caveat) and [Ysabeau Office](https://fonts.google.com/specimen/Ysabeau+Office) (SIL Open Font License). Interaction inspired by [Paste](https://pasteapp.io); annotation style after [Excalidraw](https://excalidraw.com).

MIT License · © 2026 nothingbutcici
