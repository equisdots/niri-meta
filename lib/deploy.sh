#!/usr/bin/env bash
# equisdots-niri · niri-meta
# deploy.sh — place the niri stack in the live system (idempotent, reversible).
#
# Deploy map:
#   niri          config/niri/  -> ~/.config/niri/            (compositor config)
#   niri          scripts/      -> ~/.config/niri/scripts/
#   niri-shell    overlay/      -> ~/.config/hypr/scripts/quickshell  (merge)
#   palettes      *.json        -> .../quickshell/dock/palettes (cp -f)
#   theme-sync    wrapper       -> ~/.local/bin/theme-sync   (if missing)
#   davincix      wrapper       -> ~/.local/bin/davincix     (if missing)
#   timex         wrapper + UI  -> ~/.local/bin/timex, .../quickshell/ui/timex
#   login         system-wide   -> handled by the system hook
#   background    no deploy     -> consumed by davincix/xwww
#
# Coexistence rule: a shared file is only replaced by a niri-only variant when
# the niri session is selected. The overlay engine backs up every file it
# overwrites so it can restore the baseline exactly.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'deploy.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

# ── Commands ────────────────────────────────────────────────────────────────

cmd_deploy() {
    require rsync
    local name
    while IFS= read -r name; do
        deploy_repo "$name"
    done < <(repos_all)
    ok "deploy finished"
}

cmd_setup() {
    local do_system=0 arg args=()
    for arg in "$@"; do
        case "$arg" in
            --system|--with-system) do_system=1 ;;
            *) args+=("$arg") ;;
        esac
    done

    cmd_install

    # On a fresh install default to the niri session; never flip an existing
    # choice made by a parallel `dots` + `dotsniri` setup.
    if [[ -f "$DESKTOP_STATE" ]]; then
        note "keeping the current desktop: $(desktop_current)"
    else
        cmd_desktop niri
    fi

    if [[ "$do_system" -eq 1 ]]; then
        cmd_system "${args[@]}" || warn "system phase failed; the payload is installed"
    else
        note "system integration is deferred; run 'dotsniri system' when ready"
    fi
    ok "setup finished — select the niri session at the login screen"
}

# ── Per-repo deploy ─────────────────────────────────────────────────────────

deploy_repo() {
    local name="$1" path
    path="$(repo_path "$name")"
    if [[ ! -d "$path" ]]; then
        warn "$name: not cloned; skipping (run: dotsniri install)"
        return 0
    fi
    case "$name" in
        niri-meta)  deploy_meta "$path" ;;
        niri)       deploy_niri "$path" ;;
        niri-shell) deploy_niri_shell "$path" ;;
        nyx-niri)   deploy_nyx_niri "$path" ;;
        palettes)   deploy_palettes "$path" ;;
        theme-sync) deploy_wrapper theme-sync "$path/theme-sync.sh" ;;
        davincix)   deploy_wrapper davincix "$path/davincix.sh" ;;
        timex)      deploy_timex "$path" ;;
        login)      note "login: SDDM theme is installed system-wide by 'dotsniri system' (or 'dots system')" ;;
        background) note "background: wallpaper scenes are consumed by davincix/xwww (no deploy step)" ;;
    esac
}

# The meta installs its own wrapper so `dotsniri` works from anywhere.
deploy_meta() {
    local path="$1" target
    target="$path/bin/dotsniri"
    [[ -x "$target" ]] || { warn "niri-meta: bin/dotsniri not found in the clone"; return 0; }
    run mkdir -p "$BIN"
    if (( DRY_RUN )); then
        msg "[dry-run] install wrapper $BIN/dotsniri -> $target"
        return 0
    fi
    cat > "$BIN/dotsniri" <<WRAP
#!/usr/bin/env bash
# equisdots-niri · dotsniri wrapper (the meta lives in its own clone)
exec "$target" "\$@"
WRAP
    chmod +x "$BIN/dotsniri"
    ok "dotsniri -> $BIN/dotsniri"
}

# niri compositor config. No --delete: generated/ fragments and user overrides
# (for example user-*.kdl) must survive updates. `reset` handles stale files.
deploy_niri() {
    local path="$1" src
    src="$path/config/niri"
    if [[ -d "$src" ]]; then
        msg "niri: compositor config -> $NIRI_CFG"
        run mkdir -p "$NIRI_CFG"
        run rsync -a --exclude '.git*' "$src/" "$NIRI_CFG/"
    else
        warn "niri: config/niri missing in the clone (layout changed?)"
    fi

    if [[ -d "$path/scripts" ]]; then
        msg "niri: session scripts -> $NIRI_CFG/scripts"
        run mkdir -p "$NIRI_CFG/scripts"
        run rsync -a --exclude '.git*' "$path/scripts/" "$NIRI_CFG/scripts/"
        if (( ! DRY_RUN )); then
            find "$NIRI_CFG/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        fi
    fi
    ok "niri deployed"
}

deploy_niri_shell() {
    deploy_overlay_repo niri-shell "$1"
}

# nyx-niri ships its payload under overlay/ (ui/nyx/...).
deploy_nyx_niri() {
    deploy_overlay_repo nyx-niri "$1"
}

# Generic overlay deploy: merge <path>/overlay (or shell/, or the repo root)
# into $QS when the niri session is selected; otherwise restore the baseline.
deploy_overlay_repo() {
    local name="$1" path="$2" overlay
    overlay="$(overlay_src "$path")"
    if [[ -z "$overlay" ]]; then
        warn "$name: no overlay/ or shell/ directory found; nothing to merge"
        return 0
    fi
    if desktop_includes_niri; then
        overlay_apply "$name" "$overlay"
    else
        note "$name: session is '$(desktop_current)'; overlay not applied"
        overlay_remove "$name"
    fi
}

deploy_palettes() {
    local path="$1"
    msg "palettes -> $PALETTES"
    run mkdir -p "$PALETTES"
    # cp -f (no delete): user palettes and live editor edits survive.
    run cp -f "$path"/*.json "$PALETTES/" 2>/dev/null || true
    if [[ -d "$path/community" ]]; then
        run mkdir -p "$PALETTES/community"
        run cp -f "$path/community"/*.json "$PALETTES/community/" 2>/dev/null || true
    fi
    ok "palettes deployed"
}

# Install a shared engine wrapper only when it is missing, so a parallel `dots`
# install keeps ownership of the exact same command.
deploy_wrapper() {
    local name="$1" engine="$2"
    if [[ -e "$BIN/$name" ]]; then
        note "$name: wrapper already present (left untouched)"
        return 0
    fi
    [[ -f "$engine" ]] || { warn "$name: engine not found ($engine)"; return 0; }
    run mkdir -p "$BIN"
    if (( DRY_RUN )); then
        msg "[dry-run] install wrapper $BIN/$name -> $engine"
        return 0
    fi
    cat > "$BIN/$name" <<WRAP
#!/usr/bin/env bash
# equisdots-niri · $name wrapper (engine lives in the shared equisdots clone)
exec "$engine" "\$@"
WRAP
    chmod +x "$BIN/$name"
    ok "$name -> $BIN/$name"
}

deploy_timex() {
    local path="$1"
    deploy_wrapper timex "$path/core/timex.sh"
    if [[ -d "$path/ui" ]]; then
        msg "timex: UI -> $QS/ui/timex"
        run mkdir -p "$QS/ui/timex"
        run rsync -a --exclude '.git*' "$path/ui/" "$QS/ui/timex/"
    fi
}

# ── Overlay engine ──────────────────────────────────────────────────────────
# A repo may ship its payload under overlay/, shell/ or the repo root. Each
# applied overlay lives in its own namespace ($OVERLAY_ROOT/<name>) so several
# overlays (niri-shell, nyx-niri) coexist: files copied into $QS are recorded in
# that overlay's manifest and every overwritten file is backed up first (state
# kept under $STATE, outside the $QS rsync).

overlay_src() {
    local path="$1"
    if [[ -d "$path/overlay" ]]; then
        printf '%s' "$path/overlay"
    elif [[ -d "$path/shell" ]]; then
        printf '%s' "$path/shell"
    elif [[ -f "$path/Compositor.qml" || -d "$path/core" ]]; then
        printf '%s' "$path"
    else
        printf ''
    fi
}

overlay_dir()      { printf '%s/%s' "$OVERLAY_ROOT" "$1"; }
overlay_manifest() { printf '%s/manifest' "$(overlay_dir "$1")"; }
overlay_backup()   { printf '%s/backup' "$(overlay_dir "$1")"; }

# overlay_apply <name> <src>
overlay_apply() {
    local name="$1" src="$2"
    if [[ ! -d "$src" ]]; then
        warn "overlay '$name': source not found: $src"
        return 0
    fi
    msg "$name: applying overlay -> $QS"

    # Refresh cleanly: restore the previous baseline before re-backing up.
    overlay_remove "$name"

    if (( DRY_RUN )); then
        note "[dry-run] would merge overlay files from $src into $QS"
        return 0
    fi

    local dir manifest backup
    dir="$(overlay_dir "$name")"
    manifest="$(overlay_manifest "$name")"
    backup="$(overlay_backup "$name")"

    mkdir -p "$QS" "$dir" "$backup"
    : > "$manifest"

    local rel dest count=0
    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        dest="$QS/$rel"
        if [[ -e "$dest" ]]; then
            mkdir -p "$backup/$(dirname "$rel")"
            cp -a "$dest" "$backup/$rel"
        fi
        mkdir -p "$(dirname "$dest")"
        cp -a "$src/$rel" "$dest"
        printf '%s\n' "$rel" >> "$manifest"
        count=$((count + 1))
    done < <(cd "$src" && find . \( -type f -o -type l \) \
        ! -path './.git/*' ! -path './docs/*' \
        ! -name '.gitignore' ! -name 'README.md' ! -name 'LICENSE' -print0)

    find "$QS" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    ok "$name overlay applied ($count files)"
}

# overlay_remove <name>
overlay_remove() {
    local name="$1" dir manifest backup
    dir="$(overlay_dir "$name")"
    manifest="$(overlay_manifest "$name")"
    backup="$(overlay_backup "$name")"
    [[ -f "$manifest" ]] || return 0
    if (( DRY_RUN )); then
        note "[dry-run] would remove the applied '$name' overlay"
        return 0
    fi
    local rel dest
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        dest="$QS/$rel"
        if [[ -e "$backup/$rel" ]]; then
            cp -a "$backup/$rel" "$dest"
        else
            rm -f "$dest"
            prune_empty_parents "$dest" "$QS"
        fi
    done < "$manifest"
    rm -rf "$dir"
    ok "$name overlay removed (baseline restored)"
}

# Remove every applied overlay (reset/uninstall).
overlay_remove_all() {
    [[ -d "$OVERLAY_ROOT" ]] || return 0
    local d name
    for d in "$OVERLAY_ROOT"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        overlay_remove "$name"
    done
}

# Repos whose payload is an overlay over the shared shell tree.
OVERLAY_REPOS=(niri-shell nyx-niri)

# Apply or remove every overlay according to the selected session. Used by the
# `desktop` command so switching session keeps all overlays in sync.
apply_all_overlays() {
    local name path
    for name in "${OVERLAY_REPOS[@]}"; do
        path="$(repo_path "$name")"
        [[ -d "$path" ]] || continue
        deploy_overlay_repo "$name" "$path"
    done
}

# ── Reverse operations ──────────────────────────────────────────────────────

# Remove the files the niri repo deploys, using the clone's tracked file list so
# only managed files are touched (generated/ and user files stay).
undeploy_niri() {
    local path; path="$(repo_path niri)"
    if [[ ! -d "$path/.git" ]]; then
        note "niri: clone absent; nothing to undeploy"
        return 0
    fi
    if (( DRY_RUN )); then
        note "[dry-run] would remove the deployed niri config files"
        return 0
    fi
    local f rel
    while IFS= read -r f; do
        case "$f" in
            config/niri/*) rel="${f#config/niri/}"; rm -f "$NIRI_CFG/$rel" ;;
            scripts/*)     rel="${f#scripts/}"; rm -f "$NIRI_CFG/scripts/$rel" ;;
        esac
    done < <(git -C "$path" ls-files 'config/niri' 'scripts' 2>/dev/null)
    ok "niri: deployed config files removed"
}

cmd_reset() {
    confirm "Reset the niri deploy and reinstall from origin/main? User data is preserved." \
        || { warn "aborted"; return 0; }
    overlay_remove_all
    undeploy_niri

    # Drop the own clones except the running meta; fetch_repo hard-resets it.
    local name kind p
    while IFS= read -r name; do
        kind="$(repo_kind "$name")"
        [[ "$kind" == own ]] || continue
        if [[ "$name" == niri-meta ]]; then
            pull_repo "$name"
            continue
        fi
        p="$(repo_path "$name")"
        if [[ -d "$p" ]]; then
            run rm -rf "$p"
            ok "$name: clone dropped"
        fi
    done < <(repos_all)

    cmd_install
    ok "reset finished"
}

cmd_uninstall() {
    confirm "Reverse the niri deploy (overlay, session file, wrappers)? Clones and config are kept." \
        || { warn "aborted"; return 0; }
    overlay_remove_all
    remove_session_file
    remove_marker_wrapper dotsniri
    local w
    for w in theme-sync davincix timex; do
        remove_marker_wrapper "$w"
    done
    ok "uninstall finished (clones under $BASE_NIRI are kept)"
}

# Remove a wrapper only when dotsniri generated it (marker present), never a
# wrapper owned by `dots`.
remove_marker_wrapper() {
    local name="$1" f
    f="$BIN/$name"
    [[ -f "$f" ]] || return 0
    if grep -q "equisdots-niri" "$f" 2>/dev/null; then
        run rm -f "$f"
        ok "$name wrapper removed"
    else
        note "$name: wrapper not owned by dotsniri (left untouched)"
    fi
}
