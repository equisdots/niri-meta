# equisdots niri — niri-meta

Meta installer and updater for the **equisdots niri desktop stack**, parallel
to the `equisdots/dots` meta. It is a separate command (`dotsniri`) and a
separate clone root (`~/.local/share/equisdots-niri`), so a parallel `dots`
install is never modified and the two stacks can coexist on the same machine.

`dotsniri` owns the niri compositor, the niri overlays and the display-manager
session entry. It also deploys the shared Quickshell `shell` base, the shared
`hyprland` helper scripts, the niri app configs, the plugin standard (`plugin-api`,
`plugin-sdk`, the `plugins` hub), the plugin set and the merged settings, so it
works standalone without `dots`. The remaining shared `equisdots` repos are
consumed read-only from `~/.local/share/equisdots` and remain owned by `dots`.

## Command

```sh
git clone https://github.com/equisdots/niri-meta.git
cd niri-meta
./bin/dotsniri install          # full install: repos + deploy + system packages
./bin/dotsniri desktop niri     # select niri as the default session
./bin/dotsniri doctor           # check binaries, clones, deploy and config
```

After the first `install`, a wrapper is placed at `~/.local/bin/dotsniri`, so
the command is available from anywhere. Remote bootstrap:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/equisdots/niri-meta/main/bin/dotsniri) install
```

The bootstrap clones the meta into `~/.local/share/equisdots-niri/niri-meta` if
it is absent. If the clone already exists it is fetched and hard-reset to
`origin/main` first, so the one-liner always runs the latest code. When `git`
is missing, the bootstrap falls back to the `main` source tarball
(`curl`/`wget` + `tar`), then the normal preflight runs the system phase and
installs the missing runtime tools.

Remaining limitation: the one-liner cannot install packages before the meta
exists, so it needs `git`, or `curl`/`wget` + `tar`, on a bare machine. With
neither available, install one of them first (for example
`sudo pacman -S git`) and re-run the command.

### Bootstrap preflight

`install`, `deploy` and `update` check `git`, `rsync` and `jq` first. If one is
missing and a `system/install-<distro>.sh` template exists, the system phase
runs first (after the usual confirmation) and the check is retried. Without a
matching template, `dotsniri` stops with the exact missing tools and a manual
install instruction.

### Command surface

| Command | What it does |
| --- | --- |
| `setup` | `install` everything (payload + full system phase), then default to niri |
| `install` | clone/update the own repos plus the shared bases, deploy, run the full system phase (packages, xwww, PAM, font, SDDM theme when SDDM is active), install the user app configs and the login entry; `--no-system` keeps it payload-only |
| `deploy` | deploy from the existing clones (no clone, update or packages), in phases |
| `update` | pull the own repos plus the shared bases, then re-deploy |
| `list` | managed repos with their kind (`own` / `shared`) and state |
| `doctor` | binaries, clones, shell base, plugin standard/default plugins, shared scripts, niri shell backend, overlays, units/portal/PAM, settings and `niri validate` |
| `doctor --self-test` | syntax-check the toolkit (`bash -n`); works without niri |
| `reset` | remove the niri deploy (config, units, portal), drop the own clones, reinstall everything from origin/main, including the system phase (`--no-system` skips packages) |
| `uninstall` | reverse the deploy (overlays, units, portal, login entry, wrappers); clones and config kept |
| `desktop <niri\|hyprland\|both>` | default session, `settings.json` mirror, all overlays in sync, login entry |
| `login <install\|remove\|status>` | manage the DM session entry system-wide (via `niri-login`, sudo) |
| `system [--apply] [--pam\|--no-pam] [--xwww\|--no-xwww] [--font\|--no-font] [--login\|--no-login]` | install distro packages and run the integration steps; the SDDM theme is installed automatically when SDDM is the active DM, `--login` forces it and `--no-login` skips it |
| `xwww [--force]` | install/align the pinned `xwww-daemon` release (sudo) |
| `plugins [list\|available\|add\|remove\|enable\|disable]` | manage the plugin set by the standard convention (parity with `dots plugins`) |
| `version` | print the `dotsniri` version |
| `help` | usage |

Global flags: `-y/--yes` (non-interactive), `-n/--dry-run` (print, change
nothing), `-h/--help`.

## Repos it manages

`own` repos are cloned into `~/.local/share/equisdots-niri/<repo>`, updated by
`dotsniri` and deployed by it. `shared` repos live in
`~/.local/share/equisdots/<repo>`: `dotsniri` clones them if missing. The shared
bases that `dotsniri` deploys (`hyprland` scripts, `shell`, `plugin-api`,
`plugin-sdk`, `plugins`, `nyx`, `timex`) are pulled and redeployed too; the
remaining shared repos are read-only and are only updated by `dots`. Pulling a
shared clone never edits it.

| Kind | Repo | Role |
| --- | --- | --- |
| own | [niri](https://github.com/equisdots/niri) | niri compositor config (`config.kdl` + modules + scripts + units/portal) and the standalone app configs (`config/apps`, kitty/starship/nvim installer) |
| own | [niri-shell](https://github.com/equisdots/niri-shell) | shell overlay (Niri backend, niri scripts) merged into the shared shell |
| own | [nyx-niri](https://github.com/equisdots/nyx-niri) | nyx mascot island overlay (compositor-neutral) merged into the shared shell |
| own | [niri-login](https://github.com/equisdots/niri-login) | Wayland session entry installer (so DMs list "Niri") |
| own | [plugins-niri](https://github.com/equisdots/plugins-niri) | niri-specific plugin implementations (screenshots/recording); preferred over the shared hub |
| own | niri-meta | this meta installer |
| shared | [hyprland](https://github.com/equisdots/hyprland) | shared helper scripts still called by the niri keybinds/autostart and the PAM file (read-only; its compositor config is never deployed) |
| shared | [shell](https://github.com/equisdots/shell) | Quickshell desktop UI (pulled and deployed as the base for the niri-shell overlay) |
| shared | [plugin-api](https://github.com/equisdots/plugin-api) | plugin manifest schema, host API version and compat evaluator |
| shared | [plugin-sdk](https://github.com/equisdots/plugin-sdk) | QML host kit installed at `core/sdk` |
| shared | [plugins](https://github.com/equisdots/plugins) | plugin hub: standard, concentration folder and install registry |
| shared | [nyx](https://github.com/equisdots/nyx) | mascot island plugin (deployed as a root-level plugin; base for the nyx-niri overlay) |
| shared | [palettes](https://github.com/equisdots/palettes) | base16 palette data + schema |
| shared | [theme-sync](https://github.com/equisdots/theme-sync) | cross-app theming engine |
| shared | [davincix](https://github.com/equisdots/davincix) | wallpaper kernel |
| shared | [timex](https://github.com/equisdots/timex) | time/weather plugin (default plugin set) |
| shared | [login](https://github.com/equisdots/login) | static SDDM greeter |
| shared | [background](https://github.com/equisdots/background) | wallpaper scenes |

## Deploy map

The shared data root stays `~/.config/hypr` (settings.json, palettes,
wallpapers, shell). Only the compositor config moves, to `~/.config/niri`.
`deploy` runs in four phases so the shared base and plugin host are laid down
first and the overlays are applied last, which means a base or plugin deploy can
never wipe an applied overlay:

1. shared base: the `hyprland` scripts, `shell`, `plugin-api`,
   `plugin-sdk`, the `plugins` registry and the settings merge;
2. plugins: `nyx` plus the default plugin set (`screenshots`, `timex`,
   `rss-reader`, `clipboard`, `quicknotes`, `file-search`, `sysmon`, `keybinds`);
3. niri payload and the remaining shared repos;
4. overlays: `niri-shell`, then `nyx-niri`.

| Source | Destination | Notes |
| --- | --- | --- |
| `niri` `config/niri/` | `~/.config/niri/` | compositor config; generated/user files preserved |
| `niri` `scripts/` | `~/.config/niri/scripts/` | session helper scripts (made executable) |
| `niri` `systemd/*.service` | `~/.config/systemd/user/` | copied, **not enabled** (autostart owns the daemons); `daemon-reload` is best effort |
| `niri` `portals/niri-portals.conf` | `~/.config/xdg-desktop-portal/niri-portals.conf` | per-user portal backend selection, no sudo |
| `hyprland` `scripts/*.sh` | `~/.config/hypr/scripts/` | shared helpers (`qs_manager`, `lock`, `volume`, `brightness`, `reload`, `init`, listeners); no `--delete` |
| `plugins-niri` `plugins/<id>` | `$QS/ui/plugins/<id>` + `~/.config/hypr/plugins/<id>` | niri plugin overrides; re-deployed after the overlays |
| `background` `scenes/` | `~/.config/hypr/wallpapers/` | interactive wallpaper scenes for davincix; refreshed on every deploy |
| `niri` `config/apps/rofi/` + `cava/` | `~/.config/rofi/` + `~/.config/cava/` | copied when missing/changed; an existing dir is backed up under `~/.local/state/equisdots-niri/backups/{rofi,cava}-*` |
| `install` app configs | `~/.local/bin/xtop`, `~/.config/xtop`, `~/.local/share/fonts` | xtop from source, Hack Nerd Font (system-wide for SDDM) and the wallpaper scenes; `DOTSNIRI_NO_*` skip flags |
| `hyprland` `config/pam.d/quickshell` | `/etc/pam.d/quickshell` | system phase only, sudo, prompt/`--pam`, backs up an existing service |
| `shell` (base) | `~/.config/hypr/scripts/quickshell/` | Quickshell UI; `dock/`, `ui/plugins/`, `core/sdk/`, the plugin contract files and `docs/` excluded |
| `plugin-api` | `.../quickshell/plugin-api.json` + `core/scripts/plugins_compat.sh` | normative contract + compat evaluator |
| `plugin-sdk` | `.../quickshell/core/sdk/` | QML host kit |
| `plugins` | `.../quickshell/plugins-registry.json` | install registry copy for the Plugins panel |
| `<plugin>` | `.../quickshell/ui/plugins/<id>/` + `~/.config/hypr/plugins/<id>/` | whole plugin UI + runtime subset (manifest, hypr.lua, scripts, settings seed) |
| `nyx` (plugin) | `.../quickshell/ui/plugins/nyx/` + `~/.config/hypr/plugins/nyx/` | mascot island plugin |
| `default_settings.json` | `~/.config/hypr/settings.json` and `default_settings.json` | defaults refreshed from the shared `hyprland` clone (vendored fallback), then merged with user values; user choices never overwritten |
| `niri-shell` overlay | `~/.config/hypr/scripts/quickshell/` | conditional merge; overwritten files are backed up |
| `nyx-niri` overlay | `~/.config/hypr/scripts/quickshell/ui/plugins/nyx/` | conditional merge; compositor-neutral mascot island |
| `palettes` `*.json`, `community/` | `.../quickshell/dock/palettes/` | `cp -f`, user palettes and editor edits survive |
| `theme-sync` | `~/.local/bin/theme-sync` | only installed if missing |
| `davincix` | `~/.local/bin/davincix` | only installed if missing |
| `login` | system SDDM theme | system phase; auto when SDDM is active, `--login` forces a switch, `--no-login` skips |
| `login` | system `wayland-sessions/niri.desktop` | installed by `dotsniri login` (sudo); skipped if the distro provides one |
| `background` | none | consumed by davincix / xwww at runtime |
| this repo | `~/.local/bin/dotsniri` | always refreshed |

### Settings merge

`deploy` uses the same contract as `dots`: seed `settings.json` when absent,
refresh the managed `default_settings.json` from the shared `hyprland` clone
(vendored `share/default_settings.json` as fallback), then merge defaults + the
user's file with `jq`. The merge renames a legacy `dock` block to `bar`, drops
retired keys (`serpbar`, `openGuideAtStartup`, `topbarHelpIcon`, `monitors`),
adds new sections/keys (`bar.enabled`, `plugins`, ...), and expands a leading
`~` in `wallpaperDir` to `$HOME`. User values always win.

The overlay engine stores a per-overlay manifest and backups under
`~/.local/state/equisdots-niri/overlay/<overlay>/{manifest,backup}`, **outside**
the shell directory, so a parallel `dots update` (which rsyncs the shell with
`--delete`) cannot destroy the ability to restore the baseline. Each overlay
(niri-shell, nyx-niri) has its own namespace, so they apply and remove
independently.

## The shell overlays

Overlay repos (`niri-shell`, `nyx-niri`) ship their payload under `overlay/`,
`shell/` or the repo root (in that order of preference). Applying an overlay
copies those files into the live shell, backing up every file it overwrites
(`.md` files are skipped). Removing it restores the backups and deletes the
files it added, leaving a clean Hyprland shell. Each overlay has its own
manifest/backup namespace under `~/.local/state/equisdots-niri/overlay/<name>`,
so overlays do not clobber each other.

Overlays are applied for `desktop niri` and `desktop both`, and removed for
`desktop hyprland`. This is the core coexistence rule: a shared file is never
replaced by a niri-only variant unless the niri session is selected.

## Coexistence with `dots`

- Different command (`dotsniri`), different clone root
  (`~/.local/share/equisdots-niri`). A parallel `dots` install under
  `~/.local/share/equisdots` is never modified.
- Shared repos (`hyprland`, `shell`, `plugin-api`, `plugin-sdk`, `plugins`,
  `nyx`, `palettes`, `theme-sync`, `davincix`, `timex`, `login`, `background`)
  are cloned if missing; the `hyprland` scripts and the shell/plugin bases
  are deployed, so `dotsniri` works standalone without `dots`. The shared
  `hyprland`, `shell` and `nyx` clones are kept current by `dotsniri` (they are
  the base the keybinds/overlays sit on); the other shared clones are read-only
  and only `dots update` changes them.
- The shared `hyprland` compositor config (`config/hypr/*.lua`) is never
  deployed; only `scripts/*.sh` and (system phase) `config/pam.d/quickshell`
  are consumed. Rofi/cava come from the niri repo, not from `hyprland`.
- `niri/systemd/*.service` are copied but not enabled: `modules/autostart.kdl`
  already starts the shell, xwww, the focus daemon and, when the niri repo
  ships the hook, `niri_idle_mode.sh boot`. Enabling the matching units would
  start every daemon twice; `niri_idle_mode.sh` drives the deployed
  `swayidle.service` on demand instead.
- The niri portal override is user-level (`~/.config/xdg-desktop-portal`) and
  needs no sudo; `reset`/`uninstall` remove it together with the units.
- The niri compositor config is isolated at `~/.config/niri`; Hyprland's
  `~/.config/hypr/*.lua` is untouched.
- The overlays are conditional and reversible, and they re-apply cleanly after
  a `dots update` wipes the shell (`dotsniri deploy`).
- `desktop` writes an authoritative state file and mirrors the choice into
  `settings.json` under `compositor` with `jq`, preserving every user value.

### Session selection

`desktop <mode>` sets the default and manages the display-manager session entry
through `niri-login` (installed system-wide, skipped when the distro already
ships one):

- `niri` — deploy the overlays, default to niri.
- `both` — deploy the overlays; both sessions are available.
- `hyprland` — remove the overlays and the session entry, leave a pure
  Hyprland shell.

At runtime the shared shell picks its backend from **`XDG_CURRENT_DESKTOP`**:
`niri-session` exports `XDG_CURRENT_DESKTOP=niri`, so the shell loads the Niri
backend; any other desktop falls back to Hyprland.

## Diagnostics

`tools/diagnose.sh` is a read-only report for debugging why a niri session does
not start from the display manager:

```sh
bash tools/diagnose.sh | tee ~/niri-report.txt
```

It collects the system and display manager, GPU, niri binaries and version,
session entries, SDDM config, `niri validate`, session logs, journals, logind
state, dependencies and the equisdots state. Nothing modifies the system.

## System integration

Installing packages, fonts, the SDDM theme, PAM and xwww is **delegated** to a
pluggable `system/` directory containing example templates only
(`install-arch.sh`, `install-fedora.sh`). `install`, `setup` and `reset` run
that phase by default (idempotent), even when niri is already installed;
`--no-system` keeps them payload-only. The `system` verb exposes the same phase
directly. It resolves the distro by `ID` and then by each `ID_LIKE` token,
prints the matching template and, with `--apply`, runs it. See
[`system/README.md`](system/README.md).

The system phase also owns these integration steps:

- **xwww**: installs/aligns the pinned, checksum-verified release (source-build
  fallback) into `/usr/local/bin`; `dotsniri xwww` exposes the same helper.
  `--no-xwww` skips it.
- **PAM**: installs `hyprland/config/pam.d/quickshell` to `/etc/pam.d/quickshell`
  with sudo. Without it the lock screen cannot authenticate. It prompts first;
  `--pam` opts in explicitly, `--no-pam` skips it, and an existing service file
  is backed up to `/etc/pam.d/quickshell.backup`.
- **SDDM theme**: runs `login/install.sh` automatically when SDDM is already
  the active display manager (safe: it cannot switch anything). `--login`
  forces it even if another DM owns `display-manager.service`, and `--no-login`
  skips it. `dotsniri login` itself only manages the niri Wayland session
  entry, not the theme.

The user-level systemd units and the portal override are deployed by `deploy`
(no sudo); `reset`/`uninstall` clean them up.

## Requirements

`git`, `rsync`, `jq`, plus the niri stack: `niri`, `xwayland-satellite`,
`quickshell` (`qs`), `xwww-daemon`, `swayidle`, `cava`, `playerctl`,
`wl-clipboard` (`wl-paste`), `cliphist`, `brightnessctl`, `pamixer`, `ddcutil`,
`libnotify` (`notify-send`), `python` (the `python3` binary), `kitty` and
`rofi`. The shared scripts also use `curl` and `pactl` (PipeWire/PulseAudio).
`dotsniri doctor` reports what is missing, and `dotsniri doctor --self-test`
verifies the toolkit without requiring niri. Notifications are provided by the
shell, so no separate daemon (`mako`, `dunst`) should be running.

## Layout

```
bin/dotsniri        thin entry point (flags + dispatch)
lib/common.sh       constants, logging, flags, usage
lib/repos.sh        repo registry, clone/update/list
lib/deploy.sh       deploy, overlay engine, reset/uninstall
lib/desktop.sh      session selector, settings.json, session entry
lib/login.sh        display-manager session entry (niri-login, sudo)
lib/doctor.sh       checks and self-test
lib/system.sh       deferred system hook, PAM/login integration, preflight
lib/xwww.sh         pinned xwww release/source installer
share/              vendored defaults (settings fallback)
system/             pluggable distro templates (examples only)
tools/diagnose.sh   read-only session startup report
```

## License

MIT — see [LICENSE](LICENSE).
