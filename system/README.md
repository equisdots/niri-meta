# system integration

System-level integration for the niri stack is **deferred** and kept out of the
core on purpose. `dotsniri` never hardcodes distro packages and never depends
on `equislinux`; the core is distro-agnostic. This directory is the pluggable
seam.

## How it works

`dotsniri system` detects the distro from `/etc/os-release`, looks for
`system/install-<ID>.sh` and:

- without `--apply`: prints the template path and runs it with `--dry-run`
  (so it never changes the system by accident);
- with `--apply` (or `-y`): asks for confirmation and runs the template, which
  is responsible for any `sudo` work.

Templates receive the extra arguments given to `dotsniri system` and must honor
`--dry-run`, `-y/--yes` and `--help`.

## Templates

| Template | Distro | Example content |
| --- | --- | --- |
| `install-arch.sh` | Arch Linux (`ID=arch`) | `pacman -S --needed ...` |
| `install-fedora.sh` | Fedora (`ID=fedora`) | `dnf install ...` |

Both are examples only. Copy one to `system/install-<your-id>.sh`, review the
package list and adapt it. Use `. /etc/os-release` values (`ID`, `ID_LIKE`) to
branch for derivatives.

## What the core deliberately does not do

- Install packages, fonts or the SDDM theme.
- Register system sessions, PAM services or portals.
- Touch anything under `/usr`, `/etc` or `/lib`.

The SDDM login theme itself is owned by the shared `equisdots/login` repo and is
installed system-wide by `dots system` (or by an adapted template here).
