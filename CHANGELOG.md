# Changelog

All notable changes to `niri-meta` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Own repo `niri-login` and the `login` command (`install|remove|status`) to
  place the niri Wayland session entry in a **system-scanned**
  `wayland-sessions` directory (with sudo). Display managers do not scan the
  user-local path, which is why the entry did not appear before. `install` and
  `desktop` now ensure the entry, and `doctor` checks for it.
- Own repo `nyx-niri` (compositor-neutral mascot island overlay) and its
  conditional deploy into `.../quickshell/ui/nyx`.
- Shared repos `shell` and `nyx` are now cloned and their base deployed, plus a
  vendored `share/default_settings.json` seeded only when `settings.json` is
  absent. `dotsniri` is now standalone: it no longer requires `dots` to provide
  the Quickshell shell or the settings seed.
- Namespaced multi-overlay engine
  (`~/.local/state/equisdots-niri/overlay/<name>`) so `niri-shell` and
  `nyx-niri` apply and remove independently.
- `doctor` check for the Quickshell shell base (`$QS/Shell.qml`).

### Changed

- `deploy` runs in phases: shared base (`shell`, `nyx`, settings seed) first,
  the niri payload next, and the overlays last, so a base deploy can never wipe
  an applied overlay.
- `desktop` keeps every overlay in sync with the selected session.

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
