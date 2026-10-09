# equisdots niri — niri-meta

Meta installer and updater for the **equisdots niri desktop stack**, parallel
to the `equisdots/dots` meta. It is a separate command (`dotsniri`) and a
separate clone root (`~/.local/share/equisdots-niri`), so the `equisdots` org
is **never touched**: the two stacks can coexist on the same machine.

`dotsniri` owns the niri compositor and the niri shell overlay. Everything else
is consumed read-only from the shared `equisdots` repos, which stay under
`~/.local/share/equisdots` and are updated by `dots`.

## Command

```sh
git clone https://github.com/equisdots/niri-meta.git
cd niri-meta
./bin/dotsniri install          # clone/update and deploy the niri stack
./bin/dotsniri desktop niri     # select niri as the default session
./bin/dotsniri doctor           # check binaries, clones, deploy and config
```

After the first `install`, a wrapper is placed at `~/.local/bin/dotsniri`, so
the command is available from anywhere. Remote bootstrap:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/equisdots/niri-meta/main/bin/dotsniri) install
```

### Command surface

| Command | What it does |
| --- | --- |
| `setup` | payload install, then default to niri on a fresh install; optional system hook |
| `install` | clone/update the own repos, ensure the shared repos, then deploy |
| `deploy` | deploy from the existing clones (no clone or update) |
| `update` | pull the own repos and re-deploy (shared repos stay read-only) |
| `list` | managed repos with their kind (`own` / `shared`) and state |
| `doctor` | binaries, clones, deploy state and `niri validate` |
| `doctor --self-test` | syntax-check the toolkit (`bash -n`); works without niri |
| `reset` | remove the niri deploy, drop the own clones, reinstall from origin/main |
| `uninstall` | reverse the deploy (overlay, session file, wrappers); clones kept |
| `desktop <niri\|hyprland\|both>` | default session, `settings.json` mirror, overlay toggle |
| `login <install\|remove\|status>` | install the DM session entry system-wide (via `niri-login`, sudo) |
| `system [--apply]` | distro/system hook (deferred; see `system/README.md`) |
| `version` | print the `dotsniri` version |
| `help` | usage |

Global flags: `-y/--yes` (non-interactive), `-n/--dry-run` (print, change
nothing), `-h/--help`.

## Repos it manages

`own` repos are cloned into `~/.local/share/equisdots-niri/<repo>`, updated by
`dotsniri` and deployed by it. `shared` repos are consumed **read-only** from
`~/.local/share/equisdots/<repo>`: `dotsniri` clones them if missing but never
pulls or modifies an existing shared clone.

| Kind | Repo | Role |
| --- | --- | --- |
| own | [niri](https://github.com/equisdots/niri) | niri compositor config (`config.kdl` + modules + scripts) |
| own | [niri-shell](https://github.com/equisdots/niri-shell) | shell overlay (Niri backend, niri scripts) merged into the shared shell |
| own | [nyx-niri](https://github.com/equisdots/nyx-niri) | nyx mascot island overlay (compositor-neutral) merged into the shared shell |
| own | [niri-login](https://github.com/equisdots/niri-login) | Wayland session entry installer (so DMs list "Niri") |
| own | niri-meta | this meta installer |
| shared | [shell](https://github.com/equisdots/shell) | Quickshell desktop UI (base for the niri-shell overlay) |
| shared | [nyx](https://github.com/equisdots/nyx) | mascot island base (base for the nyx-niri overlay) |
| shared | [palettes](https://github.com/equisdots/palettes) | base16 palette data + schema |
| shared | [theme-sync](https://github.com/equisdots/theme-sync) | cross-app theming engine |
| shared | [davincix](https://github.com/equisdots/davincix) | wallpaper kernel |
| shared | [timex](https://github.com/equisdots/timex) | time/weather engine + UI |
| shared | [login](https://github.com/equisdots/login) | static SDDM greeter |
| shared | [background](https://github.com/equisdots/background) | wallpaper scenes |

## Deploy map

The shared data root stays `~/.config/hypr` (settings.json, palettes,
wallpapers, shell). Only the compositor config moves, to `~/.config/niri`.

| Source | Destination | Notes |
| --- | --- | --- |
| `niri` `config/niri/` | `~/.config/niri/` | compositor config; generated/user files preserved |
| `niri` `scripts/` | `~/.config/niri/scripts/` | session helper scripts (made executable) |
| `shell` (base) | `~/.config/hypr/scripts/quickshell/` | Quickshell UI; `dock/` and `ui/nyx/` excluded |
| `nyx` (base) | `~/.config/hypr/scripts/quickshell/ui/nyx/` | mascot island base |
| `share/default_settings.json` | `~/.config/hypr/settings.json` | seeded only when absent; user config is never overwritten |
| `niri-shell` overlay | `~/.config/hypr/scripts/quickshell/` | conditional merge; overwritten files are backed up |
| `nyx-niri` overlay | `~/.config/hypr/scripts/quickshell/ui/nyx/` | conditional merge; compositor-neutral mascot island |
| `palettes` `*.json`, `community/` | `.../quickshell/dock/palettes/` | `cp -f`, user palettes and editor edits survive |
| `theme-sync` | `~/.local/bin/theme-sync` | only installed if missing |
| `davincix` | `~/.local/bin/davincix` | only installed if missing |
| `timex` | `~/.local/bin/timex` + `.../quickshell/ui/timex/` | only installed if missing |
| `login` | system SDDM theme | handled by the system hook |
| `login` | system `wayland-sessions/niri.desktop` | installed by `dotsniri login` (sudo); skipped if the distro provides one |
| `background` | none | consumed by davincix / xwww at runtime |
| this repo | `~/.local/bin/dotsniri` | always refreshed |

The overlay engine stores a per-overlay manifest and backups under
`~/.local/state/equisdots-niri/overlay/<overlay>`, **outside** the shell
directory, so a parallel `dots update` (which rsyncs the shell with `--delete`)
cannot destroy the ability to restore the baseline. Each overlay (niri-shell,
nyx-niri) has its own namespace, so they apply and remove independently.

## The shell overlays

Overlay repos (`niri-shell`, `nyx-niri`) ship their payload under `overlay/`,
`shell/` or the repo root (in that order of preference). Applying an overlay
copies those files into the live shell, backing up every file it overwrites.
Removing it restores the backups and deletes the files it added, leaving a clean
Hyprland shell. Each overlay has its own manifest/backup namespace under
`~/.local/state/equisdots-niri/overlay/<name>`, so overlays do not clobber each
other.

Overlays are applied for `desktop niri` and `desktop both`, and removed for
`desktop hyprland`. This is the core coexistence rule: a shared file is never
replaced by a niri-only variant unless the niri session is selected.

## Coexistence with `dots`

- Different command (`dotsniri`), different clone root
  (`~/.local/share/equisdots-niri`). Nothing under `equisdots` is written.
- Shared repos (shell, nyx, palettes, theme-sync, davincix, timex, login,
  background) are read-only clones. `dotsniri` clones them if missing and
  deploys the base shell/nyx, so it works standalone without `dots`; it never
  pulls or modifies an existing shared clone (that is `dots update`'s job).
- The niri compositor config is isolated at `~/.config/niri`; Hyprland's
  `~/.config/hypr/*.lua` is untouched.
- The niri overlay is conditional and reversible, and it re-applies cleanly
  after a `dots update` wipes the shell (`dotsniri deploy`).
- `desktop` writes an authoritative state file and mirrors the choice into
  `settings.json` under `compositor` with `jq`, preserving every user value.

### Session selection

`desktop <mode>` sets the default and manages a user SDDM session file
(`~/.local/share/wayland-sessions/niri.desktop`, only if no system session
exists):

- `niri` — deploy the overlay, default to niri.
- `both` — deploy the overlay; both sessions are available.
- `hyprland` — remove the overlay, leave a pure Hyprland shell.

At runtime the shared shell picks its backend from **`XDG_CURRENT_DESKTOP`**:
`niri-session` exports `XDG_CURRENT_DESKTOP=niri`, so the shell loads the Niri
backend; any other desktop falls back to Hyprland.

## Deferred system integration

Installing packages, fonts, the SDDM theme, PAM, portals and system sessions is
**deferred** and never hardcoded in the core. The `system` verb delegates to a
pluggable `system/` directory containing example templates only
(`install-arch.sh`, `install-fedora.sh`). `dotsniri system` detects the distro,
prints the matching template and, with `--apply`, runs it. See
[`system/README.md`](system/README.md).

## Requirements

`git`, `rsync`, `jq`, plus the niri stack: `niri`, `xwayland-satellite`,
`quickshell` (`qs`), `xwww-daemon`, `cava`, `playerctl`, `wl-clipboard`
(`wl-paste`), `cliphist`, `brightnessctl`, `pamixer`, `kitty` and `rofi`.
`dotsniri doctor` reports what is missing, and `dotsniri doctor --self-test`
verifies the toolkit without requiring niri.

## Layout

```
bin/dotsniri        thin entry point (flags + dispatch)
lib/common.sh       constants, logging, flags, usage
lib/repos.sh        repo registry, clone/update/list
lib/deploy.sh       deploy, overlay engine, reset/uninstall
lib/desktop.sh      session selector, settings.json, session file
lib/doctor.sh       checks and self-test
lib/system.sh       deferred system hook
system/             pluggable distro templates (examples only)
```

## License

MIT — see [LICENSE](LICENSE).
