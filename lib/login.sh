#!/usr/bin/env bash
# equisdots-niri · niri-meta
# login.sh — manage the display-manager session entry via the niri-login repo.
#
# Display managers scan system wayland-sessions directories, not the user-local
# one, so the entry is installed system-wide (with sudo) by niri-login. This
# module is the single place that installs/removes it, used by:
#   - `dotsniri login install|remove|status`
#   - `dotsniri install` / `setup` and `desktop` (best effort, never fatal)

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'login.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

login_installer() {
    printf '%s' "$(repo_path niri-login)/install.sh"
}

login_available() {
    [[ -x "$(login_installer)" ]]
}

# Install the session entry, preferring the system location. Falls back to a
# user-local entry (with a warning) if the privileged install fails. Never
# fatal: the rest of the install must still succeed.
ensure_login_entry() {
    local repo args=()
    repo="$(repo_path niri-login)"
    if [[ ! -x "$repo/install.sh" ]]; then
        warn "niri-login not cloned; run 'dotsniri install' then 'dotsniri login install'"
        return 0
    fi
    (( DRY_RUN )) && args+=("-n")
    if bash "$repo/install.sh" "${args[@]}"; then
        return 0
    fi
    warn "system session install failed; trying a user-local entry (display managers may not list it)"
    bash "$repo/install.sh" --user "${args[@]}" \
        || warn "could not install the niri session entry"
}

remove_login_entry() {
    local repo
    repo="$(repo_path niri-login)"
    [[ -x "$repo/install.sh" ]] || return 0
    bash "$repo/install.sh" --remove || true
}

cmd_login() {
    local sub="${1:-install}"; shift || true
    local repo args=()
    repo="$(repo_path niri-login)"
    if [[ ! -x "$repo/install.sh" ]]; then
        die "niri-login not cloned; run 'dotsniri install' first"
    fi
    (( DRY_RUN )) && args+=("-n")
    (( ASSUME_YES )) && args+=("-y")
    case "$sub" in
        install)          bash "$repo/install.sh" "${args[@]}" "$@" ;;
        remove|uninstall) bash "$repo/install.sh" --remove "${args[@]}" "$@" ;;
        status)           bash "$repo/install.sh" --status "$@" ;;
        *) die "login: unknown action '$sub' (use install | remove | status)" ;;
    esac
}
