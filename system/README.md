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
  (so it never changes the system by accident);
- with `--apply` (or `-y`): asks for confirmation and runs the template, which
  is responsible for any `sudo` work.

`dotsniri setup` runs the same phase with `--apply` when `niri` is missing, so a
fresh machine can be bootstrapped with a single command.

Templates receive the extra arguments given to `dotsniri system` and must honor
`--dry-run`, `-y/--yes` and `--help`.

## Templates

| Template | Distro | Example content |
| --- | --- | --- |
| `install-arch.sh` | Arch Linux (`ID=arch`) and `ID_LIKE=arch` | `pacman -S --needed ...` |
| `install-fedora.sh` | Fedora (`ID=fedora`) and `ID_LIKE=fedora` | `dnf install ...` |

Both are examples only. Copy one to `system/install-<your-id>.sh`, review the
package list and adapt it. Use `. /etc/os-release` values (`ID`, `ID_LIKE`) to
branch for derivatives; the resolver already falls back to `ID_LIKE`.

## What the core deliberately does not do

- Install packages, fonts or the SDDM theme.
- Register system sessions, PAM services or portals.
- Touch anything under `/usr`, `/etc` or `/lib`.

The one exception is the display-manager session entry: `dotsniri login
install|remove|status` places `niri.desktop` in a system-scanned
`wayland-sessions` directory (with `sudo`) through the own `niri-login` repo,
because display managers do not scan the user-local path. It is skipped when the
distro already ships a niri session entry. The SDDM login theme itself is owned
by the shared `equisdots/login` repo and is installed system-wide by
`dots system` (or by an adapted template here).

Notifications are owned by the Quickshell shell. Do not run `mako`, `dunst` or
any other notification daemon alongside it: another daemon takes over
notifications and the shell palette is not applied. `dotsniri doctor` warns when
one is running.
