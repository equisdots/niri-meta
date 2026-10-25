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

# ── Integration steps (system phase) ───────────────────────────────────────

pam_quickshell_configured() {
    [[ -f /etc/pam.d/quickshell ]] && grep -q 'system-auth' /etc/pam.d/quickshell 2>/dev/null
}

# /etc/pam.d/quickshell is required by the Quickshell lock screen. Without it
# PAM falls back to pam_deny and no password is accepted. The file ships in the
# shared hyprland clone (read-only); copy it with sudo, backing up any existing
# service file first.
system_install_pam() {
    local src
    src="$(repo_path hyprland)/config/pam.d/quickshell"
    if pam_quickshell_configured; then
        ok "PAM service 'quickshell' already configured"
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        warn "PAM: $src not found (run 'dotsniri install' to clone shared hyprland); skipping"
        return 0
    fi
    if (( DRY_RUN )); then
        msg "[dry-run] would install $src -> /etc/pam.d/quickshell (sudo)"
        return 0
    fi
    if [[ -f /etc/pam.d/quickshell ]]; then
        as_root cp -f /etc/pam.d/quickshell /etc/pam.d/quickshell.backup
        note "PAM: existing service backed up to /etc/pam.d/quickshell.backup"
    fi
    as_root install -Dm644 "$src" /etc/pam.d/quickshell
    ok "PAM service 'quickshell' installed"
}

# Optional SDDM theme. login/install.sh may switch display-manager.service to
# SDDM, so it only runs with the explicit --login opt-in; it is never part of a
# default system/install/setup run.
system_install_login_theme() {
    local repo
    repo="$(repo_path login)"
    if [[ ! -f "$repo/install.sh" ]]; then
        warn "login: $repo/install.sh not found (run 'dotsniri install'); skipping the SDDM theme"
        return 0
    fi
    if (( DRY_RUN )); then
        msg "[dry-run] would run $repo/install.sh (SDDM theme; may select SDDM as display manager)"
        return 0
    fi
    warn "login: running login/install.sh — it may select SDDM as display-manager.service"
    if bash "$repo/install.sh"; then
        ok "SDDM theme installed"
    else
        warn "login: SDDM theme installation failed"
    fi
}

# SDDM/login and the shell share the Hack Nerd Font. The user-level copy is
# installed by the app-config step; this installs it under /usr/share/fonts so
# the greeter's shutdown/reboot glyphs do not render as boxes.
system_install_font() {
    local src="$HOME/.local/share/fonts/HackNerdFont-Regular.ttf"
    local dst="/usr/share/fonts/HackNerdFont-Regular.ttf"
    local url="https://raw.githubusercontent.com/xscriptor-colors/terminal/main/assets/fonts/HackNerdFont/HackNerdFont-Regular.ttf"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst" 2>/dev/null; then
        ok "Hack Nerd Font already installed system-wide"
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        run mkdir -p "$(dirname "$src")"
        if have curl; then
            run curl -fsSL "$url" -o "$src" || true
        elif have wget; then
            run wget -q -O "$src" "$url" || true
        fi
    fi
    if [[ ! -f "$src" ]]; then
        warn "Hack Nerd Font not available; SDDM may show boxes for icons"
        return 0
    fi
    if (( DRY_RUN )); then
        msg "[dry-run] would install $src -> $dst (sudo) and run fc-cache"
        return 0
    fi
    if as_root install -Dm644 "$src" "$dst"; then
        as_root fc-cache -f >/dev/null 2>&1 || true
        ok "Hack Nerd Font installed system-wide (SDDM/login)"
    else
        warn "could not install Hack Nerd Font system-wide"
    fi
}

cmd_system() {
    local apply=0 pam=auto xwww=auto font=auto login=0 args=() arg
    for arg in "$@"; do
        case "$arg" in
            --apply)    apply=1 ;;
            --pam)      pam=yes ;;
            --no-pam)   pam=no ;;
            --xwww)     xwww=yes ;;
            --no-xwww)  xwww=no ;;
            --font)     font=yes ;;
            --no-font)  font=no ;;
            --login)    login=1 ;;
            --no-login) login=0 ;;
            *)          args+=("$arg") ;;
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
        if [[ "$apply" -eq 0 ]]; then
            return 0
        fi
        note "continuing with the integration steps only (xwww, PAM, login)"
    fi

    if [[ -n "$tpl" ]]; then
        note "template: $tpl"
    fi

    if [[ "$apply" -eq 1 ]] || (( ASSUME_YES )); then
        if [[ -n "$tpl" ]]; then
            if (( DRY_RUN )); then
                msg "[dry-run] bash $tpl ${args[*]-}"
            else
                confirm "Run $tpl? It may use sudo." || { warn "aborted"; return 0; }
                local targs=("${args[@]}")
                (( ASSUME_YES )) && targs+=(--yes)
                bash "$tpl" "${targs[@]}"
            fi
        fi

        # The shared hyprland clone supplies the PAM file; clone it if the
        # system step installed git but the payload has not run yet.
        if have git && [[ ! -d "$(repo_path hyprland)" ]]; then
            ensure_repo hyprland || warn "hyprland: clone failed; PAM setup may be skipped"
        fi

        if [[ "$xwww" != no ]]; then
            cmd_xwww || warn "xwww: installation failed; the wallpaper daemon will be missing"
        else
            note "xwww: skipped (--no-xwww)"
        fi

        if [[ "$pam" == no ]]; then
            note "PAM: skipped (--no-pam)"
        elif pam_quickshell_configured; then
            system_install_pam
        elif [[ "$pam" == yes ]] || (( DRY_RUN )) \
             || confirm "Install /etc/pam.d/quickshell for the lock screen? [y/N]"; then
            system_install_pam
        else
            note "PAM: skipped; the lock screen will not accept passwords"
        fi

        if [[ "$font" == no ]]; then
            note "system font: skipped (--no-font)"
        else
            system_install_font || warn "font: system-wide install failed (non-fatal)"
        fi

        if [[ "$login" -eq 1 ]]; then
            system_install_login_theme
        else
            note "SDDM theme: opt in with 'dotsniri system --apply --login' (never changed silently)"
        fi
    else
        note "plan only: re-run with --apply to execute the template"
        note "integration plan: xwww (pinned ${XWWW_PINNED_VERSION:-v0.13.1}), PAM (prompt), Hack Nerd Font (SDDM), SDDM theme (only with --login)"
        if [[ -n "$tpl" ]]; then
            if (( DRY_RUN )); then
                note "[dry-run] would run: bash $tpl"
            else
                bash "$tpl" --dry-run || true
            fi
        fi
    fi
}

# ── Bootstrap preflight ─────────────────────────────────────────────────────
# Mirrors `dots setup`: before install/deploy, make sure git, rsync and jq are
# present. If a distro template exists, run the system phase first (it installs
# them) and retry once. The remote one-liner still needs git (or curl/wget+tar)
# to get this meta onto disk first; see the bootstrap block in bin/dotsniri.
preflight_runtime() {
    local missing=() still=() c tpl
    for c in git rsync jq; do
        have "$c" || missing+=("$c")
    done
    (( ${#missing[@]} == 0 )) && return 0

    warn "missing required runtime tool(s): ${missing[*]}"
    if [[ "${PREFLIGHT_SYSTEM_RUNNING:-0}" -eq 1 ]]; then
        die "cannot bootstrap the missing tools automatically; install ${missing[*]} and re-run"
    fi

    tpl="$(system_template_for_distro || true)"
    if [[ -z "$tpl" ]]; then
        if (( DRY_RUN )); then
            note "[dry-run] would need to install ${missing[*]} first (no template for this distro)"
            return 0
        fi
        die "install ${missing[*]} with your package manager and re-run"
    fi

    if (( DRY_RUN )); then
        note "[dry-run] would run the system phase first to install: ${missing[*]}"
        return 0
    fi

    msg "running the system phase first to install: ${missing[*]}"
    PREFLIGHT_SYSTEM_RUNNING=1
    cmd_system --apply --no-login || warn "system phase reported errors; retrying the tool check"
    unset PREFLIGHT_SYSTEM_RUNNING

    for c in git rsync jq; do
        have "$c" || still+=("$c")
    done
    if (( ${#still[@]} )); then
        die "still missing after the system phase: ${still[*]} (install manually and re-run)"
    fi
    ok "runtime tools ready"
}
