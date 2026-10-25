#!/usr/bin/env bash
# equisdots-niri · niri-meta
# deploy.sh — place the niri stack in the live system (idempotent, reversible).
#
# Deploy map:
#   niri          config/niri/  -> ~/.config/niri/            (compositor config)
#   niri          scripts/      -> ~/.config/niri/scripts/
#   niri          systemd/      -> ~/.config/systemd/user/    (units, not enabled)
#   niri          portals/      -> ~/.config/xdg-desktop-portal/niri-portals.conf
#   hyprland      scripts/      -> ~/.config/hypr/scripts/    (shared, no delete)
#   niri          config/apps/  -> ~/.config/rofi + cava      (backup on change)
#   niri-shell    overlay/      -> ~/.config/hypr/scripts/quickshell  (merge)
#   plugin-api    contract      -> .../quickshell/plugin-api.json + compat
#   plugin-sdk    QML kit       -> .../quickshell/core/sdk/
#   plugins       registry      -> .../quickshell/plugins-registry.json
#   <plugin>      UI + runtime  -> .../quickshell/ui/plugins/<id>,
#                                  ~/.config/hypr/plugins/<id>
#   palettes      *.json        -> .../quickshell/dock/palettes (cp -f)
#   theme-sync    wrapper       -> ~/.local/bin/theme-sync   (if missing)
#   davincix      wrapper       -> ~/.local/bin/davincix     (if missing)
#   timex         default plugin (see <plugin> above)
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

# Plugins that ship with the stack (same set as `dots`): deployed through the
# registry convention on every install/update. No toggle is written; each
# manifest's defaultEnabled decides the state.
DEFAULT_PLUGINS=(screenshots timex rss-reader clipboard quicknotes file-search sysmon keybinds)

# ── Commands ────────────────────────────────────────────────────────────────

# Refuse to start a deploy when a required payload is missing, incomplete or
# dirty. This is the offline-safety boundary: an update with no network must
# never rsync --delete an incomplete clone over a working installation.
preflight_deploy() {
    local name path missing=() dirty=()
    local required=(hyprland shell plugin-api plugin-sdk plugins plugins-niri
                    niri niri-shell nyx-niri nyx timex)
    for name in "${required[@]}"; do
        path="$(repo_path "$name" 2>/dev/null || true)"
        if [[ -z "$path" || ! -d "$path" ]]; then
            missing+=("$name")
            continue
        fi
        if [[ -d "$path/.git" ]]; then
            git -C "$path" rev-parse --verify HEAD >/dev/null 2>&1                 || missing+=("$name(no HEAD)")
            [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]                 && dirty+=("$name")
        fi
    done
    [[ -f "$(repo_path shell 2>/dev/null)/Shell.qml" ]] || missing+=("shell/Shell.qml")
    [[ -d "$(repo_path shell 2>/dev/null)/core" ]] || missing+=("shell/core")
    [[ -f "$(repo_path niri 2>/dev/null)/config/niri/config.kdl" ]] || missing+=("niri/config/niri/config.kdl")
    [[ -f "$(repo_path niri-shell 2>/dev/null)/core/Compositor.qml" ]] || missing+=("niri-shell/core/Compositor.qml")
    [[ -f "$(repo_path plugins-niri 2>/dev/null)/plugins/screenshots/plugin.json" ]] || missing+=("plugins-niri/screenshots")
    [[ -f "$(repo_path plugin-api 2>/dev/null)/plugin-api.json" ]] || missing+=("plugin-api")
    [[ -d "$(repo_path plugin-sdk 2>/dev/null)/qml" ]] || missing+=("plugin-sdk/qml")
    [[ -f "$(repo_path plugins 2>/dev/null)/registry.json" ]] || missing+=("plugins/registry.json")

    if (( ${#missing[@]} )); then
        die "deploy aborted: missing/incomplete required payload: ${missing[*]}. The current installation was left untouched."
    fi
    if (( ${#dirty[@]} )); then
        die "deploy aborted: local changes in managed clones: ${dirty[*]}. Commit/discard them or use 'dotsniri reset'. The current installation was left untouched."
    fi
}

cmd_deploy() {
    preflight_runtime
    preflight_deploy
    local name

    # Phase 1: shared base payloads. The shell, the plugin contract/SDK, the
    # plugin hub and the shared Hyprland scripts (still called by the niri
    # keybinds/autostart) are deployed first so the plugin subset below lands
    # on a valid host. This keeps dotsniri standalone (no `dots` run required)
    # while remaining idempotent and read-only toward `dots`.
    deploy_repo shell
    deploy_repo plugin-api
    deploy_repo plugin-sdk
    deploy_repo plugins
    deploy_repo hyprland
    deploy_settings

    # Phase 2: plugins. Nyx (a root-level plugin repo) and the default plugin
    # set deploy through the generic convention (UI -> shell tree, runtime ->
    # ~/.config/hypr/plugins/<id>).
    deploy_repo nyx
    deploy_default_plugins

    # Phase 3: the niri payload and the remaining shared repos (overlays are
    # handled last so a base/plugin deploy can never wipe them).
    while IFS= read -r name; do
        case "$name" in
            hyprland|shell|nyx|timex|plugin-api|plugin-sdk|plugins|plugins-niri|niri-shell|nyx-niri) continue ;;
        esac
        deploy_repo "$name"
    done < <(repos_all)

    # Phase 4: overlays last (after the plugin UI tree exists).
    deploy_repo niri-shell
    deploy_repo nyx-niri

    # Phase 5: niri-specific plugin overrides win over any baseline restored
    # by an old overlay manifest (the screenshots plugin used to live in
    # niri-shell; the migration must not bring the Hyprland UI back).
    deploy_niri_plugin_overrides

    write_version_state
    ok "deploy finished"
}

# Keep the About/updater version state aligned with this meta's VERSION.
write_version_state() {
    local v f
    v="$(cat "$ROOT_DIR/VERSION" 2>/dev/null || true)"
    [[ -n "$v" ]] || return 0
    f="${XDG_STATE_HOME:-$HOME/.local/state}/equisdots-niri-version"
    if (( DRY_RUN )); then
        msg "[dry-run] write LOCAL_VERSION=\"$v\" to $f"
        return 0
    fi
    run mkdir -p "$(dirname "$f")"
    printf 'LOCAL_VERSION="%s"\n' "$v" > "$f"
    ok "version state -> $f ($v)"
}

cmd_setup() {
    local install_args=() arg
    for arg in "$@"; do
        case "$arg" in
            --system|--with-system) ;; # install runs the system phase by default
            --no-system|--pam|--no-pam|--xwww|--no-xwww|--font|--no-font|--login|--no-login)
                install_args+=("$arg") ;;
        esac
    done

    # install already runs the full system phase (packages, xwww, PAM, font,
    # SDDM theme when active); do not run it a second time here.
    cmd_install "${install_args[@]}"

    # On a fresh install default to the niri session; never flip an existing
    # choice made by a parallel `dots` + `dotsniri` setup.
    if [[ -f "$DESKTOP_STATE" ]]; then
        note "keeping the current desktop: $(desktop_current)"
    else
        cmd_desktop niri
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
        niri-meta)   deploy_meta "$path" ;;
        niri)        deploy_niri "$path" ;;
        niri-shell)  deploy_niri_shell "$path" ;;
        nyx-niri)    deploy_nyx_niri "$path" ;;
        niri-login)  note "niri-login: session entry is installed by 'dotsniri login' (needs sudo)" ;;
        hyprland)    deploy_hyprland_shared "$path" ;;
        shell)       deploy_shell "$path" ;;
        plugin-api)  deploy_plugin_api "$path" ;;
        plugin-sdk)  deploy_plugin_sdk "$path" ;;
        plugins)     deploy_plugins_registry "$path" ;;
        plugins-niri) note "plugins-niri: deployed through the plugin convention" ;;
        nyx)         deploy_plugin "$path" ;;
        palettes)    deploy_palettes "$path" ;;
        theme-sync)  deploy_wrapper theme-sync "$path/theme-sync.sh" ;;
        davincix)    deploy_wrapper davincix "$path/davincix.sh" ;;
        timex)       note "timex: shipped as a default plugin (deploy_default_plugins)" ;;
        login)       note "login: SDDM theme is installed system-wide by 'dotsniri system' (or 'dots system')" ;;
        background)  note "background: wallpaper scenes are consumed by davincix/xwww (no deploy step)" ;;
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

# Resolve the wallpaper directory from settings.json (the shell reads it
# verbatim), expanding a leading "~". Defaults to the shared data root.
niri_wallpaper_dir() {
    local dir=""
    if have jq && [[ -f "$HYPR/settings.json" ]]; then
        dir="$(jq -r '.wallpaperDir // empty' "$HYPR/settings.json" 2>/dev/null || true)"
    fi
    dir="${dir:-$HYPR/wallpapers}"
    printf '%s' "${dir/#\~/$HOME}"
}

# Seed generated/env.kdl with literal paths (niri cannot expand $HOME, and
# environment {} is a single-occurrence section). The template ships in the
# niri clone; existing generated files are never overwritten.
deploy_generated_env() {
    local src="$1" template="$1/defaults/environment.kdl"
    local out="$NIRI_CFG/generated/env.kdl"
    [[ -f "$out" ]] && return 0
    [[ -f "$template" ]] || {
        warn "niri: env seed template missing ($template); skipping generated/env.kdl"
        return 0
    }
    if (( DRY_RUN )); then
        note "[dry-run] would seed $out with literal PATH/XDG paths"
        return 0
    fi

    local local_bin="$HOME/.local/bin" session_path="$HOME/.local/bin"
    local -a path_parts=()
    local p
    IFS=: read -r -a path_parts <<< "${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
    for p in "${path_parts[@]}"; do
        [[ -n "$p" ]] || continue
        [[ ":$session_path:" == *":$p:"* ]] && continue
        session_path="$session_path:$p"
    done

    local wallpaper_dir
    wallpaper_dir="$(niri_wallpaper_dir)"
    local scripts_dir="$HYPR/scripts"
    local pictures_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    local videos_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}"

    local app_scale="1.0" app_scale_env=""
    if have jq && [[ -f "$HYPR/settings.json" ]]; then
        app_scale="$(jq -r '.appScale // 1.0' "$HYPR/settings.json" 2>/dev/null || printf '1.0')"
    fi
    [[ "$app_scale" =~ ^[0-9]+([.][0-9]+)?$ ]] || app_scale="1.0"
    if awk -v s="$app_scale" 'BEGIN { exit !(s + 0 != 1.0) }'; then
        local gdk_int gdk_dpi electron_factor xcursor_size
        read -r gdk_int gdk_dpi electron_factor xcursor_size < <(
            awk -v s="$app_scale" 'BEGIN {
                gi = int(s + 0.0001); if (gi < 1) gi = 1;
                printf "%d %.4f %s %d\n", gi, s / gi, s, int(24 * s)
            }'
        )
        app_scale_env="$(printf '    GDK_SCALE "%s"\n    GDK_DPI_SCALE "%s"\n    ELECTRON_FORCE_DEVICE_SCALE_FACTOR "%s"\n    XCURSOR_SIZE "%s"' \
            "$gdk_int" "$gdk_dpi" "$electron_factor" "$xcursor_size")"
    fi

    local tmp line
    tmp="$(mktemp "${TMPDIR:-/tmp}/dotsniri-env.XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//@SESSION_PATH@/$session_path}"
        line="${line//@WALLPAPER_DIR@/$wallpaper_dir}"
        line="${line//@SCRIPT_DIR@/$scripts_dir}"
        line="${line//@XDG_PICTURES_DIR@/$pictures_dir}"
        line="${line//@XDG_VIDEOS_DIR@/$videos_dir}"
        line="${line//@APP_SCALE_ENV@/$app_scale_env}"
        printf '%s\n' "$line"
    done < "$template" > "$tmp"

    run mkdir -p "$NIRI_CFG/generated"
    run cp "$tmp" "$out"
    rm -f "$tmp"
    chmod 644 "$out" 2>/dev/null || true
    ok "niri: seeded generated/env.kdl (appScale $app_scale)"
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

    # Seed the single-occurrence generated sections (input/animations/blur)
    # once. The writers own them afterwards; existing files are preserved.
    if [[ -d "$src/defaults" ]]; then
        run mkdir -p "$NIRI_CFG/generated"
        local g gsrc gdst
        for g in input:user-input animations:user-animations blur:blur; do
            gsrc="${g%%:*}"; gdst="${g##*:}"
            if [[ ! -f "$NIRI_CFG/generated/$gdst.kdl" && -f "$src/defaults/$gsrc.kdl" ]]; then
                run cp "$src/defaults/$gsrc.kdl" "$NIRI_CFG/generated/$gdst.kdl"
            fi
        done
    fi

    deploy_generated_env "$src"

    if [[ -d "$path/scripts" ]]; then
        msg "niri: session scripts -> $NIRI_CFG/scripts"
        run mkdir -p "$NIRI_CFG/scripts"
        run rsync -a --exclude '.git*' "$path/scripts/" "$NIRI_CFG/scripts/"
        if (( ! DRY_RUN )); then
            find "$NIRI_CFG/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        fi
    fi

    deploy_niri_apps "$path"
    deploy_niri_scenes "$path"
    deploy_niri_units "$path"
    deploy_niri_portal "$path"
    ok "niri deployed"
}

# Rofi/cava configs are owned by the niri repository (config/apps/), so the
# niri stack does not depend on the equisdots/hyprland repo for them.
deploy_niri_apps() {
    local path="$1" apps="$1/config/apps"
    [[ -d "$apps/rofi" ]] && deploy_rofi "$apps/rofi"
    [[ -d "$apps/cava" ]] && deploy_cava "$apps/cava"
    return 0
}

# Interactive wallpaper scenes from the shared background clone. They are
# copied into the davincix wallpaper directory on every deploy, so a fresh or
# updated niri install never has an empty wallpaper picker. Still-image packs
# are optional downloads (WALLPAPERS_PACK / wallpapers.sh).
deploy_niri_scenes() {
    local path="$1" bg scenes dest count=0 d name
    bg="$(repo_path background 2>/dev/null || true)"
    scenes="$bg/scenes"
    dest="$(niri_wallpaper_dir)"
    [[ -d "$scenes" ]] || { note "background scenes not found; skipping"; return 0; }
    msg "niri: wallpaper scenes -> $dest"
    run mkdir -p "$dest"
    for d in "$scenes"/*/; do
        [[ -f "$d/scene.js" ]] || continue
        name="$(basename "$d")"
        run rsync -a --delete "$d" "$dest/$name/"
        count=$((count + 1))
    done
    ok "wallpaper scenes deployed ($count)"
}

# Optional user units. They are copied, never enabled: the niri autostart
# already starts the shell, xwww, the focus daemon and (when the niri repo
# ships the hook) `niri_idle_mode.sh boot`, so enabling the matching units
# would start every daemon twice. `niri_idle_mode.sh` detects the deployed
# swayidle.service and drives it on demand.
deploy_niri_units() {
    local path="$1" src="$1/systemd" dest="$XDG_CONFIG_HOME/systemd/user" f n=0
    [[ -d "$src" ]] || return 0
    msg "niri: user units -> $dest (not enabled)"
    run mkdir -p "$dest"
    for f in "$src"/*.service; do
        [[ -f "$f" ]] || continue
        run cp -f "$f" "$dest/"
        n=$((n + 1))
    done
    if (( DRY_RUN )); then
        note "[dry-run] would run: systemctl --user daemon-reload"
    elif have systemctl; then
        systemctl --user daemon-reload 2>/dev/null \
            || warn "systemctl --user daemon-reload failed (unit files are in place)"
    fi
    if [[ -f "$NIRI_CFG/modules/autostart.kdl" ]] \
       && grep -q 'spawn-sh-at-startup.*niri_idle_mode\.sh[[:space:]]\+boot' "$NIRI_CFG/modules/autostart.kdl" 2>/dev/null; then
        note "idle: niri autostart owns idle (niri_idle_mode.sh boot); swayidle.service stays disabled"
    else
        note "idle: no autostart idle hook; attach swayidle.service with: systemctl --user add-wants niri.service swayidle.service"
    fi
    ok "niri units deployed ($n files)"
}

# Per-user portal override (no sudo). It lets xdg-desktop-portal pick the
# GNOME/GTK backends for the niri session; a distro package may also provide a
# system-wide copy, but the user-level file wins and works without root.
deploy_niri_portal() {
    local path="$1" src="$1/portals/niri-portals.conf"
    local dest="$XDG_CONFIG_HOME/xdg-desktop-portal/niri-portals.conf"
    [[ -f "$src" ]] || return 0
    msg "niri: portals -> $dest"
    run mkdir -p "$(dirname "$dest")"
    run cp -f "$src" "$dest"
    ok "niri portals deployed"
}

deploy_niri_shell() {
    [[ -f "$1/core/Compositor.qml" ]] || { warn "niri-shell: incomplete clone; skipping"; return 1; }
    deploy_overlay_repo niri-shell "$1"
}

# nyx-niri ships its payload under overlay/ (ui/plugins/nyx/...).
deploy_nyx_niri() {
    [[ -f "$1/overlay/ui/plugins/nyx/front/MascotsOverlay.qml" ]] || {
        warn "nyx-niri: incomplete clone; skipping"; return 1; }
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

# Shared Hyprland payload that is still part of the niri session: the helper
# scripts the niri keybinds/autostart call (never delete user scripts) and the
# rofi themes. Its compositor config is NOT deployed (niri owns the compositor).
deploy_hyprland_shared() {
    local path="$1" src="$path/scripts"
    if [[ -d "$src" ]]; then
        msg "hyprland: shared scripts -> $HYPR/scripts"
        run mkdir -p "$HYPR/scripts"
        run rsync -a --exclude '.git*' "$src/" "$HYPR/scripts/"
        if (( ! DRY_RUN )); then
            find "$HYPR/scripts" -maxdepth 1 -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        fi
        ok "shared scripts deployed"
    else
        warn "hyprland: scripts/ missing in the clone"
    fi

    note "rofi/cava: deployed from the niri repository (config/apps/)"
}

# Rofi themes: copy only when the destination is missing or changed. On the
# first change an existing ~/.config/rofi is backed up under the dotsniri
# state directory before it is merged, so local edits are never lost.
deploy_rofi() {
    local src="$1" dest="$CFG/rofi" backup rel changed=0
    backup="$STATE/backups/rofi-$(date +%Y%m%d_%H%M%S)"

    if [[ -d "$dest" ]]; then
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -f "$dest/$rel" ]] || ! cmp -s "$src/$rel" "$dest/$rel"; then
                changed=1
                break
            fi
        done < <(cd "$src" && find . -type f -print0)
        if [[ "$changed" -eq 0 ]]; then
            note "rofi: themes up to date (left untouched)"
            return 0
        fi
        msg "rofi: ~/.config/rofi differs; backing it up to $backup"
        if (( DRY_RUN )); then
            note "[dry-run] would back up $dest before updating"
        else
            mkdir -p "$backup"
            cp -a "$dest/." "$backup/"
            ok "rofi backup -> $backup"
        fi
    else
        msg "rofi: themes -> $dest"
    fi

    run mkdir -p "$dest"
    run rsync -a --exclude '.git*' "$src/" "$dest/"
    ok "rofi themes deployed"
}

# Cava config from the niri repo (same backup/compare contract as rofi).
deploy_cava() {
    local src="$1" dest="$CFG/cava" backup rel changed=0
    backup="$STATE/backups/cava-$(date +%Y%m%d_%H%M%S)"
    if [[ -d "$dest" ]]; then
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -f "$dest/$rel" ]] || ! cmp -s "$src/$rel" "$dest/$rel"; then
                changed=1
                break
            fi
        done < <(cd "$src" && find . -type f -print0)
        if [[ "$changed" -eq 0 ]]; then
            note "cava: config up to date (left untouched)"
            return 0
        fi
        msg "cava: ~/.config/cava differs; backing it up to $backup"
        if (( DRY_RUN )); then
            note "[dry-run] would back up $dest before updating"
        else
            mkdir -p "$backup"
            cp -a "$dest/." "$backup/"
            ok "cava backup -> $backup"
        fi
    else
        msg "cava: config -> $dest"
    fi
    run mkdir -p "$dest"
    run rsync -a --exclude '.git*' "$src/" "$dest/"
    ok "cava config deployed"
}

# User app configs (kitty, starship, nvim, Hack Nerd Font). Run on `install`,
# not on `deploy`/`update`, and never under --dry-run. DOTSNIRI_NO_APPS=1 skips.
install_niri_app_configs() {
    [[ "${DOTSNIRI_NO_APPS:-0}" == "1" ]] && { note "app configs: skipped (DOTSNIRI_NO_APPS=1)"; return 0; }
    local script; script="$(repo_path niri)/scripts/install-app-configs.sh"
    [[ -f "$script" ]] || { warn "app configs: $script not found; skipping"; return 0; }
    if (( DRY_RUN )); then
        note "[dry-run] would run $script"
        return 0
    fi
    local args=()
    (( ASSUME_YES )) && args+=("-y")
    msg "app configs: kitty, starship, nvim, xtop, scenes, Hack Nerd Font"
    bash "$script" "${args[@]}" || warn "app configs finished with warnings"
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

# Mirror the shared `shell` deploy from `dots` so dotsniri is standalone. The
# plugin-owned subtrees are excluded here and deployed separately (plugin-api,
# plugin-sdk, the registry copy and ui/plugins/<id>), and dock/ (palettes) is
# owned by the palette deploy. The legacy ui/nyx location is purged: nyx is a
# plugin now and lives in ui/plugins/nyx.
deploy_shell() {
    local path="$1" backup
    if [[ ! -f "$path/Shell.qml" || ! -d "$path/core" || ! -d "$path/ui" ]]; then
        warn "shell: clone is incomplete ($path); refusing to touch $QS"
        return 1
    fi
    # The shell deploy is the only --delete step over the live tree. Snapshot
    # it first (keep the last 3), so an interrupted/offline update is
    # recoverable even in the worst case.
    if [[ -d "$QS" && -n "$(find "$QS" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        backup="$STATE/backups/shell-$(date +%Y%m%d_%H%M%S).tar.gz"
        msg "shell: snapshot -> $backup"
        run mkdir -p "$STATE/backups"
        if (( ! DRY_RUN )); then
            tar -czf "$backup" -C "$QS" . 2>/dev/null || warn "shell snapshot failed (continuing)"
        fi
        ls -1dt "$STATE"/backups/shell-*.tar.gz 2>/dev/null | tail -n +4 | while IFS= read -r old; do
            run rm -f "$old"
        done
    fi
    msg "shell: quickshell -> $QS"
    run mkdir -p "$QS"
    run rsync -a --delete --exclude '.git*' --exclude 'docs/' \
        --exclude 'dock/' --exclude 'ui/plugins/' --exclude 'ui/nyx/' \
        --exclude 'core/sdk/' --exclude 'plugin-api.json' \
        --exclude 'core/scripts/plugins_compat.sh' \
        --exclude 'plugins-registry.json' --exclude 'plugin-*.qml' \
        "$path/" "$QS/"
    if (( ! DRY_RUN )); then
        find "$QS" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        rm -rf "$QS/ui/nyx"
    fi
    ok "shell deployed"
}

# ── Plugin standard (mirrors `dots`) ───────────────────────────────────────

deploy_plugin_api() {
    local path="$1"
    [[ -f "$path/plugin-api.json" ]] || { warn "plugin-api: payload missing in the clone"; return 0; }
    msg "plugin-api -> $QS (plugin-api.json + compat evaluator)"
    run mkdir -p "$QS/core/scripts"
    run cp -f "$path/plugin-api.json" "$QS/plugin-api.json"
    run cp -f "$path/scripts/plugins_compat.sh" "$QS/core/scripts/plugins_compat.sh"
    if (( ! DRY_RUN )); then chmod +x "$QS/core/scripts/plugins_compat.sh" 2>/dev/null || true; fi
    ok "plugin-api deployed"
}

deploy_plugin_sdk() {
    local path="$1"
    [[ -d "$path/qml" ]] || { warn "plugin-sdk: payload missing in the clone (qml/)"; return 0; }
    msg "plugin-sdk -> $QS/core/sdk (QML host kit)"
    run mkdir -p "$QS/core/sdk"
    run rsync -a --delete --exclude '.git*' "$path/qml/" "$QS/core/sdk/"
    ok "plugin-sdk deployed"
}

deploy_plugins_registry() {
    local path="$1" reg="$1/registry.json"
    [[ -f "$reg" ]] || { warn "plugins: registry.json missing in the clone"; return 0; }
    msg "plugins: registry -> $QS/plugins-registry.json"
    run cp -f "$reg" "$QS/plugins-registry.json"
    ok "plugins registry deployed"
}

# Deploy one plugin by the standard convention (docs/plugins.md §1/§6):
#   whole plugin   -> $QS/ui/plugins/<id>  (UI face)
#   runtime subset -> $HYPR/plugins/<id>  (manifest, hypr.lua, scripts/)
#   defaults       -> seed the plugin's own settings.json ONCE
#   standalone     -> one root-level launcher per entry
deploy_plugin() {
    local path="$1" id defs
    [[ -f "$path/plugin.json" ]] || { warn "plugin: no plugin.json in $path"; return 0; }
    id="$(jq -r '.id // empty' "$path/plugin.json" 2>/dev/null || true)"
    [[ -n "$id" ]] || { warn "plugin: manifest has no id ($path)"; return 0; }
    msg "plugin $id: UI -> $QS/ui/plugins/$id"
    run mkdir -p "$QS/ui/plugins/$id" "$HYPR/plugins/$id"
    run rsync -a --delete --exclude '.git*' --exclude 'docs/' "$path/" "$QS/ui/plugins/$id/"
    run cp -f "$path/plugin.json" "$HYPR/plugins/$id/"
    [[ -f "$path/hypr.lua" ]] && run cp -f "$path/hypr.lua" "$HYPR/plugins/$id/"
    if [[ -d "$path/scripts" ]]; then
        run mkdir -p "$HYPR/plugins/$id/scripts"
        run rsync -a --delete --exclude '.git*' "$path/scripts/" "$HYPR/plugins/$id/scripts/"
    fi
    defs="$(jq -r '.defaults // empty' "$path/plugin.json" 2>/dev/null || true)"
    if [[ -n "$defs" && -f "$path/$defs" ]]; then
        run cp -f "$path/$defs" "$HYPR/plugins/$id/defaults.json"
        if [[ ! -f "$HYPR/plugins/$id/settings.json" ]]; then
            run cp -f "$path/$defs" "$HYPR/plugins/$id/settings.json"
            ok "plugin $id: settings.json seeded from $defs"
        fi
    fi
    if (( ! DRY_RUN )); then
        find "$HYPR/plugins/$id/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        rm -f "$QS/plugin-$id-"*.qml 2>/dev/null || true
        local entry edir ebase rel
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            edir="$(dirname "$entry")"; [[ "$edir" == "." ]] && edir=""
            ebase="$(basename "$entry" .qml)"
            rel="ui/plugins/$id"; [[ -n "$edir" ]] && rel="$rel/$edir"
            cat > "$QS/plugin-$id-$ebase.qml" <<LAUNCH
// generated by dotsniri — standalone entry for plugin $id ($entry)
import "./$rel"

$ebase { }
LAUNCH
        done < <(jq -r '(.standalone // [])[]' "$path/plugin.json" 2>/dev/null)
    fi
    ok "plugin $id deployed"
}

# Resolve an installed-plugin source: a root-level plugin repo (nyx, timex) or
# a folder in the plugin hub (plugins/plugins/<id>).
plugin_source_dir() {
    local id="$1" hub niri_plugins
    niri_plugins="$(repo_path plugins-niri 2>/dev/null || true)"
    if [[ -n "$niri_plugins" && -f "$niri_plugins/plugins/$id/plugin.json" ]]; then
        printf '%s' "$niri_plugins/plugins/$id"
        return 0
    fi
    case "$id" in
        nyx|timex) repo_path "$id"; return 0 ;;
    esac
    hub="$(repo_path plugins 2>/dev/null || true)"
    [[ -n "$hub" && -f "$hub/plugins/$id/plugin.json" ]] && { printf '%s' "$hub/plugins/$id"; return 0; }
    return 1
}

deploy_default_plugins() {
    local pid src
    for pid in "${DEFAULT_PLUGINS[@]}"; do
        src="$(plugin_source_dir "$pid" || true)"
        if [[ -z "$src" ]]; then
            warn "plugin $pid: source not found (hub clone missing?)"
            continue
        fi
        deploy_plugin "$src"
    done
}

# Re-deploy the niri-owned plugins after the overlays. This is the migration
# path for files that used to live in niri-shell (screenshots): overlay_remove
# restores its baseline backup, and the niri plugin must replace it again.
deploy_niri_plugin_overrides() {
    local root d
    root="$(repo_path plugins-niri 2>/dev/null || true)"
    [[ -n "$root" && -d "$root/plugins" ]] || return 0
    for d in "$root/plugins"/*/; do
        [[ -f "$d/plugin.json" ]] || continue
        deploy_plugin "$d"
    done
    return 0
}

# Canonical defaults: prefer the shared hyprland clone (kept current by
# `dots`/dotsniri), then the vendored copy so a standalone install works.
settings_default_file() {
    local root shared
    root="$(repo_path hyprland 2>/dev/null || true)"
    if [[ -n "$root" ]]; then
        shared="$root/config/hypr/default_settings.json"
        if [[ -f "$shared" ]] && { ! have jq || jq -e . "$shared" >/dev/null 2>&1; }; then
            printf '%s' "$shared"
            return 0
        fi
    fi
    printf '%s' "$ROOT_DIR/share/default_settings.json"
}

# Same contract as `dots`: settings.json is ALWAYS default_settings.json + the
# user's values. Seed when absent, refresh the managed default, then merge:
#  1) migrate the pre-equisdots "dock" schema to the canonical "bar"
#  2) drop legacy keys nothing reads anymore
#  3) (re)apply the shipped defaults as the base (user values win; user arrays
#     such as bar.zones are kept as-is, new sections/bar.enabled/plugins land)
#  4) expand a leading "~" in wallpaperDir (the shell resolves it verbatim)
# User choices are never overwritten.
deploy_settings() {
    local def user="$HYPR/settings.json" tmp
    def="$(settings_default_file)"
    [[ -f "$def" ]] || { warn "settings: no default_settings.json found"; return 0; }

    run mkdir -p "$HYPR"
    if [[ ! -f "$HYPR/default_settings.json" ]] \
       || ! cmp -s "$def" "$HYPR/default_settings.json"; then
        run cp -f "$def" "$HYPR/default_settings.json"
        ok "default_settings.json refreshed from $def"
    fi

    if [[ ! -f "$user" ]]; then
        run cp -f "$def" "$user"
        ok "settings.json seeded from $def"
        # Fall through to the merge below: the shipped default has a literal
        # "~" in wallpaperDir and the shell resolves it verbatim.
    fi

    if ! have jq; then
        warn "settings: jq missing; $user left untouched"
        return 0
    fi
    if (( DRY_RUN )); then
        note "[dry-run] would merge defaults into $user (dock->bar, legacy keys, ~ expansion)"
        return 0
    fi

    tmp="$(mktemp)"
    if jq --slurpfile def "$def" --arg home "$HOME" '
        (if (has("dock") and (has("bar") | not)) then .bar = .dock else . end)
        | del(.dock, .serpbar, .openGuideAtStartup, .topbarHelpIcon, .monitors)
        | $def[0] * .
        | (if ((.wallpaperDir // "") | startswith("~"))
           then .wallpaperDir = ($home + (.wallpaperDir | ltrimstr("~"))) else . end)
    ' "$user" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$user"
        ok "settings.json = defaults + user overrides"
    else
        rm -f "$tmp"
        warn "settings.json could not be merged (invalid JSON?); left untouched"
    fi
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
    if [[ -z "$(find -L "$src" -type f -not -path '*/docs/*' -print -quit 2>/dev/null)" ]]; then
        warn "overlay '$name': source is empty ($src); refusing to remove the current overlay"
        return 1
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
        ! -name '.gitignore' ! -name 'LICENSE' ! -name '*.md' -print0)

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

# Units shipped by the niri repo (fallback when the clone is unavailable).
NIRI_UNITS=(focus-daemon.service quickshell.service swayidle.service xwww.service)

# Remove the user-level integration that is not part of the compositor config:
# the niri systemd units and the portal override.
undeploy_niri_integration() {
    local path unit dest="$XDG_CONFIG_HOME/systemd/user" units=()
    if (( DRY_RUN )); then
        note "[dry-run] would remove the niri user units and portal override"
        return 0
    fi
    path="$(repo_path niri)"
    if [[ -d "$path/.git" ]]; then
        while IFS= read -r unit; do
            [[ -n "$unit" ]] && units+=("$(basename "$unit")")
        done < <(git -C "$path" ls-files 'systemd/*.service' 2>/dev/null)
    fi
    (( ${#units[@]} )) || units=("${NIRI_UNITS[@]}")
    for unit in "${units[@]}"; do
        rm -f "$dest/$unit"
    done
    rm -f "$XDG_CONFIG_HOME/xdg-desktop-portal/niri-portals.conf"
    if have systemctl; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    ok "niri user units and portal override removed"
}

# Remove the files the niri repo deploys, using the clone's tracked file list so
# only managed files are touched (generated/ and user files stay).
undeploy_niri() {
    local path; path="$(repo_path niri)"
    if [[ ! -d "$path/.git" ]]; then
        note "niri: clone absent; cleaning the user integration only"
        undeploy_niri_integration
        return 0
    fi
    if (( DRY_RUN )); then
        note "[dry-run] would remove the deployed niri config files"
        undeploy_niri_integration
        return 0
    fi
    local f rel
    while IFS= read -r f; do
        case "$f" in
            config/niri/*) rel="${f#config/niri/}"; rm -f "$NIRI_CFG/$rel" ;;
            scripts/*)     rel="${f#scripts/}"; rm -f "$NIRI_CFG/scripts/$rel" ;;
        esac
    done < <(git -C "$path" ls-files 'config/niri' 'scripts' 2>/dev/null)
    undeploy_niri_integration
    ok "niri: deployed config files removed"
}

snapshot_reset_state() {
    local backup="$STATE/backups/reset-$(date +%Y%m%d_%H%M%S)"
    run mkdir -p "$backup"
    [[ -d "$QS" ]] && run cp -a "$QS" "$backup/quickshell"
    [[ -d "$NIRI_CFG" ]] && run cp -a "$NIRI_CFG" "$backup/niri"
    [[ -f "$HYPR/settings.json" ]] && run cp -a "$HYPR/settings.json" "$backup/settings.json"
    RESET_SNAPSHOT="$backup"
    ok "reset snapshot -> $backup"
    ls -1dt "$STATE"/backups/reset-* 2>/dev/null | tail -n +4 | while IFS= read -r old; do
        run rm -rf "$old"
    done
}

restore_reset_state() {
    local backup="$1"
    [[ -n "$backup" && -d "$backup" ]] || return 1
    [[ -d "$backup/quickshell" ]] && { run mkdir -p "$QS"; run cp -a "$backup/quickshell/." "$QS/"; }
    [[ -d "$backup/niri" ]] && { run mkdir -p "$NIRI_CFG"; run cp -a "$backup/niri/." "$NIRI_CFG/"; }
    [[ -f "$backup/settings.json" ]] && run cp -a "$backup/settings.json" "$HYPR/settings.json"
    return 0
}

cmd_reset() {
    local install_args=() arg
    for arg in "$@"; do
        case "$arg" in
            --no-system|--system|--with-system|--pam|--no-pam|--xwww|--no-xwww|--font|--no-font|--login|--no-login)
                install_args+=("$arg") ;;
        esac
    done
    confirm "Reset the niri deploy and reinstall from origin/main? User data is preserved." \
        || { warn "aborted"; return 0; }
    if ! reset_network_ok; then
        die "reset aborted: GitHub is unreachable. The current installation was left untouched."
    fi
    RESET_SNAPSHOT=""
    snapshot_reset_state
    overlay_remove_all
    undeploy_niri
    # Managed plugin payload (the user's plugins-user/ is never touched).
    run rm -rf "$QS/ui/plugins" "$HYPR/plugins"
    run rm -f "$QS"/plugin-*.qml

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

    if ! ( cmd_install "${install_args[@]}" ); then
        if restore_reset_state "$RESET_SNAPSHOT"; then
            warn "reset install failed; restored the pre-reset shell/config snapshot"
        else
            warn "reset install failed; snapshot kept at ${RESET_SNAPSHOT:-$STATE/backups}"
        fi
        die "reset failed; the previous desktop payload was restored where possible"
    fi
    ok "reset finished"
}

cmd_uninstall() {
    confirm "Reverse the niri deploy (overlay, user units, portal, session file, wrappers)? Clones and config are kept." \
        || { warn "aborted"; return 0; }
    overlay_remove_all
    undeploy_niri_integration
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
