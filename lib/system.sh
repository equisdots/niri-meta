#!/usr/bin/env bash
# equisdots-niri · niri-meta
# system.sh — deferred, distro-agnostic system integration hook.
#
# The core never hardcodes distro packages. System-level work (packages, fonts,
# login theme, PAM, portals, session registration) lives in pluggable
# templates under system/install-<distro>.sh. `dotsniri system` detects the
# distro and runs the matching template on request; without a template it
# prints what is available. No equislinux dependency is assumed.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'system.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

distro_id() {
    local id=""
    if [[ -r /etc/os-release ]]; then
        id="$( set +u; . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
    fi
    [[ -n "$id" ]] || id="unknown"
    printf '%s' "$id"
}

system_templates() {
    find "$ROOT_DIR/system" -maxdepth 1 -name 'install-*.sh' 2>/dev/null | sort
}

cmd_system() {
    local apply=0 args=() arg
    for arg in "$@"; do
        case "$arg" in
            --apply) apply=1 ;;
            *)       args+=("$arg") ;;
        esac
    done

    local id tpl
    id="$(distro_id)"
    msg "system integration: deferred hook (distro: $id)"
    note "the core stays distro-agnostic; packages live in system/ templates"

    tpl="$(find "$ROOT_DIR/system" -maxdepth 1 -name "install-$id.sh" 2>/dev/null | head -1)"
    if [[ -z "$tpl" ]]; then
        note "available templates:"
        local f
        while IFS= read -r f; do
            printf '   - %s\n' "$(basename "$f")"
        done < <(system_templates)
        warn "no system/install-$id.sh template for this distro"
        note "copy or adapt one as system/install-$id.sh and re-run 'dotsniri system --apply'"
        return 0
    fi

    note "template: $tpl"
    if [[ "$apply" -eq 1 ]] || (( ASSUME_YES )); then
        confirm "Run $tpl? It may use sudo." || { warn "aborted"; return 0; }
        if (( DRY_RUN )); then
            msg "[dry-run] bash $tpl ${args[*]-}"
        else
            bash "$tpl" "${args[@]}"
        fi
    else
        note "plan only: re-run with --apply to execute the template"
        if (( DRY_RUN )); then
            note "[dry-run] would run: bash $tpl"
        else
            bash "$tpl" --dry-run || true
        fi
    fi
}
