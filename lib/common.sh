#!/usr/bin/env bash
# equisdots-niri · niri-meta
# common.sh — shared constants, logging, global flags and small helpers.
#
# This file is sourced by bin/dotsniri. It is not meant to run on its own.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'common.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

# ── Identity ────────────────────────────────────────────────────────────────
APP="dotsniri"
VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION"

# ── Base directories ────────────────────────────────────────────────────────
# Own clones (the niri stack) and the shared equisdots clones (read-only).
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"

BASE_NIRI="$XDG_DATA_HOME/equisdots-niri"
BASE_SHARED="$XDG_DATA_HOME/equisdots"

# Shared equisdots data root. Strategy A keeps ~/.config/hypr as the data root
# (settings.json, palettes, wallpapers, shell); the compositor config is the
# only thing that moves, to ~/.config/niri.
CFG="$XDG_CONFIG_HOME"
HYPR="$CFG/hypr"
QS="$HYPR/scripts/quickshell"
PALETTES="$QS/dock/palettes"
NIRI_CFG="$CFG/niri"

# User-level integration.
BIN="$HOME/.local/bin"
STATE="$XDG_STATE_HOME/equisdots-niri"
WAYLAND_SESSIONS="$XDG_DATA_HOME/wayland-sessions"

# Overlay bookkeeping. It is kept OUTSIDE $QS on purpose: `dots` rsyncs the
# shared shell with --delete, so anything stored inside $QS would be wiped by a
# `dots update`. Each overlay (niri-shell, nyx-niri, ...) gets its own namespace
# under this root, with its own manifest and backups, so multiple overlays can
# be applied and removed independently.
OVERLAY_ROOT="$STATE/overlay"
DESKTOP_STATE="$STATE/desktop"

# ── Global flags ────────────────────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
HELP=0

# ── Logging ─────────────────────────────────────────────────────────────────
msg()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }
note() { printf '\033[1;36m ..\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Small helpers ───────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

require() {
    local c
    for c in "$@"; do
        have "$c" || die "missing dependency: $c"
    done
}

# run <cmd...> — execute a command, or print it under --dry-run.
run() {
    if (( DRY_RUN )); then
        printf '   [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# confirm "question" — prompt unless -y/--yes was given.
confirm() {
    (( ASSUME_YES )) && return 0
    local reply
    printf '\033[1;33m ?\033[0m %s [y/N] ' "$1" >&2
    read -r reply || return 1
    [[ "$reply" =~ ^[Yy]$ ]]
}

# prune_empty_parents <file-inside-stop> <stop-dir>
# Removes now-empty directories between a file's parent and <stop-dir>.
prune_empty_parents() {
    local dir stop="$2"
    dir="$(dirname "$1")"
    while [[ "$dir" == "$stop"/* ]]; do
        rmdir "$dir" 2>/dev/null || break
        dir="$(dirname "$dir")"
    done
}

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
dotsniri — meta installer and updater for the equisdots niri stack

Usage: dotsniri <command> [-y] [--dry-run]

Commands:
  setup              install the payload and, when asked, the system hook
  install            clone/update the managed repos and deploy them
  deploy             deploy from existing clones (no clone or update)
  update             git pull the own repos and re-deploy
  list               show managed repos and their kind (own / shared)
  doctor             check binaries, clones, deploy and the niri config
  reset              purge the niri deploy and reinstall from origin/main
  uninstall          reverse the deploy (clones and config are kept)
  desktop <mode>     select the default session: niri | hyprland | both
  login <action>     manage the DM session entry: install | remove | status
  system [--apply]   install distro packages (niri, portals, ...) via templates
  version            print the dotsniri version
  help               show this help

Flags:
  -y, --yes          assume yes (non-interactive)
  -n, --dry-run      print actions, change nothing
  -h, --help         show help (use after a command for its usage)

The niri stack is installed under ~/.local/share/equisdots-niri. Shared
equisdots repos are consumed read-only from ~/.local/share/equisdots, so a
parallel `dots` install is never modified.
EOF
}

usage_command() {
    case "${1:-}" in
        desktop) cat <<'EOF'
dotsniri desktop <niri|hyprland|both>
  Sets the default session, mirrors it into settings.json's "compositor" key and
  (un)applies the niri-shell overlay:
    niri       deploy the overlay, set niri as the default
    both       deploy the overlay, keep both sessions (XDG selects at runtime)
    hyprland   remove the overlay, leave a pure Hyprland shell
EOF
            ;;
        doctor) cat <<'EOF'
dotsniri doctor [--self-test]
  Checks binaries, clones, deployed files and the niri config. Each item is
  reported as ok / warn / fail. --self-test syntax-checks the toolkit
  (bash -n) and works even when niri is not installed.
EOF
            ;;
        login) cat <<'EOF'
dotsniri login <install|remove|status>
  Installs the niri Wayland session entry into a system-scanned directory
  (/usr/local/share/wayland-sessions or /usr/share/wayland-sessions) with sudo,
  so display managers list "Niri". Skips gracefully when the distro already
  provides niri.desktop.
EOF
            ;;
        install|deploy|update) cat <<'EOF'
dotsniri <install|deploy|update>
  install   clone/update the own repos, ensure the shared repos, then deploy
  deploy    deploy from the existing clones (no clone or update)
  update    pull the own repos and re-deploy (shared repos stay read-only)
EOF
            ;;
        reset|uninstall) cat <<'EOF'
dotsniri <reset|uninstall> [-y]
  Destructive operations. They prompt for confirmation unless -y is given.
    reset      remove the niri deploy, drop the own clones and reinstall
    uninstall  reverse the deploy; clones and config are kept
EOF
            ;;
        system) cat <<'EOF'
dotsniri system [--apply]
  Resolves the distro (ID, then ID_LIKE) to a system/install-<distro>.sh
  template and installs the niri stack packages (compositor, portals, shell
  tools). Without --apply it only prints the plan. Arch and Fedora templates
  ship as examples; the core stays distro-agnostic.
EOF
            ;;
        *) usage ;;
    esac
}

cmd_version() {
    local v=unknown
    [[ -f "$VERSION_FILE" ]] && v="$(tr -d '[:space:]' < "$VERSION_FILE")"
    printf '%s %s\n' "$APP" "$v"
}
