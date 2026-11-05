<p align="center"><img src="assets/logo.png" width="128" height="128" alt="Move"></p>

<h1 align="center">Move</h1>

<p align="center">Keyboard window manager for macOS. Private, sandboxed, no network, one permission.</p>

Move snaps windows to halves, thirds, fourths, corners and grids with global shortcuts. It does what
[Rectangle](https://github.com/rxhanson/Rectangle) does with the keyboard, rebuilt from scratch in about
2,000 lines of Swift, with no dependencies and nothing that phones home.

## Why

| | Move | Rectangle |
|---|---|---|
| Network | **Blocked by the App Sandbox** (no `network.client` entitlement: the kernel refuses every connection) | Not sandboxed; Sparkle updater checks `rectangleapp.com` |
| Sandbox | On | Off |
| Permissions | Accessibility only (to move other apps' windows) | Accessibility |
| Global shortcuts | Carbon hotkeys: no Input Monitoring | MASShortcut (also Carbon) |
| Updates, analytics, crash reports | None | Sparkle |
| Dependencies | None | Sparkle, MASShortcut |
| Data | Preferences on your Mac, nothing else | Same |
| Logs | Action names and window frames only, never titles or app content | |

## Install (free, no Apple Developer account)

Apple charges $99 a year to notarize apps. Move skips that: you build it on your Mac and it's signed
locally, so Gatekeeper never sees a download to quarantine.

```bash
git clone https://github.com/ahmadawais/move.git && cd move
./scripts/install.sh          # builds, copies to /Applications, launches
```

Needs the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.

Then allow it once: **System Settings → Privacy & Security → Accessibility → Move**. Move relaunches
by itself when you do.

**Keep that permission across rebuilds (optional, recommended):**

```bash
./scripts/make-cert.sh        # once per Mac: a self-signed "Move Local Signing" certificate
./scripts/install.sh
```

Without the certificate Move is signed ad-hoc. It works the same, but macOS ties the Accessibility
permission to the exact build, so after each rebuild you turn Move off and on again in that list.
The certificate's private key never leaves your login keychain, and only `codesign` can use it.

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

## Scripting

```bash
open -g "move://execute-action?name=left-half"
open -g "move://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari"
open -g "move://execute-task?name=unignore-app"
```

Action names are Rectangle's (`first-fourth`, `top-left-sixth`, `next-display` …), so Rectangle scripts work by
changing `rectangle://` to `move://`.

## Not included

Drag-to-snap areas, Todo mode, Stage Manager awareness, multi-window actions (tile all, cascade, cycle stacked
windows), mouse-button shortcuts, title-bar double-click, window animation, JSON import/export, translations.

## Build & test

```bash
./scripts/test.sh             # Swift Testing: engine, controller, prefs, URLs, hotkeys, settings renders
./scripts/build.sh            # build/Move.app
```

Settings renders land in `.build/renders/` for review. 26 tests are Rectangle's `DisplayTransferTests`, ported 1:1.

```
Sources/Move/main.swift        app entry
Sources/MoveKit/
  Engine.swift                 all window geometry, pure and unit-tested (no AppKit)
  Action.swift                 the 132 actions, names, groups
  Controller.swift             focused window → engine → place, restore history
  Window.swift                 Accessibility window access, permission
  HotKeys.swift                Carbon global shortcuts, key names
  Prefs.swift                  settings and default shortcuts
  Settings.swift               SwiftUI settings window
  AppDelegate.swift            menu bar, URLs, ignored apps
```

## License

MIT. Ported parts of Rectangle keep its MIT notice, see LICENSE.
