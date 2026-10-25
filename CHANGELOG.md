# Changelog

All notable changes to `niri-meta` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `install` now runs the niri repo's standalone app config installer,
  including xtop (built from `xtop-cli/xtop` with cargo), the interactive
  wallpaper scenes and Hack Nerd Font system-wide for SDDM. `DOTSNIRI_NO_APPS`
  / `DOTSNIRI_NO_XTOP` / `DOTSNIRI_NO_SCENES` / `DOTSNIRI_NO_SYSTEM_FONT` skip
  steps. `deploy`/`update` stay offline.
- Own repo `plugins-niri`: niri-specific plugin implementations. The first is
  `plugins/screenshots`, which keeps the standard plugin UI/bar contract but
  calls `niri_screenshot.sh` / `niri_record.sh` directly. `deploy` prefers
  `plugins-niri/plugins/<id>` over the shared hub and re-deploys the niri
  plugins after the shell overlays, so an old `niri-shell` backup cannot
  restore the Hyprland implementation.
- `deploy` copies the interactive wallpaper scenes from the `background`
  clone into `~/.config/hypr/wallpapers` on every deploy/update, so davincix
  and the wallpaper picker are never empty after a fresh install.
- `deploy` installs rofi/cava from the niri repo (`config/apps/`) instead of
  consuming `hyprland/config/rofi`. Existing dirs are backed up under
  `~/.local/state/equisdots-niri/backups/{rofi,cava}-*`.
- `doctor` checks cava, the wallpaper directory, the system-wide Hack Nerd
  Font and xtop.
- `system` installs Hack Nerd Font system-wide for SDDM (`--no-font` skips).
  `rust`/`cargo` is in the Arch/Fedora package templates for the xtop build.
- `system/install-arch.sh`: AUR-helper parity with the Hyprland installer. It
  prefers `paru`, then `yay`, and builds `yay` from the AUR with `git` +
  `base-devel` when neither is present, so `mpvpaper`, `envycontrol` and
  Bibata are installed instead of skipped.
- `system` package lists: `qt6-multimedia` (Fedora `qt6-qtmultimedia`) is now
  core because the davincix wallpaper picker and video previews import
  `QtMultimedia`; the Arch/Fedora lists also gain `inotify-tools`,
  `rofi-emoji`, `lm_sensors`, `iw`, `librsvg`, `xdg-utils`, `xdg-user-dirs`
  and `pipewire-alsa`. `mpvpaper` is AUR-only, so it lives in the optional
  group and can never abort the core transaction. If the core transaction
  still fails, every core package is retried individually so the essentials
  (notably `qt6-multimedia`) are installed.
- `doctor` now requires `inotifywait` and `socat`, and checks that the
  QtMultimedia QML module is installed (a missing module silently breaks the
  wallpaper picker).

### Fixed

- `deploy`/`generated/env.kdl`: the wallpaper directory is resolved from
  `settings.json.wallpaperDir` (with `~` expansion) instead of assuming
  `~/.config/hypr/wallpapers`, so scenes and davincix use the same directory
  the picker reads.
- `reset` is now offline-safe: it checks GitHub reachability before deleting
  anything, snapshots the deployed shell/config/settings under
  `~/.local/state/equisdots-niri/backups/reset-*`, and restores that snapshot
  if the reinstall step fails.
- Offline/incomplete updates are now fail-safe: `install` and `update` abort
  before deploying if a required repo cannot be obtained, `deploy` refuses to
  run with a missing/incomplete or dirty managed clone, `deploy_shell` verifies
  the shell payload and snapshots the live tree under
  `~/.local/state/equisdots-niri/backups/shell-*.tar.gz` (last 3), and
  `overlay_apply` refuses an empty overlay source. The current installation is
  never touched when these checks fail.
- `deploy`: a fresh `settings.json` is now merged after seeding instead of
  returning early, so the shipped `wallpaperDir: "~/.config/hypr/wallpapers"`
  is expanded to `$HOME` on the first install.
- `deploy`: seed `~/.config/niri/generated/env.kdl` with literal HOME-derived
  paths and the appScale block.
- `repos`: pull every shared repo the stack consumes read-only (palettes,
  theme-sync, davincix, login, background and the shared scripts); local
  changes are never discarded.
- `system/install-arch.sh`: use the real Arch package name `adw-gtk-theme` and
  move `bibata-cursor-theme` to the optional/AUR group.

## [0.3.0] - 2026-10-24

### Added

- Shared `hyprland` repo parity: the read-only clone now supplies the helper
  scripts the niri keybinds/autostart call (`qs_manager`, `lock`, `volume`,
  `brightness`, `reload`, `init`, the listeners and their libs) into
  `~/.config/hypr/scripts/` **without `--delete`**, plus the rofi themes into
  `~/.config/rofi/` (existing dir backed up under the dotsniri state dir). Its
  compositor config is never deployed.
- `niri/systemd/*.service` deploy to `~/.config/systemd/user` (copied, not
  enabled) with a best-effort `systemctl --user daemon-reload`, and
  `niri/portals/niri-portals.conf` deploys per-user to
  `~/.config/xdg-desktop-portal/` (no sudo). `reset`/`uninstall` clean both.
  Idle ownership is documented: when the niri autostart starts
  `niri_idle_mode.sh boot`, swayidle is not enabled (no duplicate daemon).
- Full settings-merge parity with `dots`: `settings.json` is seeded when
  absent, `default_settings.json` is refreshed from the shared `hyprland`
  clone (vendored fallback), then defaults + user values are merged with `jq`:
  `dock` → `bar`, legacy keys dropped, new sections/`bar.enabled`/`plugins`
  added, and a leading `~` in `wallpaperDir` expanded to `$HOME`. User choices
  are never overwritten.
- Fresh-bootstrap preflight: `install`/`deploy`/`update` check `git`, `rsync`
  and `jq`; when a distro template exists they run the system phase first and
  retry. The curl one-liner now falls back to the source tarball
  (`curl`/`wget` + `tar`) when git is unavailable.
- System integration: pinned `xwww` release installer (`dotsniri xwww`, source
  build fallback, `--dry-run`), PAM service installation for the Quickshell
  lock screen (`/etc/pam.d/quickshell`, prompt/`--pam`, backup, no silent
  changes), and SDDM theme installation only with the explicit
  `system --login` opt-in (never changes the display manager silently).
- `doctor` checks the shared scripts, rofi themes, niri units/portal, the
  `quickshell` PAM service, the `wallpaperDir` literal `~`, and a
  shared-scripts/system-package summary.
- Arch/Fedora templates now include the missing runtime packages (kitty, rofi,
  playerctl, brightnessctl, pamixer, ddcutil, nautilus, pavucontrol,
  network-manager-applet, blueman, gnome-keyring, a polkit agent, qt5ct/qt6ct,
  noto fonts, adw-gtk3, papirus, bibata, fd, ripgrep, imagemagick, ffmpeg,
  cava, power-profiles-daemon, satty, zbar, starship, zsh, ...) and install
  optional/AUR/COPR packages separately and non-fatally. `python3` was
  corrected to `python` on Arch.
- Plugin-standard parity with the merged Hyprland stack: shared repos
  `plugin-api`, `plugin-sdk` and `plugins` are cloned and deployed; the deploy
  installs `plugin-api.json` + the compat evaluator, `core/sdk/`, the
  `plugins-registry.json` copy and the default plugin set (`screenshots`,
  `timex`, `rss-reader`, `clipboard`, `quicknotes`, `file-search`, `sysmon`,
  `keybinds`) by the generic convention (whole UI under `ui/plugins/<id>`,
  runtime manifest/`hypr.lua`/`scripts` under `~/.config/hypr/plugins/<id>`,
  plugin-owned settings seeded once, standalone launchers generated).
- Nyx is deployed as the root-level plugin it is now (`ui/plugins/nyx` +
  `~/.config/hypr/plugins/nyx`); the `nyx-niri` overlay follows it.
- `doctor` checks the plugin standard, the Plugins panel and every default
  plugin payload, plus `bar.enabled` in `settings.json`.
- `dotsniri plugins` (`list`, `available`, `add`, `remove`, `enable`,
  `disable`): same convention as `dots plugins`, resolving sources from the
  plugin hub and the root-level `nyx`/`timex` clones. The Plugins page install
  button uses it (falling back to `dots` when present).
- `updates.json` and the `~/.local/state/equisdots-niri-version` state: the
  shell's updater popup now reports and applies niri-stack updates
  (`dotsniri update`).
- `share/default_settings.json` re-synced with the current upstream defaults
  (`bar.enabled`, `plugins`, no `barEngine`/`mascots` blocks).

### Fixed

- `plugins enable|disable` (and the list state) now resolve the toggle exactly
  like `shell/core/scripts/plugins_scan.sh`: `scope = manifest.scope ||
  plugins.<id>`, `toggle = manifest.toggle || <scope>.enabled`, written to the
  plugin's own `settings.json`. Manifests with a custom scope (for example
  `nyx`/`mascots`, `batteryplus`) no longer read/write the wrong key.
- `deploy` seeds the single-occurrence generated sections
  (`generated/user-input.kdl`, `generated/user-animations.kdl`,
  `generated/blur.kdl`) from the niri repo's `defaults/` only when missing, so a
  fresh install has the translated input/animation/blur defaults without ever
  duplicating those sections in the assembled config.

### Changed

- `shell` deploy excludes the plugin-owned paths (`ui/plugins/`,
  `core/sdk/`, `plugin-api.json`, `plugins_compat.sh`, `plugins-registry.json`,
  `plugin-*.qml`) and purges the legacy `ui/nyx` location.
- `deploy` now runs in four phases (base + shared hyprland scripts/rofi +
  plugin host, plugins, niri payload + units/portal, overlays).
- Shared repo pulls now include `hyprland` (scripts/rofi are deployed),
  alongside `shell`, `plugin-api`, `plugin-sdk`, `plugins` and `timex`.
- `timex` is no longer deployed as a `~/.local/bin/timex` wrapper +
  `ui/timex`; it ships as a default plugin like on the Hyprland stack.

### Added (previous)

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

[Unreleased]: https://github.com/equisdots/niri-meta/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/equisdots/niri-meta/compare/v0.1.0...v0.3.0
[0.1.0]: https://github.com/equisdots/niri-meta/releases/tag/v0.1.0
