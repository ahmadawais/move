<p align="center"><img src="assets/logo.png" width="128" height="128" alt="Move"></p>

<h1 align="center">Move</h1>

<p align="center">Keyboard window manager for macOS. Private, no network, one permission.</p>

Move snaps windows to halves, thirds, fourths, corners and grids with global shortcuts. About 2,000 lines of
Swift, no dependencies, nothing that phones home.

## Private by design

- **No network.** At launch Move puts itself in a kernel sandbox profile that refuses every IP connection and
  DNS lookup, and that it can't lift. Not a promise: the kernel enforces it.
- **One permission**, Accessibility, to move other apps' windows. Global shortcuts are Carbon hotkeys, so no
  Input Monitoring.
- **No updater, analytics or crash reports.** No dependencies.
- **Your data stays put.** Settings live in `~/Library/Preferences/com.ahmadawais.move.plist`. Logs carry action
  names and window frames, never window titles or app content.

## Install

Apple charges $99 a year to notarize apps. Move skips that: the app is signed on your Mac, by you, and it
never carries the download flag Gatekeeper checks. Two ways, same result.

**1. Download the release (no Xcode):**

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadawais/move/main/scripts/get.sh | bash
```

[`get.sh`](scripts/get.sh) downloads the latest [release](https://github.com/ahmadawais/move/releases),
checks its SHA-256 sums, signs it with a certificate it creates in your login keychain (once; macOS asks for
your password), and installs it to `/Applications`. Run it again to update. With the
[GitHub CLI](https://cli.github.com) signed in, it also checks the build provenance: proof the zip was built by
this repo's [release workflow](.github/workflows/release.yml) from the tagged commit, not uploaded by hand.
Check it yourself any time with `gh attestation verify Move.zip --repo ahmadawais/move`.

Prefer reading before running? `curl -fsSLO https://raw.githubusercontent.com/ahmadawais/move/main/scripts/get.sh`,
read it, then `bash get.sh`.

**2. Build from source** (Xcode Command Line Tools: `xcode-select --install`):

```bash
git clone https://github.com/ahmadawais/move.git && cd move
./scripts/make-cert.sh        # once per Mac: the local signing certificate
./scripts/install.sh          # builds, signs, copies to /Applications, launches
```

Then allow it once: **System Settings → Privacy & Security → Accessibility → Move**. Move relaunches by itself.

**Why the certificate?** macOS ties the Accessibility permission to the app's signature. The local certificate
makes that signature the same on every update, so the permission stays. Its private key never leaves your
login keychain and only `codesign` may use it. Skip it (`MOVE_ADHOC=1` for `get.sh`) and Move is signed
ad-hoc: it works the same, but you turn it off and on again in that list after each update.

## Shortcuts

Defaults are ⌃⌥⌘ plus a key. Every one of the 132 actions can take a shortcut in **Settings → Shortcuts**:
click, press keys. Esc cancels, ⌫ clears. A key already in use moves to the new action.

| Action | Keys | Pressed again |
|---|---|---|
| Left / Right Half | ⌃⌥⌘ ← / → | moves to the next display |
| Top / Bottom Half | ⌃⌥⌘ ↑ / ↓ | moves to the display above / below |
| Maximize | ⌃⌥⌘ ↩ | |
| Almost Maximize | ⌃⌥⌘ ' | |
| Center | ⌃⌥⌘ C | |
| Center Half | ⌃⌥⌘ \\ | |
| First / Second / Third / Last Fourth | ⌃⌥⌘ 1 / 2 / 3 / 4 | 1 and 4 step through the fourths; 2 and 3 widen to ¾, then ½ |
| Larger / Smaller | ⌃⌥⌘ ] / [ | |

What "pressed again" does is a setting: move to the next display, cycle sizes (½ → ⅔ → ⅓),
both, cycle through displays, cycle quadrants, switch sides, or nothing.

## Actions

Halves · corners · thirds and two-thirds · fourths and three-fourths · sixths · ninths · eighths · twelfths ·
sixteenths · corner thirds · vertical thirds · vertical sixths and eighths · maximize, almost maximize,
maximize height · center, center prominently · specified size · larger, smaller (and by width / height) ·
halve or double width / height · move to an edge · next, previous or a specific display (1–9) · restore.

Thirds and fourths follow the display: columns on landscape, rows on portrait.

## Settings

- **General**: Accessibility status, launch at login, menu bar icon, what a repeated shortcut does, cycle sizes.
- **Shortcuts**: every action, recordable.
- **Layout**: gaps between windows, almost-maximize size, larger/smaller step, specified size, Center Half cycling,
  maximize-again-to-restore, centering on edge moves.
- **Apps**: apps where Move's shortcuts are off (handy for apps that use the same keys).
- **Advanced**: screen-edge gaps, cursor follows the window, privacy facts.

## Why not the App Sandbox

The App Sandbox blocks the Accessibility API (`deny mach-lookup com.apple.axserver`), so no sandboxed app can move
another app's windows. Move uses a narrower kernel sandbox instead: everything is allowed except networking
(`Sources/MoveKit/NoNetwork.swift`, a seven-line profile). `NoNetworkTests` run `curl`, `nc` and `host` under that exact
profile and check that they fail. **Settings → Advanced → Privacy** shows whether it is active.

## Scripting

```bash
open -g "move://execute-action?name=left-half"
open -g "move://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari"
open -g "move://execute-task?name=unignore-app"
```

Every action has a kebab-case name: its title in lowercase with dashes (`first-fourth`, `top-left-sixth`,
`next-display` …).

## Not included

Drag-to-snap areas, Todo mode, Stage Manager awareness, multi-window actions (tile all, cascade, cycle stacked
windows), mouse-button shortcuts, title-bar double-click, window animation, JSON import/export, translations.

## Build & test

```bash
./scripts/test.sh             # Swift Testing: engine, controller, prefs, URLs, hotkeys, settings renders
./scripts/build.sh            # build/Move.app
git tag vX.Y.Z && git push --tags   # CI: test, universal build, provenance, GitHub release
```

Settings renders land in `.build/renders/` for review.

```
Sources/Move/main.swift        app entry
Sources/MoveKit/
  Engine.swift                 all window geometry, pure and unit-tested (no AppKit)
  Action.swift                 the 132 actions, names, groups
  Controller.swift             focused window → engine → place, restore history
  Window.swift                 Accessibility window access, permission
  NoNetwork.swift              kernel sandbox profile: no networking
  HotKeys.swift                Carbon global shortcuts, key names
  Prefs.swift                  settings and default shortcuts
  Settings.swift               SwiftUI settings window
  AppDelegate.swift            menu bar, URLs, ignored apps
```

## License

MIT.
