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
    rofi-emoji
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
    librsvg
    ffmpeg

    grim
    slurp
    satty
    zbar
    gpu-screen-recorder

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
    qt6-multimedia
    sddm

    noto-fonts
    noto-fonts-emoji
    noto-fonts-cjk
    adw-gtk-theme
    papirus-icon-theme

    power-profiles-daemon
    starship
    zsh
    socat
    inotify-tools
    lm_sensors
    iw
    xdg-utils
    xdg-user-dirs
    pciutils
    rust
    base-devel

    pipewire
    pipewire-alsa
    pipewire-pulse
    wireplumber
    networkmanager
    bluez
    bluez-utils
    polkit
)

# AUR-only packages required by the full niri stack. They stay out of the core
# transaction (one unknown pacman target aborts it) and are installed one by
# one through paru/yay (bootstrapped below). A failure is fatal: the installer
# must not silently skip a dependency. `envycontrol` is installed by the NVIDIA
# step only, so AMD/Intel systems do not pull it.
OPTIONAL_PKGS=(
    mpvpaper
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
    printf 'AUR helper: use paru/yay, or build yay from the AUR when neither is present\n'
    printf 'optional (AUR helper): %s\n' "${OPTIONAL_PKGS[*]}"
    exit 0
fi

if (( ! ASSUME_YES )); then
    printf 'Install %d packages with pacman? [y/N] ' "${#PKGS[@]}"
    read -r reply || reply=""
    [[ "$reply" =~ ^[Yy]$ ]] || { printf 'aborted\n'; exit 1; }
fi

# AUR helper parity with equisdots/hyprland: prefer paru, then yay, and build
# yay from the AUR when neither exists. yay must run as the desktop user, so a
# root invocation only warns and falls back to the official repositories.
AUR_HELPER=""
ensure_aur_helper() {
    if [[ "$(id -u)" == "0" ]]; then
        printf 'AUR helpers cannot run as root; AUR-only packages will be skipped\n' >&2
        return 1
    fi
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER=paru
        printf 'AUR helper: paru\n'
        return 0
    fi
    if command -v yay >/dev/null 2>&1; then
        AUR_HELPER=yay
        printf 'AUR helper: yay\n'
        return 0
    fi

    if ! command -v git >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
        printf 'Installing yay build tools (git, base-devel)...\n'
        sudo pacman -S --needed --noconfirm git base-devel || return 1
    fi

    local tmp
    tmp="$(mktemp -d)" || return 1
    printf 'No AUR helper found; building yay from the AUR...\n'
    if ! git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi
    if ( cd "$tmp/yay" && makepkg -si --noconfirm ); then
        AUR_HELPER=yay
    fi
    rm -rf "$tmp"
    [[ -n "$AUR_HELPER" ]]
}

pacman_args=(--needed)
(( ASSUME_YES )) && pacman_args+=(--noconfirm)

# Preflight: resolve the full core set before changing anything. A missing
# target or unsatisfied dependency aborts here, with the user's current install
# untouched. This is the check that would have caught mpvpaper in core.
printf 'Preflight: resolving %d core packages...\n' "${#PKGS[@]}"
if ! sudo pacman -Sp "${pacman_args[@]}" "${PKGS[@]}" >/dev/null; then
    printf 'error: package resolution failed; nothing was installed\n' >&2
    exit 1
fi

# Install the core set as one pacman transaction. Pacman commits atomically:
# if this fails, no core package is installed and the caller aborts before the
# dots payload is deployed.
if ! sudo pacman -S "${pacman_args[@]}" "${PKGS[@]}"; then
    printf 'error: core package transaction failed; nothing was installed\n' >&2
    exit 1
fi

if (( ${#OPTIONAL_PKGS[@]} > 0 )); then
    if ! ensure_aur_helper; then
        printf 'error: no AUR helper for required AUR packages: %s\n' "${OPTIONAL_PKGS[*]}" >&2
        exit 1
    fi
    # One helper transaction for all AUR packages, with one retry. AUR builds
    # are not atomic; the caller still keeps the existing deployment untouched
    # and a rerun installs only the missing pieces.
    if ! "$AUR_HELPER" -S --needed --noconfirm "${OPTIONAL_PKGS[@]}"; then
        printf 'AUR transaction failed; retrying once...\n' >&2
        if ! "$AUR_HELPER" -S --needed --noconfirm "${OPTIONAL_PKGS[@]}"; then
            printf 'error: AUR package transaction failed: %s\n' "${OPTIONAL_PKGS[*]}" >&2
            exit 1
        fi
    fi
fi
