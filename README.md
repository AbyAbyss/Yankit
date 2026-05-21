# ipaste

A free, open-source clipboard manager for macOS. Lives in the menu bar,
remembers the last ~30 things you copy (text, images, files), and pastes
any of them back with `⌘⇧V`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.

## Status

Feature-complete (Phases 0–7): clipboard capture for text, images, and
files; searchable history panel with pinning; `⌘⇧V` global shortcut; a
settings window; pause-capture; per-app exclusion; and storage housekeeping.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & run

The Xcode project is generated from `project.yml`, so it is not committed.
Generate it, then build from Xcode:

```sh
xcodegen generate
open ipaste.xcodeproj
```

Press `⌘R` in Xcode to run. A clipboard icon appears in the menu bar; there
is no Dock icon — ipaste is a menu-bar agent app.

Run the unit tests with `⌘U`.

Builds are unsigned during development, so macOS Gatekeeper may warn on first
launch. Right-click the app and choose **Open** to get past it.

## Building a release

ipaste ships unsigned for now. To build a distributable copy:

1. In Xcode, select the `ipaste` scheme, then Product → Archive.
2. In the Organizer, choose Distribute App → Copy App — or build the
   Release configuration and take `ipaste.app` from the build output.
3. Optionally wrap it in a disk image:
   `hdiutil create -volname ipaste -srcfolder ipaste.app -ov ipaste.dmg`

Because the build is unsigned, the first launch needs a right-click →
**Open** to get past Gatekeeper. Code signing and notarization can be
added later with an Apple Developer account.

## License

MIT — see [LICENSE](LICENSE).
