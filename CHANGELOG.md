# Changelog

All notable changes to `niri-meta` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `login install|remove|status` and the own `niri-login` repo: the niri Wayland
  session entry is placed in a **system-scanned** `wayland-sessions` directory
  (with sudo) so display managers list "Niri". Display managers do not scan the
  user-local path, which is why the entry did not appear before. It is skipped
  when the distro already ships a session entry, and falls back to a user-local
  entry with a warning if the privileged install fails. `install` and `desktop`
  ensure the entry.
- Own repo `nyx-niri` (compositor-neutral mascot island overlay) with its
  conditional deploy into `.../quickshell/ui/nyx`.
- Shared repos `shell` and `nyx` are now cloned and their base deployed, plus a
  vendored `share/default_settings.json` seeded only when `settings.json` is
  absent. `dotsniri` is now standalone: it no longer requires `dots` to provide
  the Quickshell shell or the settings seed.
- Namespaced multi-overlay engine
  (`~/.local/state/equisdots-niri/overlay/<name>/{manifest,backup}`) so
  `niri-shell` and `nyx-niri` apply and remove independently.
- `doctor` checks for the Quickshell shell base (`$QS/Shell.qml`), the Niri
  shell backend (`core/compositors/Niri.qml`) when niri is selected, the login
  session entry, and a competing notification daemon (`mako`/`dunst`).
- `tools/diagnose.sh`: read-only session-startup diagnostics. It reports the
  system and display manager, GPU, niri binaries and version, session entries,
  SDDM config, `niri validate`, session logs, journals, logind state,
  dependencies and the `equisdots-niri` state. It never modifies the system.
- curl-bootstrap self-update: when the one-liner finds an existing
  `~/.local/share/equisdots-niri/niri-meta` clone it fetches and hard-resets it
  before running, so a piped bootstrap always uses the latest code.
- System template resolution by distro `ID` and then each token of `ID_LIKE`
  (for example `ID=x` + `ID_LIKE=arch` resolves to `install-arch.sh`).

### Changed

- `install` now defaults the desktop to niri before deploying, so the
  compositor overlays are applied (otherwise the shell keeps the Hyprland
  backend and breaks under niri with a gray screen and only a cursor). It also
  bootstraps packages through the system template when `niri` is missing, and
  ensures the login session entry.
- The shared `shell` and `nyx` bases are now **pulled and redeployed** by
  `install`/`update` because the overlays sit on top of them; the other shared
  repos stay read-only (owned by `dots`).
- `deploy` runs in phases: the shared base (`shell`, `nyx`, settings seed)
  first, the niri payload and remaining shared repos next, and the overlays
  last, so a base deploy can never wipe an applied overlay.
- `desktop` keeps every overlay in sync with the selected session and delegates
  the display-manager session entry to the `niri-login` flow.
- `setup` auto-runs the system package phase when `niri` is missing, and only
  keeps an existing desktop choice (for example one set by a parallel `dots`).
- Overlay deploys now exclude all `*.md` files (previously only `README.md`).

### Fixed

- Stale shared `shell`/`nyx` bases (which produced a stale `SystemMonitor` and
  broken notifications) are now refreshed by pulling and redeploying them on
  install/update.

### Removed

- Inline user-local SDDM session-file writing from `desktop`/`install`; the
  session entry is now managed system-wide by the `niri-login` repo (`login`),
  which display managers actually scan.

## [0.1.0] - 2026-10-08

### Added

- `dotsniri` meta installer/updater for the equisdots niri stack, parallel to
  `dots` and fully isolated from the `equisdots` org.
- Modular library layout: `lib/{common,repos,deploy,desktop,doctor,system}.sh`
  behind the thin `bin/dotsniri` entry point.
- Repo registry with explicit `own` (niri, niri-shell, niri-meta) and `shared`
  (palettes, theme-sync, davincix, timex, login, background) kinds; shared
  clones are consumed read-only from the `equisdots` clone root.
- Deploy map: `niri` -> `~/.config/niri`, `niri-shell` overlay ->
  `~/.config/hypr/scripts/quickshell` (conditional merge), shared palettes ->
  `.../quickshell/dock/palettes`, wrappers into `~/.local/bin`.
- `desktop niri|hyprland|both` selector: writes a state file, mirrors
  `settings.json` `compositor`, manages the user SDDM session file and
  (un)applies the overlay.
- Reverse operations (`reset`, `uninstall`) with confirmation, plus a
  conservative overlay engine that backs up and restores overwritten files.
- `doctor` dependency and config checks, plus `doctor --self-test` that
  syntax-checks the toolkit without requiring niri.
- Deferred, distro-agnostic system integration: a `system` verb and a pluggable
  `system/` directory with Arch and Fedora example templates only.

[Unreleased]: https://github.com/equisdots/niri-meta/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/equisdots/niri-meta/releases/tag/v0.1.0
