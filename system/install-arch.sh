#!/usr/bin/env bash
# equisdots-niri · niri-meta
# system/install-arch.sh — Arch Linux package template for the niri stack.
#
# THIS IS A TEMPLATE. `dotsniri system` detects the distro and offers the
# matching file; it is not run automatically. Review the package list first.
#
# Usage: install-arch.sh [--dry-run] [-y|--yes] [--help]
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0

# Niri stack runtime: compositor, XWayland bridge, shell, portals, session
# services and the CLI/GUI tools the shared scripts, bar and panels rely on.
# Every official-repo package is installed in one transaction.
PKGS=(
    niri
    xwayland-satellite
    quickshell
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    swayidle

    cava
    playerctl
    wl-clipboard
    cliphist
    fd
    ripgrep
    brightnessctl
    pamixer
    ddcutil
    kitty
    rofi
    jq
    git
    rsync
    curl
    wget
    tar
    unzip
    python
    libnotify
    imagemagick
    ffmpeg

    grim
    slurp
    satty
    zbar

    nautilus
    gvfs
    gvfs-mtp
    pavucontrol
    network-manager-applet
    blueman
    gnome-keyring
    libsecret
    polkit-kde-agent
    qt5ct
    qt6ct
    qt5-wayland
    qt6-wayland

    noto-fonts
    noto-fonts-emoji
    noto-fonts-cjk
    adw-gtk-theme
    papirus-icon-theme

    power-profiles-daemon
    starship
    zsh
    socat

    pipewire
    pipewire-pulse
    wireplumber
    networkmanager
    bluez
    bluez-utils
    polkit
)

# AUR-only / optional packages. Installed through paru/yay when present and
# never fatal: a missing helper or package only warns.
OPTIONAL_PKGS=(
    envycontrol
    gpu-screen-recorder
    bibata-cursor-theme
)

usage() {
    cat <<'EOF'
install-arch.sh — example Arch Linux packages for the equisdots niri stack

Usage: install-arch.sh [--dry-run] [-y|--yes] [--help]
  --dry-run   print the pacman/AUR commands and change nothing
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
    printf 'sudo pacman -S --needed %s\n' "${PKGS[*]}"
    printf 'optional (AUR helper): %s\n' "${OPTIONAL_PKGS[*]}"
    exit 0
fi

if (( ! ASSUME_YES )); then
    printf 'Install %d packages with pacman? [y/N] ' "${#PKGS[@]}"
    read -r reply || reply=""
    [[ "$reply" =~ ^[Yy]$ ]] || { printf 'aborted\n'; exit 1; }
fi

pacman_args=(--needed)
(( ASSUME_YES )) && pacman_args+=(--noconfirm)
sudo pacman -S "${pacman_args[@]}" "${PKGS[@]}"

# Optional packages are never fatal: try the official repos first, then an AUR
# helper (paru/yay) when one is available.
if ! sudo pacman -S "${pacman_args[@]}" "${OPTIONAL_PKGS[@]}" 2>/dev/null; then
    aur_helper=""
    if command -v paru >/dev/null 2>&1; then
        aur_helper=paru
    elif command -v yay >/dev/null 2>&1; then
        aur_helper=yay
    fi
    if [[ -n "$aur_helper" ]]; then
        "$aur_helper" -S --needed --noconfirm "${OPTIONAL_PKGS[@]}" \
            || printf 'optional packages skipped: %s\n' "${OPTIONAL_PKGS[*]}" >&2
    else
        printf 'optional packages skipped (not in the repos; no paru/yay): %s\n' "${OPTIONAL_PKGS[*]}" >&2
    fi
fi
