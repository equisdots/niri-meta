#!/usr/bin/env bash
# equisdots-niri · niri-meta
# doctor.sh — dependency, clone and config checks, plus a syntax self-test.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'doctor.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

DOCTOR_FAIL=0

chk_bin() {
    local c="$1"
    if have "$c"; then ok "$c"; else warn "$c missing"; DOCTOR_FAIL=1; fi
}

# Pass when at least one of the candidate commands exists.
chk_any() {
    local label="$1" c
    shift
    for c in "$@"; do
        if have "$c"; then ok "$label ($c)"; return 0; fi
    done
    warn "$label missing (tried: $*)"
    DOCTOR_FAIL=1
}

chk_optional() {
    local c="$1"
    if have "$c"; then ok "$c (optional)"; else note "$c optional, missing"; fi
}

check_niri_version() {
    if ! have niri; then
        warn "niri not installed: cannot report its version"
        DOCTOR_FAIL=1
        return 0
    fi
    local v
    v="$(niri --version 2>/dev/null | head -1 || true)"
    if [[ -n "$v" ]]; then ok "niri $v"; else warn "niri present but --version failed"; DOCTOR_FAIL=1; fi
}

check_niri_config() {
    local cfg="$NIRI_CFG/config.kdl"
    if [[ ! -f "$cfg" ]]; then
        warn "$cfg missing (run: dotsniri install)"
        DOCTOR_FAIL=1
        return 0
    fi
    if ! have niri; then
        warn "niri not installed: cannot validate $cfg"
        DOCTOR_FAIL=1
        return 0
    fi
    if niri validate -c "$cfg" >/dev/null 2>&1; then
        ok "niri validate: $cfg"
    else
        warn "niri validate failed: $cfg"
        DOCTOR_FAIL=1
    fi
}

check_clones() {
    local name path
    while IFS= read -r name; do
        path="$(repo_path "$name")"
        if [[ -d "$path/.git" ]]; then
            ok "$name clone"
        else
            warn "$name clone missing (run: dotsniri install)"
            DOCTOR_FAIL=1
        fi
    done < <(repos_all)
}

check_overlay() {
    local want=0 name path manifest applied=0 missing=0
    desktop_includes_niri && want=1
    for name in "${OVERLAY_REPOS[@]}"; do
        path="$(repo_path "$name")"
        [[ -d "$path" ]] || continue
        manifest="$(overlay_manifest "$name")"
        if [[ -f "$manifest" ]]; then applied=$((applied + 1)); else missing=$((missing + 1)); fi
    done

    if [[ "$want" -eq 1 && "$missing" -eq 0 ]]; then
        ok "shell overlays applied (desktop=$(desktop_current))"
    elif [[ "$want" -eq 0 && "$applied" -eq 0 ]]; then
        ok "shell overlays not applied (desktop=$(desktop_current))"
    else
        warn "overlay state does not match desktop '$(desktop_current)' (run: dotsniri deploy)"
        DOCTOR_FAIL=1
    fi
}

check_shell_base() {
    if [[ -f "$QS/Shell.qml" ]]; then
        ok "Quickshell shell present ($QS)"
    else
        warn "shell missing at $QS (run: dotsniri install)"
        DOCTOR_FAIL=1
    fi
    # When niri is the selected session the neutral backend must be deployed,
    # otherwise the shell falls back to the Hyprland backend and breaks.
    if desktop_includes_niri; then
        if [[ -f "$QS/core/compositors/Niri.qml" ]]; then
            ok "niri shell backend present (core/compositors/Niri.qml)"
        else
            warn "niri shell backend missing; run 'dotsniri install' (overlays not applied)"
            DOCTOR_FAIL=1
        fi
    fi
}

check_login_entry() {
    local d found=0
    for d in /usr/share/wayland-sessions /usr/local/share/wayland-sessions \
             "${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions"; do
        if [[ -f "$d/niri.desktop" ]]; then
            ok "niri session entry: $d/niri.desktop"
            found=1
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        warn "no niri session entry (run: dotsniri login install)"
        DOCTOR_FAIL=1
    fi
}

check_notification_daemon() {
    local p found=0
    for p in mako dunst; do
        if pgrep -x "$p" >/dev/null 2>&1; then
            warn "$p is running: it serves notifications instead of the shell (palette not applied). Stop it."
            DOCTOR_FAIL=1
            found=1
        fi
    done
    [[ "$found" -eq 0 ]] && ok "no competing notification daemon (the shell owns notifications)"
}

check_path() {
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ok "$HOME/.local/bin in PATH" ;;
        *) warn "$HOME/.local/bin not in PATH (dotsniri and engines unreachable)"; DOCTOR_FAIL=1 ;;
    esac
}

check_settings_compositor() {
    [[ -f "$HYPR/settings.json" ]] || return 0
    have jq || return 0
    local have_c want
    have_c="$(jq -r '.compositor // empty' "$HYPR/settings.json" 2>/dev/null || true)"
    want="$(desktop_current)"
    if [[ "$have_c" == "$want" ]]; then
        ok "settings.json compositor = $have_c"
    else
        note "settings.json compositor='${have_c:-unset}' vs desktop='$want' (run: dotsniri desktop $want)"
    fi
}

cmd_doctor_selftest() {
    local fails=0 f
    msg "self-test: syntax-checking the toolkit (no niri required)"
    while IFS= read -r f; do
        if bash -n "$f" 2>/dev/null; then
            ok "syntax: ${f#"$ROOT_DIR"/}"
        else
            warn "syntax error: ${f#"$ROOT_DIR"/}"
            fails=1
        fi
    done < <(find "$ROOT_DIR" -name '*.sh' -not -path '*/.git/*' | sort)

    if bash -n "$ROOT_DIR/bin/dotsniri" 2>/dev/null; then
        ok "syntax: bin/dotsniri"
    else
        warn "syntax error: bin/dotsniri"
        fails=1
    fi
    if [[ -x "$ROOT_DIR/bin/dotsniri" ]]; then
        ok "bin/dotsniri is executable"
    else
        warn "bin/dotsniri is not executable"
        fails=1
    fi
    if (( fails == 0 )); then ok "self-test passed"; else warn "self-test failed"; fi
    return "$fails"
}

cmd_doctor() {
    if [[ "${1:-}" == "--self-test" || "${1:-}" == "self-test" ]]; then
        shift
        cmd_doctor_selftest "$@"
        return $?
    fi

    DOCTOR_FAIL=0

    msg "binaries (required)"
    chk_bin niri
    chk_bin xwayland-satellite
    chk_any quickshell quickshell qs
    chk_bin xwww-daemon
    chk_bin cava
    chk_bin playerctl
    chk_bin wl-paste
    chk_bin cliphist
    chk_bin brightnessctl
    chk_bin pamixer
    chk_bin kitty
    chk_bin rofi
    chk_bin jq

    if ! have niri; then
        note "niri is not installed; run 'dotsniri system --apply' to install it"
    fi

    msg "binaries (optional)"
    local c
    for c in grim slurp satty hyprpicker cargo mpvpaper; do
        chk_optional "$c"
    done

    msg "clones"
    check_clones

    msg "niri config"
    check_niri_version
    check_niri_config

    msg "deploy"
    check_shell_base
    check_overlay
    check_login_entry
    check_notification_daemon
    check_path
    check_settings_compositor

    if (( DOCTOR_FAIL == 0 )); then
        ok "doctor: all critical checks passed"
    else
        warn "doctor: some checks failed (see the warn lines above)"
    fi
    return "$DOCTOR_FAIL"
}
