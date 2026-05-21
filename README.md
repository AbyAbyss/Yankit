<p align="center">
  <img src="docs/banner.svg" alt="Yankit" width="1200">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-1b1b1b?logo=apple&logoColor=white" alt="Platform: macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-AppKit-2396F3?logo=swift&logoColor=white" alt="SwiftUI + AppKit">
  <img src="https://img.shields.io/badge/license-MIT-3da639" alt="License: MIT">
  <img src="https://img.shields.io/badge/status-feature%20complete-22c55e" alt="Status: feature complete">
</p>

<p align="center">
  A fast, free, open-source clipboard manager for macOS —<br>
  it remembers the <b>text</b>, <b>images</b>, and <b>files</b> you copy, and pastes any of them back with <b>⌘⇧V</b>.
</p>

<p align="center">
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#how-it-works">How it works</a> &nbsp;·&nbsp;
  <a href="#requirements">Requirements</a> &nbsp;·&nbsp;
  <a href="#build-and-run">Build</a> &nbsp;·&nbsp;
  <a href="#keyboard-shortcuts">Shortcuts</a> &nbsp;·&nbsp;
  <a href="#roadmap">Roadmap</a>
</p>

---

## Features

- **Captures everything you copy** — plain text, images, and files, automatically.
- **Searchable history** — press ⌘⇧V, start typing, and the list filters instantly.
- **Pin what matters** — pinned items are exempt from the rolling limit and never auto-deleted.
- **Paste straight back** — pick an item and Yankit pastes it into the app you were just in.
- **Light on memory** — history lives in SQLite with image blobs on disk, not in RAM (~40 MB idle).
- **Privacy-first** — skips password-manager content, dims while paused, and keeps its data out of Spotlight and Time Machine.
- **Pause when you need to** — one click silences capture for an hour, until tomorrow, or until you resume.
- **Per-app exclusion** — tell Yankit to ignore copies made in specific apps.
- **Yours to tune** — a configurable cap (default 30) trims the oldest items, with optional auto-expiry by age.

## How it works

Yankit lives in the menu bar — no Dock icon, no window in your way. It watches the
system pasteboard and records each new copy into a local SQLite database, with image
and file payloads stored as files on disk so the database stays small and fast.

Press **⌘⇧V** anywhere to open the history panel, filter with a few keystrokes, and
hit Return to paste. Pinned items stick around; everything else rolls off once you
pass the limit.

Nothing leaves your Mac. There is no account, no sync, and no telemetry.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build and run

The Xcode project is generated from `project.yml`, so it is not committed:

```sh
xcodegen generate
open Yankit.xcodeproj
```

Press `⌘R` to run and `⌘U` to run the tests. A clipboard icon appears in the menu bar.

For one-touch paste, grant Yankit **Accessibility** access when prompted
(System Settings → Privacy & Security → Accessibility). Without it, Yankit still
places your selection on the clipboard for a manual `⌘V`.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘⇧V` | Open / close the history panel |
| Type | Filter the history live |
| `↑` `↓` | Move the selection |
| `Return` | Paste the selected item |
| `Esc` | Dismiss the panel |

The `⌘⇧V` shortcut is rebindable in Settings → General.

## Architecture

The full design — data model, capture pipeline, eviction strategy, and the phased
build — lives in [ARCHITECTURE.md](ARCHITECTURE.md). In short: a polling clipboard
monitor, a GRDB/SQLite store with on-disk blobs, a non-activating SwiftUI panel,
and a handful of focused services wired together at launch.

## Building a release

Yankit ships unsigned for now. To build a distributable copy:

1. In Xcode, select the `Yankit` scheme, then Product → Archive.
2. Choose Distribute App → Copy App, or build the Release configuration and take
   `Yankit.app` from the build output.
3. Optionally wrap it in a disk image:
   `hdiutil create -volname Yankit -srcfolder Yankit.app -ov Yankit.dmg`

Because the build is unsigned, the first launch needs a right-click → **Open** to
get past Gatekeeper.

## Roadmap

- Code signing and notarization for a friction-free install
- A Homebrew cask (`brew install --cask yankit`)
- Drag items out of the history panel

## License

MIT — see [LICENSE](LICENSE). Contributions welcome.
