#!/usr/bin/env bash
# equisdots-niri · niri-meta
# xwww.sh — install/align the xwww wallpaper daemon (niri autostart dependency).
#
# Ported from the read-only shared hyprland installer, but kept standalone so a
# niri-only machine never needs `dots system`. The release is pinned and
# checksum-verified; the source build is only a fallback. Installs the client
# `xwww` and `xwww-daemon` into /usr/local/bin (sudo), never the upstream
# `awww` package.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'xwww.sh must be sourced, not executed\n' >&2
    exit 1
}

# Pinned release; XWWW_VERSION overrides it (same contract as the hyprland
# installer and dots/scripts/install-xwww.sh).
XWWW_PINNED_VERSION="v0.13.1"

xwww_wanted_version() {
    printf '%s' "${XWWW_VERSION:-$XWWW_PINNED_VERSION}"
}

xwww_release_arch() {
    case "$(uname -m)" in
        x86_64)        printf 'x86_64-unknown-linux-gnu' ;;
        aarch64|arm64) printf 'aarch64-unknown-linux-gnu' ;;
        *)             printf '' ;;
    esac
}

# `xwww --version` prints "xwww <version>"; the pin is compared as v<version>.
xwww_installed_version() {
    have xwww || return 0
    xwww --version 2>/dev/null | awk '{print $2}' | head -1 || true
}

xwww_matches_pin() {
    local want have_v
    want="$(xwww_wanted_version)"
    have_v="$(xwww_installed_version)"
    [[ -n "$want" && "v${have_v}" == "$want" ]]
}

xwww_install_release() {
    local arch="$1" want base url tmp expected actual d
    want="$(xwww_wanted_version)"
    base="xwww-${want}-${arch}"
    url="https://github.com/x-ports/xwww/releases/download/${want}/${base}.tar.gz"

    have curl || { warn "xwww: curl missing; cannot download the release"; return 1; }
    have tar  || { warn "xwww: tar missing; cannot extract the release"; return 1; }

    tmp="$(mktemp -d)"
    msg "xwww: downloading $want ($arch)"
    if ! curl -fsSL "$url" -o "$tmp/pkg.tar.gz"; then
        warn "xwww: release download failed"
        rm -rf "$tmp"
        return 1
    fi

    if curl -fsSL "$url.sha256" -o "$tmp/pkg.sha256" 2>/dev/null; then
        expected="$(cut -d' ' -f1 "$tmp/pkg.sha256" | head -1)"
        actual="$(sha256sum "$tmp/pkg.tar.gz" | cut -d' ' -f1)"
        if [[ -z "$expected" || "$expected" != "$actual" ]]; then
            warn "xwww: checksum mismatch; aborting the release install"
            rm -rf "$tmp"
            return 1
        fi
    else
        warn "xwww: checksum file unavailable; continuing without verification"
    fi

    if ! tar -xzf "$tmp/pkg.tar.gz" -C "$tmp" >/dev/null 2>&1; then
        warn "xwww: could not extract the tarball"
        rm -rf "$tmp"
        return 1
    fi
    d="$tmp/$base"
    if [[ ! -f "$d/xwww" || ! -f "$d/xwww-daemon" ]]; then
        warn "xwww: unexpected tarball layout"
        rm -rf "$tmp"
        return 1
    fi

    as_root install -Dm755 "$d/xwww" "$d/xwww-daemon" /usr/local/bin/
    rm -rf "$tmp"
    ok "xwww installed from release: $(command -v xwww-daemon 2>/dev/null || printf /usr/local/bin/xwww-daemon)"
}

xwww_install_source() {
    local src="${XDG_CACHE_HOME:-$HOME/.cache}/xwww-build"
    msg "xwww: building from source"
    have git || { warn "xwww: git missing; cannot clone the source"; return 1; }
    if [[ -d "$src/.git" ]]; then
        git -C "$src" pull --ff-only --quiet \
            || warn "xwww: pull failed; building the existing checkout"
    else
        rm -rf "$src"
        git clone --depth 1 https://github.com/x-ports/xwww "$src" --quiet || {
            warn "xwww: clone failed"
            return 1
        }
    fi
    have cargo || { warn "xwww: cargo missing (install rust) and no prebuilt release"; return 1; }
    if ! (cd "$src" && cargo build --release --features scene); then
        warn "xwww: source build failed"
        return 1
    fi
    as_root install -Dm755 "$src/target/release/xwww" "$src/target/release/xwww-daemon" /usr/local/bin/
    ok "xwww installed from source: $(command -v xwww-daemon 2>/dev/null || printf /usr/local/bin/xwww-daemon)"
}

# cmd_xwww [--force] — idempotent install; honors DRY_RUN.
cmd_xwww() {
    local force=0 arg
    for arg in "$@"; do
        case "$arg" in
            --force) force=1 ;;
            --help|-h)
                printf 'usage: dotsniri xwww [--force] [-n]\n'
                return 0
                ;;
            *) warn "xwww: unknown option: $arg" ;;
        esac
    done

    local want have_v arch
    want="$(xwww_wanted_version)"
    have_v="$(xwww_installed_version)"
    if [[ "$force" -eq 0 ]] && xwww_matches_pin; then
        ok "xwww $want already installed"
        return 0
    fi

    msg "xwww: ${have_v:-missing} -> $want (sudo: /usr/local/bin)"
    if (( DRY_RUN )); then
        note "[dry-run] would download/install xwww $want (or build it from source)"
        return 0
    fi

    if have pacman && pacman -Qq awww >/dev/null 2>&1; then
        warn "package 'awww' is installed; xwww-daemon wins on PATH (remove it with: sudo pacman -Rns awww)"
    fi

    arch="$(xwww_release_arch)"
    if [[ -n "$arch" ]] && xwww_install_release "$arch"; then
        return 0
    fi
    warn "xwww: prebuilt release unavailable/failed; falling back to the source build"
    if ! xwww_install_source; then
        warn "xwww: installation failed; retry later with 'dotsniri xwww'"
        return 1
    fi
}
