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

After the template, the system phase owns three opt-in integration steps:

| Step | Default | Flags | What it does |
| --- | --- | --- | --- |
| xwww | on | `--no-xwww` | Installs/aligns the pinned `xwww` release (checksum-verified, source-build fallback) into `/usr/local/bin`. `dotsniri xwww` runs the same helper. |
| PAM | prompt | `--pam`, `--no-pam` | Installs `/etc/pam.d/quickshell` from the shared `hyprland` clone (sudo). Backs up an existing file; without it the lock screen cannot authenticate. |
| SDDM | off | `--login` | Runs `login/install.sh`, which installs the SDDM theme **and may switch `display-manager.service` to SDDM**. Never runs without the explicit flag. |

`dotsniri setup` runs the same phase with `--apply` when `niri` is missing, so a
fresh machine can be bootstrapped with a single command. `install`, `deploy` and
`update` also run the preflight described below.

Templates receive the extra arguments given to `dotsniri system` and must honor
`--dry-run`, `-y/--yes` and `--help`.

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

AUR/COPR/third-party packages (`envycontrol`, `gpu-screen-recorder`,
`satty`, `bibata-cursor-theme`) are installed separately and never fail the
core transaction. Package names drift between releases, so review the list for
your distro before applying it.

## What the core deliberately does not do

- Install packages, fonts or the SDDM theme without the system phase.
- Register system sessions, PAM services or portal files under `/usr` or
  `/etc` outside the explicit system-phase steps above.
- Change the display manager silently: the SDDM theme step requires `--login`.

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
