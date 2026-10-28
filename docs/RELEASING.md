# Releasing Yankit

Yankit uses [Semantic Versioning](https://semver.org). The version lives in one
place, `MARKETING_VERSION` in `project.yml`. It is what Settings → About shows,
and GitHub Actions releases exactly that version — triggered by pushing its tag
or by a button.

## Versioning

Versions are `MAJOR.MINOR.PATCH`, and release tags are that version prefixed
with `v` — for example `v1.4.0`.

Starting from `1.3.0`, bump by the size of the change:

- **PATCH** — `1.3.0` → `1.3.1` → `1.3.2`: bug fixes and small tweaks.
- **MINOR** — `1.3.x` → `1.4.0`: a significant change or new feature, still
  compatible with existing data and settings. Resets PATCH to 0.
- **MAJOR** — `1.x.y` → `2.0.0`: a major change, e.g. a redesign, an
  incompatible data format, or removed features. Resets MINOR and PATCH to 0.

## Cutting a release

1. **Bump the version.** Set `MARKETING_VERSION` in `project.yml` (e.g. to
   `"1.4.0"`) and merge that to `main` with the changes it ships. Local builds
   then show the new version in Settings → About too.
2. **Release it**, either way:
   - **Button:** GitHub → **Actions** → **Release** → **Run workflow** on `main`.
     The `v1.4.0` tag is created for you. The run stops if the tag already
     exists (you forgot to bump) or if it isn't started from `main`.
   - **Tag:**
     ```sh
     git checkout main && git pull
     git tag v1.4.0
     git push origin v1.4.0
     ```
     The run stops if the tag doesn't match `MARKETING_VERSION`.

Either trigger runs [`.github/workflows/release.yml`](../.github/workflows/release.yml),
which:

1. Checks out the commit and reads the version from `project.yml`.
2. Generates the Xcode project with XcodeGen.
3. Runs the unit tests — a failure here stops the release.
4. Builds `Yankit.app` in Release configuration with that version, signed
   with your Developer ID if the signing secrets are set, ad-hoc otherwise.
5. Packages it into `Yankit-1.4.0.dmg` with a drag-to-Applications layout,
   then notarizes and staples it (signed builds only).
6. Signs the DMG for Sparkle and writes `appcast.xml` (only if the
   `SPARKLE_PRIVATE_KEY` secret is set).
7. Creates the GitHub Release (and the tag, for a button run), attaches the
   DMG and the appcast, and auto-generates notes from the commits since the
   previous tag.

Watch it under the repository's **Actions** tab; when it finishes, the release
is live on the **Releases** page.

To undo a mistaken release, delete the GitHub Release and the tag
(`git push --delete origin v1.4.0`), then re-tag.

> macOS CI runners are free for public repositories. On a private repository
> they consume Actions minutes at a higher rate.

## Building a release locally

To produce the same artifact by hand — useful for testing before you tag:

```sh
xcodegen generate
xcodebuild -project Yankit.xcodeproj -scheme Yankit -configuration Release \
  -derivedDataPath build build
APP="build/Build/Products/Release/Yankit.app"
mkdir dmg && cp -R "$APP" dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname Yankit -srcfolder dmg -ov -format UDZO Yankit-local.dmg
```

## Signing and notarization

The CI build is **unsigned**. It runs, but on first launch macOS Gatekeeper
blocks it and the user must approve it under System Settings → Privacy &
Security → **Open Anyway**. Removing that friction means signing and notarizing
the app, which requires a paid Apple Developer account.

### 1. Join the Apple Developer Program

Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/)
— **$99 per year, recurring**. You need an active membership to sign and
notarize new builds. Builds you have already notarized keep working for users
even if the membership later lapses.

### 2. Create a Developer ID certificate

In Xcode → Settings → Accounts, add your Apple ID, select your team, then
**Manage Certificates → + → Developer ID Application**. This is the certificate
for distributing apps *outside* the Mac App Store.

For CI, export it from Keychain Access: find "Developer ID Application: …",
export as a `.p12` with a password, then base64-encode it for a GitHub secret.

### 3. Sign the build

`project.yml` already turns on the hardened runtime (required for
notarization) for Release builds. Build with your Developer ID identity
instead of the ad-hoc `-`:

```sh
xcodebuild -project Yankit.xcodeproj -scheme Yankit -configuration Release \
  -derivedDataPath build \
  DEVELOPMENT_TEAM=YOURTEAMID \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
  build
```

Sparkle's helpers ship signed by the Sparkle team, so re-sign them with your
identity before notarizing. The release workflow does this in its
**Re-sign Sparkle and the app** step; copy those commands for a local build.

### 4. Notarize

Store your notary credentials once. Use an
[app-specific password](https://support.apple.com/102654) created at
appleid.apple.com, not your main Apple ID password:

```sh
xcrun notarytool store-credentials yankit-notary \
  --apple-id "you@example.com" --team-id "YOURTEAMID" \
  --password "abcd-efgh-ijkl-mnop"
```

Then submit the DMG, wait for the result, and staple the ticket so the app
validates even offline:

```sh
xcrun notarytool submit Yankit-1.4.0.dmg --keychain-profile yankit-notary --wait
xcrun stapler staple Yankit-1.4.0.dmg
```

A notarized, stapled DMG opens with no Gatekeeper warning.

### 5. Turn on signing in CI

The release workflow already has the signing and notarization steps. They
switch on by themselves once these repository secrets exist (Settings →
Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 of the exported `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `APPLE_APP_PASSWORD` | the app-specific password |

Without `DEVELOPER_ID_CERT_P12` the workflow builds unsigned, as before.

## Auto-updates (Sparkle)

Yankit updates itself with [Sparkle](https://sparkle-project.org). Each
release attaches an `appcast.xml`, and the app reads the copy on the latest
release:

```
https://github.com/AbyAbyss/Yankit/releases/latest/download/appcast.xml
```

Sparkle only installs an update whose EdDSA signature matches the public key
built into the running app. Set the keys up once:

1. Download the Sparkle release that matches the package version from
   [its releases page](https://github.com/sparkle-project/Sparkle/releases)
   and run `./bin/generate_keys`. It stores the private key in your login
   Keychain and prints the public key.
2. Paste the public key into `SPARKLE_PUBLIC_KEY` in `project.yml`.
3. Export the private key with `./bin/generate_keys -x sparkle_private_key`,
   save the file's contents as the `SPARKLE_PRIVATE_KEY` repository secret,
   then delete the file. Keep the Keychain copy: **if you lose the private
   key, existing installs can never update again.**

The release workflow refuses to run while `SPARKLE_PUBLIC_KEY` is empty, so a
release can't ship without an updater by accident. Local builds without the
key have no updater at all (no
"Check for Updates…" item), so forks and local builds don't nag anyone.

The first release with a key is the first one that can update itself. Users
on 1.3.x and earlier install it by hand once; from then on it updates on its
own. Sparkle asks on the second launch whether to check automatically.

## Selling the supporter download

Yankit stays MIT and free to build. The supporter download is the same
signed, notarized DMG, sold pay-what-you-want so people can pay for the
convenience and to support the project:

1. Make a product on [Gumroad](https://gumroad.com) or
   [Lemon Squeezy](https://www.lemonsqueezy.com) called "Yankit (supporter
   download)": pay what you want, suggested $5. Attach the release DMG, or
   link to the latest release so the file never goes stale.
2. Add the product link, plus Buy Me a Coffee and GitHub Sponsors if you
   use them, to the `#support` section of the website. The app's
   **Support Yankit…** menu item and About link open that section, so the
   links can change without a new build.
3. If you add GitHub Sponsors, list it in `.github/FUNDING.yml` to get the
   **Sponsor** button on the repository.

Buyers get updates through Sparkle like everyone else, so there is no
license key to manage.

## Publishing to Homebrew

Homebrew itself is free and needs nothing from Apple. A cask just downloads and
unpacks your DMG — so if the app is unsigned, users still get the Gatekeeper
prompt. Notarizing first makes the `brew install` experience clean.

### Your own tap (start here)

1. Create a public GitHub repository named **`homebrew-yankit`**.
2. Add `Casks/yankit.rb`:

```ruby
cask "yankit" do
  version "1.4.0"
  sha256 "PASTE_THE_DMG_SHA256_HERE"

  url "https://github.com/AbyAbyss/Yankit/releases/download/v#{version}/Yankit-#{version}.dmg"
  name "Yankit"
  desc "Free, open-source clipboard manager for macOS"
  homepage "https://github.com/AbyAbyss/Yankit"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Yankit.app"

  zap trash: "~/Library/Application Support/Yankit"
end
```

Get the checksum after a release with `shasum -a 256 Yankit-1.4.0.dmg`. Users
then install with:

```sh
brew install --cask AbyAbyss/yankit/yankit
```

Each release, bump `version` and `sha256` in the cask and commit. (This can be
automated later with a small workflow in the tap repository.)

### The official homebrew-cask

Getting into the main [`homebrew/cask`](https://github.com/Homebrew/homebrew-cask)
repository lets users run `brew install --cask yankit` with no tap. The bar is
higher: the app should be reasonably established, and a signed + notarized build
is strongly preferred. When you qualify, open a pull request adding the cask
file there and follow its contribution checklist.

## Release checklist

- [ ] `main` builds and all tests pass.
- [ ] User-facing changes show up clearly in commit messages — they become the
      release notes.
- [ ] Decide the version bump: major, minor, or patch.
- [ ] Set `MARKETING_VERSION` in `project.yml` and merge to `main`.
- [ ] Click **Run workflow**, or `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] Watch the **Actions** run finish green.
- [ ] Check the **Releases** page: DMG and `appcast.xml` attached, notes look right.
- [ ] From an older install, use **Check for Updates…** and confirm it updates.
- [ ] If you maintain a Homebrew tap, bump `version` + `sha256` in the cask.
