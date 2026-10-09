#!/usr/bin/env bash
# equisdots-niri · niri-meta
# desktop.sh — select the default session and toggle the niri-shell overlay.
#
# State:
#   ~/.local/state/equisdots-niri/desktop   authoritative value (niri|hyprland|both)
#   ~/.config/hypr/settings.json            mirrored "compositor" key (jq)
#   ~/.local/share/wayland-sessions/niri.desktop   user SDDM session (if needed)
#
# The shared shell picks its backend from XDG_CURRENT_DESKTOP at runtime:
# niri-session exports XDG_CURRENT_DESKTOP=niri, so the shell loads the Niri
# backend; otherwise it falls back to Hyprland. The overlay is therefore
# deployed for `niri` and `both`, and removed for `hyprland`.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'desktop.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

desktop_current() {
    if [[ -f "$DESKTOP_STATE" ]]; then
        local v
        v="$(tr -d '[:space:]' < "$DESKTOP_STATE" 2>/dev/null || true)"
        case "$v" in
            niri|hyprland|both) printf '%s' "$v"; return 0 ;;
        esac
    fi
    printf '%s' "hyprland"
}

desktop_includes_niri() {
    case "$(desktop_current)" in
        niri|both) return 0 ;;
        *)         return 1 ;;
    esac
}

set_desktop_state() {
    run mkdir -p "$STATE"
    if (( DRY_RUN )); then
        msg "[dry-run] write $DESKTOP_STATE = $1"
        return 0
    fi
    printf '%s\n' "$1" > "$DESKTOP_STATE"
}

# Mirror the choice into settings.json without disturbing user values. The
# state file stays authoritative if jq or settings.json is absent.
set_settings_compositor() {
    local value="$1" tmp
    if [[ ! -f "$HYPR/settings.json" ]]; then
        note "settings.json absent; the state file is authoritative"
        return 0
    fi
    if ! have jq; then
        warn "jq missing; settings.json 'compositor' not updated"
        return 0
    fi
    tmp="$(mktemp)"
    if ! jq --arg c "$value" '.compositor = $c' "$HYPR/settings.json" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        warn "could not update settings.json (left untouched)"
        return 0
    fi
    if (( DRY_RUN )); then
        note "[dry-run] would set settings.json compositor=$value"
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$HYPR/settings.json"
    ok "settings.json compositor = $value"
}

# ── SDDM user session file ──────────────────────────────────────────────────

session_file() { printf '%s' "$WAYLAND_SESSIONS/niri.desktop"; }

system_session_present() {
    local d
    for d in /usr/share/wayland-sessions /usr/local/share/wayland-sessions; do
        [[ -f "$d/niri.desktop" ]] && return 0
    done
    return 1
}

install_session_file() {
    if system_session_present; then
        note "a system niri.desktop is already present; not adding a user session"
        return 0
    fi
    local f
    f="$(session_file)"
    run mkdir -p "$WAYLAND_SESSIONS"
    if (( DRY_RUN )); then
        msg "[dry-run] write $f"
        return 0
    fi
    cat > "$f" <<'EOF'
[Desktop Entry]
Name=Niri
Comment=equisdots niri session
Exec=niri-session
Type=Application
DesktopNames=niri
EOF
    ok "user session -> $f"
}

# Remove the session file only when dotsniri wrote it (comment marker).
remove_session_file() {
    local f
    f="$(session_file)"
    [[ -f "$f" ]] || return 0
    grep -q "equisdots niri session" "$f" 2>/dev/null || return 0
    run rm -f "$f"
    ok "user session removed"
}

# ── Command ─────────────────────────────────────────────────────────────────

cmd_desktop() {
    local choice="${1:-}"
    case "$choice" in
        niri|hyprland|both) ;;
        "")  die "desktop: need one of: niri | hyprland | both" ;;
        *)   die "desktop: unknown value '$choice' (use niri | hyprland | both)" ;;
    esac

    msg "desktop: default -> $choice"
    set_desktop_state "$choice"
    set_settings_compositor "$choice"

    if [[ "$choice" == hyprland ]]; then
        remove_session_file
    else
        install_session_file
    fi

    # Keep every overlay (niri-shell, nyx-niri, ...) in sync with the session.
    apply_all_overlays

    cat <<'EOF'
XDG_CURRENT_DESKTOP selects the shell backend at runtime:
  niri-session exports XDG_CURRENT_DESKTOP=niri, so the shell's Compositor.qml
  loads the Niri backend; any other desktop keeps the Hyprland backend.
EOF
    ok "desktop = $choice"
}
