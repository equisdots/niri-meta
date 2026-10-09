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

# Candidate template ids: the distro ID first, then each token of ID_LIKE, so
# ID=x + ID_LIKE=arch resolves to install-arch.sh.
distro_ids() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$( set +u; . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
        like="$( set +u; . /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}" )"
    fi
    [[ -n "$id" ]] && printf '%s\n' "$id"
    local t
    for t in $like; do printf '%s\n' "$t"; done
}

# Resolve the template path for this distro (ID then ID_LIKE), or empty.
system_template_for_distro() {
    local cand c
    while IFS= read -r cand; do
        [[ -n "$cand" ]] || continue
        c="$ROOT_DIR/system/install-$cand.sh"
        [[ -f "$c" ]] && { printf '%s' "$c"; return 0; }
    done < <(distro_ids)
    return 1
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
    msg "system integration: distro hook (distro: $id)"
    note "the core stays distro-agnostic; packages live in system/ templates"

    tpl="$(system_template_for_distro || true)"
    if [[ -z "$tpl" ]]; then
        note "available templates:"
        local f
        while IFS= read -r f; do
            printf '   - %s\n' "$(basename "$f")"
        done < <(system_templates)
        warn "no matching system/install-<distro>.sh template for this distro"
        note "copy or adapt one as system/install-<distro>.sh and re-run 'dotsniri system --apply'"
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
