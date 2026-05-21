# ipaste — Architecture & Implementation Plan

A free, open-source clipboard manager for macOS. Lives in the menu bar, remembers
the last ~30 things you copied (text, images, files), and lets you paste any of
them back with `⌘⇧V`.

This document is the design contract. It is written so a single engineer (or
Claude) can implement it phase by phase with clear verification at each step.

---

## 1. Goals & non-goals

**Goals (from the request)**

- Capture **text, images, and files** copied anywhere on the Mac.
- Keep a **rolling history**, capped at a **configurable maximum (default 30)**.
- **Text and image previews** in the history list.
- A **menu bar (tray) icon**.
- **Launch at login** option.
- Global shortcut **`⌘⇧V`** to open the history picker.
- **Do not keep everything in memory** — persist to SQLite + disk.
- **Auto-delete the oldest items** once the cap is exceeded.
- A **Settings / Preferences window**.
- **Capture everything by default**; let the user **exclude specific apps**.

**Added during design review (agreed)**

These four were not in the original request but were added after architectural
review, because each meaningfully improves correctness, privacy, or daily use:

- **Search-as-you-type** in the history panel — the fastest way to find an item.
- **Pinning** — pin items so they survive auto-eviction. Without it the 30-item
  cap will eventually delete something you wanted to keep.
- **Pause / private capture** toggle in the menu bar — a privacy escape hatch
  for when you are about to copy passwords, 2FA codes, or other secrets.
- **Privacy hardening** — transient-marker handling, restrictive file
  permissions, optional auto-expire, and a capture size guard.

**Non-goals (explicitly out of scope for v1, to keep it simple)**

- iCloud / cross-device sync.
- Rich snippet management, tagging, or folders.
- Mac App Store distribution (see §10 — sandboxing makes this impractical).
- Editing clipboard content inside the app.
- Encryption at rest (SQLCipher) — deferred; the file permissions and
  auto-expire in this plan cover the realistic v1 risk.

Anything not in the Goals or design-review list above is not built unless you
ask for it.

---

## 2. Tech stack & key decisions

| Concern            | Choice                          | Why |
|--------------------|---------------------------------|-----|
| Language / UI      | Swift 5.9+, SwiftUI + AppKit    | Lowest memory, native pasteboard access |
| Minimum OS         | macOS 14 Sonoma                 | Modern SwiftUI, clean `SMAppService` |
| Database           | SQLite via **GRDB.swift**       | Mature, typed, migrations, MIT license |
| Global hotkey      | **KeyboardShortcuts** (S. Sorhus) | Carbon-backed, no Accessibility needed, rebindable |
| Launch at login    | `SMAppService.mainApp`          | First-party API, no helper bundle |
| Tray icon          | `NSStatusItem`                  | Standard menu bar API |
| App type           | Agent app (`LSUIElement = YES`) | Menu-bar-only, no Dock icon |
| Distribution       | Notarized DMG / Homebrew cask   | Not sandboxed — see §10 |

Both third-party dependencies are MIT-licensed and added via Swift Package
Manager. Everything else uses first-party frameworks.

**A senior-engineer note on simplicity:** with a 30-item cap, the dataset is
tiny. The architecture below is deliberately modest — one SQLite table, a polling
timer, a few views. Resist adding a caching layer, a sync engine, or a plugin
system. The interesting engineering is in *correctness* (eviction, dedup, focus
handling, self-capture), not scale.

---

## 3. High-level architecture

```
                       ┌─────────────────────────┐
        ⌘⇧V  ─────────▶│      HotkeyManager       │
                       └────────────┬────────────┘
                                    │ show panel
   ┌────────────────┐   poll   ┌────▼─────────┐   write   ┌──────────────┐
   │  NSPasteboard  │◀─────────│ Clipboard    │──────────▶│  Clipboard   │
   │   (system)     │ 0.4s tick│ Monitor      │           │  Repository  │
   └────────────────┘          └──────┬───────┘           └──────┬───────┘
                                      │ pause / exclude /        │
                                      │ self-capture checks      │
                               ┌──────▼───────┐         ┌────────▼────────┐
                               │ Preferences  │         │  SQLite (GRDB)  │
                               │ (UserDefaults)│        │  + BlobStore     │
                               └──────────────┘         │  (files on disk) │
                                                         └────────┬────────┘
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐         │
   │ MenuBar      │   │ History      │◀──│ PasteService │◀────────┘
   │ Controller   │   │ Panel (UI)   │──▶│ (CGEvent ⌘V) │  load full payload
   └──────────────┘   └──────────────┘   └──────────────┘     on demand
```

The app is a single process. The only always-on cost is a low-frequency timer
(the `ClipboardMonitor`). Everything else is event-driven.

---

## 4. Data model & storage

### 4.1 On-disk layout

```
~/Library/Application Support/ipaste/
  history.sqlite          ← text + all metadata
  blobs/
    <uuid>.png            ← image payloads (clipboard images, full size)
    <uuid>.thumb.png      ← 128px thumbnails for the list
```

Text lives inside SQLite (small, queryable). Image bytes live as files,
referenced by path — this keeps the database file small and fast, and makes
eviction a simple "delete row + delete file".

The `ipaste` directory is created with `0700` permissions and the database file
with `0600`, and the whole directory is marked `isExcludedFromBackup` and
excluded from Spotlight indexing — so clipboard history is not silently copied
into Time Machine snapshots or search indexes.

### 4.2 Schema — one table

```sql
CREATE TABLE clipboard_item (
  id              TEXT PRIMARY KEY,         -- UUID
  kind            TEXT NOT NULL,            -- 'text' | 'image' | 'file'
  copied_at       DATETIME NOT NULL,        -- when captured (eviction order)
  pinned          INTEGER NOT NULL DEFAULT 0, -- 1 = exempt from eviction
  content_hash    TEXT NOT NULL,            -- dedup key
  byte_size       INTEGER NOT NULL,

  -- text items
  text_content    TEXT,                     -- full text
  preview_text    TEXT,                     -- first ~200 chars for the list

  -- image items
  blob_path       TEXT,                     -- blobs/<uuid>.png
  thumbnail_path  TEXT,                     -- blobs/<uuid>.thumb.png
  pixel_width     INTEGER,
  pixel_height    INTEGER,

  -- file items
  file_url        TEXT,                     -- original on-disk location
  file_name       TEXT,

  -- provenance (drives the app-exclusion feature)
  source_bundle_id TEXT,
  source_app_name  TEXT
);

CREATE INDEX idx_item_copied_at   ON clipboard_item(copied_at);
CREATE INDEX idx_item_content_hash ON clipboard_item(content_hash);
```

The `content_hash` index exists because dedup now looks up the hash across the
whole table (see §7). Schema changes go through GRDB **migrations** so existing
users' history survives upgrades.

### 4.3 How each kind is stored

- **Text** — `text_content` holds the full string; `preview_text` holds a
  truncated snippet so the list never loads large strings. RTF, if present, is
  not stored in v1 (plain text only — simplest correct choice).
- **Image** — clipboard images have no source file. The PNG bytes are written
  to `blobs/<uuid>.png`, a 128px `thumb.png` is generated, and only the paths +
  dimensions go in the row.
- **File** — when you copy files in Finder, the pasteboard carries *file URLs*,
  not bytes. ipaste stores the **URL reference** plus the file name. It does
  **not** copy the file's bytes (a copied 4 GB video must not bloat `blobs/`).
  Trade-off: if you later move or delete that file, the history item becomes
  stale. This is the standard behavior for clipboard managers and is called out
  in §14 as a decision you can override.

---

## 5. Memory strategy ("not everything in memory")

The requirement is satisfied by three rules:

1. **SQLite is the source of truth.** The full history is never held as an
   in-memory array of payloads.
2. **The history list binds to lightweight rows only** — `id`, `kind`,
   `preview_text`, `thumbnail_path`, timestamps. A full image (potentially
   megabytes) is loaded **only** when its row is selected for preview or chosen
   for paste, and released right after.
3. **Thumbnails are capped at 128px**, so even showing all 30 rows at once costs
   a few hundred KB, not tens of MB.

Resident memory target: **under ~40 MB idle**. The only persistent allocations
are the AppKit/SwiftUI runtime, the status item, and one repeating timer.

---

## 6. Clipboard capture pipeline

`NSPasteboard` provides **no change notification**, so the monitor polls.

```
ClipboardMonitor (Timer, ~0.4s):
  1. Read NSPasteboard.general.changeCount.
  2. If unchanged → return.
  3. SELF-CAPTURE GUARD: if this changeCount was produced by our own
     PasteService, record it as seen and return. (Without this, every
     paste the app performs would be re-captured into the history.)
  4. If capture is paused (Preferences.pausedUntil is in the future) → return.
  5. A copy happened. Determine the source app:
       NSWorkspace.shared.frontmostApplication  → bundle id + name.
  6. If bundle id ∈ Preferences.excludedBundleIDs → skip (do not save).
  7. If the pasteboard carries `org.nspasteboard.ConcealedType` or
     `org.nspasteboard.TransientType` (password managers / transient
     secrets) and Preferences.ignoreConcealedItems is on → skip.
  8. Detect kind, in priority order:
       file URLs present?  → kind = file
       image present?      → kind = image   (.png / .tiff / NSImage)
       string present?     → kind = text
  9. If the payload exceeds Preferences.maxCaptureBytes → skip.
 10. Compute content_hash and dedup against the WHOLE history (see §7):
       hash already present → refloat that existing row, return.
 11. Persist via ClipboardRepository (write blob if needed, insert row).
 12. Run eviction (see §7).
```

Polling at 0.4s is imperceptible to the user and costs near-zero CPU (an integer
comparison). It is the simplest reliable mechanism and needs **no special
permission**.

**Source-app accuracy caveat:** `frontmostApplication` is the app in focus when
the copy is *observed*, which is correct in the overwhelming majority of cases
but can misattribute if focus changes within the 0.4s window. Acceptable for an
exclusion filter; documented here for honesty.

---

## 7. Eviction & deduplication

**Deduplication.** Copying the same thing twice should not create two rows. On
capture, the monitor looks up `content_hash` across the **entire history**, not
just the newest item. If a match is found, that existing row is refloated
(`copied_at = now`) and nothing is inserted. This also means re-pasting an old
item correctly moves it to the top instead of creating a duplicate.

**Eviction.** Immediately after every insert:

```
count = SELECT COUNT(*) FROM clipboard_item WHERE pinned = 0
if count > Preferences.maxItems:
    for each surplus UNPINNED row, oldest copied_at first:
        delete blob_path and thumbnail_path files from disk (if any)
        DELETE the row
    all inside one transaction
```

**Pinned items are exempt from eviction and do not count toward `maxItems`** —
the cap governs only the unpinned, auto-managed portion of the history. This is
what makes a low cap like 30 safe: anything you care about, you pin.

Eviction also runs **when the user lowers `maxItems`** in Settings, so the
history shrinks immediately.

**Auto-expire (TTL).** If `Preferences.autoExpireDays` is greater than zero, a
daily sweep deletes unpinned items older than that many days regardless of the
count cap — this bounds how long a copied secret can linger. Off by default.

---

## 8. User interface

Three surfaces, all SwiftUI hosted in AppKit windows.

### 8.1 Menu bar — `MenuBarController`

An `NSStatusItem` with the ipaste icon. **Left-click** opens the history panel.
**Right-click** opens a small menu:

- *Open History (⌘⇧V)*
- *Pause Capture* — submenu: *for 1 hour*, *until tomorrow morning*,
  *until I resume*; shown as *Resume Capture* while paused.
- *Settings…*
- *Quit*

While capture is paused the menu bar icon **dims**, so the state is obvious at a
glance and you never copy secrets thinking capture is off when it isn't (or vice
versa).

### 8.2 History panel — `HistoryPanel`

A borderless, non-activating `NSPanel` (so it does not steal focus from the app
you were typing in — critical for the paste flow in §9). SwiftUI content via
`NSHostingView`. Appears centered on the active screen.

A **search field** sits at the top of the panel and holds focus when the panel
opens — typing filters the list live across text content, file names, and source
app name. Arrow keys still navigate the filtered results, so the fast path is:
`⌘⇧V`, type a few letters, `Return`.

Each row shows:

- **Text** — the `preview_text` snippet, kind icon, source app, relative time.
- **Image** — the 128px thumbnail, dimensions, source app, relative time.
- **File** — the system file icon, file name, source app, relative time.
- A **pin toggle** — pinned rows show a filled pin and sort above the rest.

Interaction:

- Arrow keys move the selection; **Return** pastes the selected item.
- **Esc** dismisses the panel.
- Clicking a row pastes it.
- `1`–`9` paste the Nth item directly (quick-access).
- `⌘P` (or clicking the pin) toggles pin on the selected item.

### 8.3 Settings window — `SettingsView`

A standard SwiftUI `Settings` scene with tabs:

- **General** — launch at login toggle; max items stepper (1–100, default 30);
  the `⌘⇧V` shortcut recorder (rebindable).
- **Excluded Apps** — list of apps whose copies are ignored; an "Add…" button
  opens a picker over `/Applications`. Empty by default = capture everything.
- **Privacy** — ignore concealed/transient pasteboard content (on by default);
  auto-expire items older than N days (off by default); max single-item capture
  size (default 10 MB).
- **Storage** — current item count and disk usage; a "Clear History" button.
- **About** — version, open-source license, project link.

---

## 9. Global hotkey & paste flow

**Opening the picker.** `KeyboardShortcuts` registers `⌘⇧V` with that default,
and the Settings recorder lets the user change it. Pressing it shows
`HistoryPanel`.

**Pasting a chosen item:**

```
1. Before showing the panel, record the current frontmost app.
2. User picks an item in the panel.
3. PasteService writes the item's payload to NSPasteboard AND records the
   resulting changeCount so the monitor's self-capture guard ignores it:
     text  → write string
     image → load blobs/<uuid>.png, write image
     file  → write the file URL
4. Dismiss the panel; reactivate the previously frontmost app.
5. Synthesize ⌘V via CGEvent so the content lands in that app.
```

Step 5 needs the **Accessibility** permission (`AXIsProcessTrusted`). If the
user has not granted it, ipaste **degrades gracefully**: the item is placed on
the clipboard and a one-time hint explains that the user can press `⌘V` manually,
or enable Accessibility for one-touch paste. The app is fully usable either way.

> **Known shortcut conflict — surfacing the trade-off.** `⌘⇧V` is macOS's
> standard *Paste and Match Style*. While ipaste runs, a global `⌘⇧V` overrides
> that in every app. This is the explicitly requested default, but because the
> shortcut is rebindable, anyone who relies on Paste-and-Match-Style can change
> it in Settings. Flagging it so the choice is deliberate, not accidental.

---

## 10. Permissions, sandboxing & distribution

| Capability                 | Permission needed | Notes |
|----------------------------|-------------------|-------|
| Read `NSPasteboard`        | None              | — |
| Global hotkey (Carbon)     | None              | via KeyboardShortcuts |
| Auto-paste (`CGEvent ⌘V`)  | **Accessibility** | Optional; graceful fallback |
| Launch at login            | None              | `SMAppService` |
| Read copied file URLs      | None when unsandboxed | — |

**Sandboxing.** A clipboard manager that synthesizes keystrokes and references
arbitrary copied file paths cannot work well inside the App Sandbox. ipaste ships
**unsandboxed**, which also means **not via the Mac App Store**.

**Distribution.** Recommended path: a **notarized `.dmg`** attached to GitHub
Releases, plus an optional **Homebrew cask**. Notarization needs an Apple
Developer account ($99/yr). Without one, the app still runs but users must
right-click → Open the first time — acceptable for an open-source tool, and a
decision left to you in §14.

---

## 11. Project structure

```
ipaste/
  ipaste.xcodeproj
  Package.resolved              ← SPM: GRDB.swift, KeyboardShortcuts
  Sources/
    App/
      ipasteApp.swift           ← @main, App scene wiring
      AppDelegate.swift         ← lifecycle, starts monitor + menu bar
    Clipboard/
      ClipboardItem.swift       ← model (Codable, GRDB record)
      ClipboardMonitor.swift    ← polling + capture pipeline (§6)
      PasteService.swift        ← write pasteboard + CGEvent ⌘V (§9)
    Storage/
      Database.swift            ← GRDB setup + migrations
      ClipboardRepository.swift ← CRUD, dedup, eviction, auto-expire (§7)
      BlobStore.swift           ← blob/thumbnail file management
    Settings/
      Preferences.swift         ← UserDefaults-backed settings
      LoginItemManager.swift    ← SMAppService wrapper
      HotkeyManager.swift       ← KeyboardShortcuts wrapper
      ExcludedAppsManager.swift ← blocklist + app picker
      PauseController.swift     ← pause-until state + icon dimming
    UI/
      MenuBarController.swift   ← NSStatusItem + pause menu
      HistoryPanel.swift        ← NSPanel host
      HistoryView.swift         ← SwiftUI list + search field
      HistoryRowView.swift      ← per-kind row rendering + pin toggle
      SettingsView.swift        ← tabbed settings
  Resources/
    Assets.xcassets             ← menu bar icon (normal + dimmed), app icon
    Info.plist                  ← LSUIElement = YES
  Tests/
    StorageTests.swift          ← repository: insert / dedup / eviction / pin
  README.md
  LICENSE
```

---

## 12. Settings reference (UserDefaults keys)

| Key                   | Type       | Default | Meaning |
|-----------------------|------------|---------|---------|
| `maxItems`            | Int        | `30`    | Cap on unpinned items; lowering it triggers eviction |
| `launchAtLogin`       | Bool       | `false` | Mirrors `SMAppService` state |
| `excludedBundleIDs`   | [String]   | `[]`    | Apps whose copies are ignored |
| `ignoreConcealedItems`| Bool       | `true`  | Skip concealed/transient pasteboard content |
| `pausedUntil`         | Date?      | `nil`   | Capture paused until this time (`nil` = active) |
| `autoExpireDays`      | Int        | `0`     | Delete unpinned items older than N days (`0` = off) |
| `maxCaptureBytes`     | Int        | `10 MB` | Skip captures larger than this |
| `captureImages`       | Bool       | `true`  | Master toggle for image capture |
| `captureFiles`        | Bool       | `true`  | Master toggle for file capture |
| (hotkey)              | —          | `⌘⇧V`   | Managed by KeyboardShortcuts |

`captureImages` / `captureFiles` are tiny additions that make "capture
everything by default, but let me opt out" coherent. They default to on, so
out-of-the-box behavior is exactly "save everything."

---

## 13. Implementation phases

Each phase is independently verifiable, per the project's goal-driven execution
guideline. Do not start a phase until the previous one's check passes.

```
Phase 0 — Scaffold
  Xcode project, SPM deps, LSUIElement, menu bar icon.
  → verify: app launches, icon in menu bar, no Dock icon.

Phase 1 — Storage layer
  GRDB Database + migration (incl. `pinned` column), ClipboardRepository,
  BlobStore. Eviction exempts pinned rows; dedup is whole-history.
  → verify: StorageTests pass — insert; duplicate hash refloats instead of
    inserting; eviction deletes oldest UNPINNED row + its blobs; pinned
    rows survive eviction and do not count toward the cap.

Phase 2 — Clipboard monitor
  Polling, kind detection, source-app capture, self-capture guard,
  concealed/transient skip, size guard, persist.
  → verify: copy text / image / files → correct rows + blobs; duplicates
    refloat; the app's own pastes are NOT captured.

Phase 3 — History panel
  NSPanel + SwiftUI list, per-kind previews, search-as-you-type,
  pin/unpin affordance, keyboard navigation.
  → verify: panel lists items with previews; typing filters live;
    pinning a row exempts it from eviction.

Phase 4 — Global hotkey & paste
  KeyboardShortcuts ⌘⇧V; PasteService with CGEvent + graceful fallback;
  changeCount handoff to the self-capture guard.
  → verify: ⌘⇧V opens panel; choosing an item pastes into the prior app
    and does not create a duplicate history row; with Accessibility off,
    the item still lands on the clipboard.

Phase 5 — Settings & pause
  General / Excluded Apps / Privacy / Storage / About tabs; menu bar
  "Pause Capture" toggle with timed options + icon dimming.
  → verify: lowering maxItems evicts immediately; login-item toggle
    survives reboot; pausing stops capture and dims the icon.

Phase 6 — App exclusion
  Wire excludedBundleIDs into the capture pipeline.
  → verify: copies from an excluded app produce no row.

Phase 7 — Polish & ship
  Startup integrity sweep, daily auto-expire sweep, 0600 perms + backup
  exclusion, app icon, README, notarized DMG.
  → verify: orphan blobs cleaned on launch; expired items removed;
    concealed/transient secrets never captured.
```

A reasonable first milestone is **Phases 0–4** — that is a working clipboard
manager. Phases 5–7 make it configurable and shippable.

---

## 14. Open decisions for you

After the design review, only three forks remain. I want your call rather than a
silent default:

1. **License** — `MIT` (simplest, most permissive) vs `GPL-3.0` (keeps
   derivatives open). Recommendation: **MIT**, unless copyleft matters to you.

2. **File capture depth** — store file **path references** (current plan: cheap,
   but breaks if the file moves) vs **copy the bytes** for small files under a
   size limit. Recommendation: references only for v1.

3. **Notarization** — will you enroll in the Apple Developer Program ($99/yr)
   for a smooth install, or ship unsigned for now (right-click → Open)?

My recommendation for v1: **MIT license, references-only file capture.** Search,
pinning, the pause toggle, and the privacy hardening are now folded into the plan
above per the design review — they are no longer open questions.
