# Releasing Yankit

Yankit uses [Semantic Versioning](https://semver.org) and **tag-driven
releases**: you push a version tag, and GitHub Actions builds, tests, packages,
and publishes the release for you.

## Versioning

Versions are `MAJOR.MINOR.PATCH`, and release tags are that version prefixed
with `v` — for example `v1.4.0`.

- **MAJOR** — incompatible changes (data format, removed features).
- **MINOR** — new features, backwards compatible.
- **PATCH** — bug fixes only.

You never hand-edit the version for a release — the build reads it from the tag.
The `MARKETING_VERSION` in `project.yml` is just the placeholder used for local
development builds.

## Cutting a release

Once `main` is in good shape:

```sh
git checkout main && git pull
git tag v1.4.0
git push origin v1.4.0
```

Pushing the tag triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml),
which:

1. Checks out the tagged commit.
2. Generates the Xcode project with XcodeGen.
3. Runs the unit tests — a failure here stops the release.
4. Builds `Yankit.app` in Release configuration, stamped with the tag's version.
5. Packages it into `Yankit-1.4.0.dmg` with a drag-to-Applications layout.
6. Creates a GitHub Release for the tag, attaches the DMG, and auto-generates
   notes from the commits since the previous tag.

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

Add the hardened runtime (required for notarization) to `project.yml`, under the
`Yankit` target's `settings.base`:

```yaml
        ENABLE_HARDENED_RUNTIME: YES
```

Then build with your Developer ID identity instead of the ad-hoc `-`:

```sh
xcodebuild -project Yankit.xcodeproj -scheme Yankit -configuration Release \
  -derivedDataPath build \
  DEVELOPMENT_TEAM=YOURTEAMID \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
  build
```

### 4. Notarize

Store your notary credentials once. Use an
[app-specific password](https://support.apple.com/102654) created at
appleid.apple.com — not your main Apple ID password:

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

### 5. Add signing to CI

When you are ready, add these repository secrets under Settings → Secrets and
variables → Actions:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of the exported `.p12` |
| `MACOS_CERTIFICATE_PWD` | the `.p12` export password |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `APPLE_APP_PASSWORD` | the app-specific password |

Then, in `release.yml`, import the certificate before the build, build with the
Developer ID identity, and add a notarize step after the DMG is created:

```yaml
      - name: Import signing certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.MACOS_CERTIFICATE }}
          p12-password: ${{ secrets.MACOS_CERTIFICATE_PWD }}

      # ...in the build step, replace the ad-hoc identity with:
      #   DEVELOPMENT_TEAM=${{ secrets.APPLE_TEAM_ID }}
      #   CODE_SIGN_IDENTITY="Developer ID Application"

      - name: Notarize and staple
        run: |
          xcrun notarytool submit "Yankit-${VERSION}.dmg" \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --team-id "${{ secrets.APPLE_TEAM_ID }}" \
            --password "${{ secrets.APPLE_APP_PASSWORD }}" \
            --wait
          xcrun stapler staple "Yankit-${VERSION}.dmg"
```

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

  url "https://github.com/aby/yankit/releases/download/v#{version}/Yankit-#{version}.dmg"
  name "Yankit"
  desc "Free, open-source clipboard manager for macOS"
  homepage "https://github.com/aby/yankit"

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
brew install --cask aby/yankit/yankit
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
- [ ] `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] Watch the **Actions** run finish green.
- [ ] Check the **Releases** page — DMG attached, notes look right.
- [ ] If you maintain a Homebrew tap, bump `version` + `sha256` in the cask.
