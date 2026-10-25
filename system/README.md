# system integration

System-level integration for the niri stack is **deferred** and kept out of the
core on purpose. `dotsniri` never hardcodes distro packages and never depends
on `equislinux`; the core is distro-agnostic. This directory is the pluggable
seam.

## How it works

`dotsniri system` resolves the distro from `/etc/os-release`: it tries the
distro `ID` first, then each token of `ID_LIKE`, so `ID=x` + `ID_LIKE=arch`
finds `system/install-arch.sh`. It:

- without `--apply`: prints the template path and runs it with `--dry-run`
  (so it never changes the system by accident), then prints the integration
  plan;
- with `--apply` (or `-y`): asks for confirmation and runs the template, which
  is responsible for any `sudo` package work.

After the template, the system phase owns these integration steps:

| Step | Default | Flags | What it does |
| --- | --- | --- | --- |
| xwww | on | `--no-xwww` | Installs/aligns the pinned `xwww` release (checksum-verified, source-build fallback) into `/usr/local/bin`. `dotsniri xwww` runs the same helper. |
| PAM | prompt | `--pam`, `--no-pam` | Installs `/etc/pam.d/quickshell` from the shared `hyprland` clone (sudo). Backs up an existing file; without it the lock screen cannot authenticate. `install`/`reset` pass `--pam`. |
| Font | on | `--no-font` | Installs Hack Nerd Font system-wide for SDDM/login. |
| SDDM | auto | `--login`, `--no-login` | Runs `login/install.sh` automatically when SDDM is already the active display manager (safe). `--login` forces the theme and may switch `display-manager.service` to SDDM; `--no-login` skips it. |
| NVIDIA | offer | `--nvidia`, `--no-nvidia` | On Arch-like systems, detects an NVIDIA GPU and offers the nvidia-dkms/boot setup (kernel headers, mkinitcpio, nvidia_drm.modeset, nouveau blacklist, nvidia-drm options, power services, optional envycontrol rule). `--nvidia` forces it and fails without a GPU; `--no-nvidia` skips it. AMD/Intel stay distro-managed. |

`dotsniri install`, `setup` and `reset` run the full system phase by default,
even when niri is already installed; `--no-system` keeps them payload-only.
`deploy` and `update` do not install packages. All of them run the preflight
described below.

Templates receive the extra arguments given to `dotsniri system` and must honor
`--dry-run`, `-y/--yes` and `--help`.

Dependency failures are fatal. The Arch template retries the core transaction
package by package to identify the culprit and exits non-zero if any required
package fails; AUR packages are installed one by one and also abort on failure.
`cmd_system` checks the template exit status and returns non-zero if the
template, xwww, PAM, font, SDDM theme or an accepted NVIDIA setup fails. Only
explicit flags skip a step.

## Bootstrap preflight

Before `install`/`deploy`/`update`, `dotsniri` checks `git`, `rsync` and `jq`.
If one is missing and a matching template exists, it runs the system phase
first (after confirmation), then retries. Without a template it stops with the
missing tools and a manual instruction. The remote one-liner still needs `git`
(or `curl`/`wget` + `tar`) before the meta exists; see the README.

## Templates

| Template | Distro | Example content |
| --- | --- | --- |
| `install-arch.sh` | Arch Linux (`ID=arch`) and `ID_LIKE=arch` | `pacman -S --needed ...` + optional AUR helper |
| `install-fedora.sh` | Fedora (`ID=fedora`) and `ID_LIKE=fedora` | `dnf install ...` |

Both are examples only. Copy one to `system/install-<your-id>.sh`, review the
package list and adapt it. Use `. /etc/os-release` values (`ID`, `ID_LIKE`) to
branch for derivatives; the resolver already falls back to `ID_LIKE`.

AUR/COPR/third-party packages (`mpvpaper` and `bibata-cursor-theme` on Arch;
`mpvpaper` and `rofi-emoji` on Fedora) are installed separately and never fail
the core transaction. They are still required: each one is attempted and a
failure aborts the system phase instead of being silently skipped (`envycontrol`
is installed only by the NVIDIA step). `mpvpaper` is
AUR-only on Arch and must stay in the optional group: one unknown pacman
target aborts the whole core install. If the core transaction fails for any
other reason, the Arch template retries every core package individually so
essentials such as `qt6-multimedia` still land.

The Arch template also ensures an AUR helper the same way the Hyprland
installer does: it prefers `paru`, then `yay`, and builds `yay` from the AUR
with `git` + `base-devel` when neither is present. Package names drift between
releases, so review the list for your distro before applying it.

`qt6-multimedia` (Fedora `qt6-qtmultimedia`) is part of the core list on
purpose: the davincix wallpaper picker and video previews import
`QtMultimedia`, and without the QML module the picker fails to load entirely.

## What the core deliberately does not do

- Install packages, fonts or the SDDM theme without the system phase.
- Register system sessions, PAM services or portal files under `/usr` or
  `/etc` outside the explicit system-phase steps above.
- Change the display manager silently: the SDDM theme auto-runs only when SDDM
  is already active; switching another DM requires `--login`.
- Install GPU drivers without an offer: on Arch-like systems the NVIDIA setup
  is offered (or forced with `--nvidia`); AMD/Intel drivers stay distro-managed.

The display-manager session entry is a separate command: `dotsniri login
install|remove|status` places `niri.desktop` in a system-scanned
`wayland-sessions` directory (with `sudo`) through the own `niri-login` repo,
because display managers do not scan the user-local path. It is skipped when the
distro already ships a niri session entry.

The user-level niri systemd units and `niri-portals.conf` are deployed by
`dotsniri deploy` (no sudo) and removed by `reset`/`uninstall`. Units are
copied but **not enabled**: the niri autostart already starts the shell, xwww
and the focus daemon (and `niri_idle_mode.sh boot` when the repo ships it), so
enabling the same units would duplicate daemons.

Notifications are owned by the Quickshell shell. Do not run `mako`, `dunst` or
any other notification daemon alongside it: another daemon takes over
notifications and the shell palette is not applied. `dotsniri doctor` warns when
one is running.
