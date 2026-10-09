#!/usr/bin/env bash
# equisdots-niri · niri-meta
# system/install-fedora.sh — Fedora package template for the niri stack.
#
# THIS IS A TEMPLATE. `dotsniri system` detects the distro and offers the
# matching file; it is not run automatically. Review the package list first,
# because some niri components may come from a COPR on older Fedora releases.
#
# Usage: install-fedora.sh [--dry-run] [-y|--yes] [--help]
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0

# Niri stack runtime: compositor, XWayland bridge, shell, panels, portals and
# the CLI tools the bar/panels rely on. Adjust to taste. `quickshell` and
# `niri` may require a COPR repository depending on the Fedora release.
PKGS=(
    niri
    xwayland-satellite
    quickshell
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    cava
    playerctl
    wl-clipboard
    cliphist
    brightnessctl
    pamixer
    kitty
    rofi
    jq
    git
    rsync
)

usage() {
    cat <<'EOF'
install-fedora.sh — example Fedora packages for the equisdots niri stack

Usage: install-fedora.sh [--dry-run] [-y|--yes] [--help]
  --dry-run   print the dnf command and change nothing
  -y, --yes   do not prompt
  --help      show this help
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -y|--yes)  ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if (( DRY_RUN )); then
    printf 'sudo dnf install %s\n' "${PKGS[*]}"
    exit 0
fi

if (( ! ASSUME_YES )); then
    printf 'Install %d packages with dnf? [y/N] ' "${#PKGS[@]}"
    read -r reply || reply=""
    [[ "$reply" =~ ^[Yy]$ ]] || { printf 'aborted\n'; exit 1; }
fi

sudo dnf install "${PKGS[@]}"
