#!/usr/bin/env bash
# equisdots-niri · niri-meta
# plugins.sh — plugin manager for the niri stack (parity with `dots plugins`).
#
# The standard, registry and plugin sources are the shared equisdots repos. The
# niri meta deploys them through the same convention as `dots`:
#   whole plugin   -> $QS/ui/plugins/<id>
#   runtime subset -> $HYPR/plugins/<id> (plugin.json, hypr.lua, scripts/)
#   defaults       -> seed the plugin's own settings.json once
#   standalone     -> one root-level launcher per entry
#
# Commands:
#   dotsniri plugins [list]              installed plugins + state
#   dotsniri plugins available           registry entries with installed state
#   dotsniri plugins add <id> [--no-enable] [--force]
#   dotsniri plugins remove <id>
#   dotsniri plugins enable|disable <id>

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'plugins.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

PLUGIN_HUB="$(repo_path plugins 2>/dev/null || true)"
PLUGIN_REGISTRY="$PLUGIN_HUB/registry.json"

# Resolve an install source directory for an id from the registry.
plugin_source_dir_id() {
    local id="$1" hub="$PLUGIN_HUB" src path
    # Root-level plugin repos (nyx, timex) are already managed clones.
    case "$id" in
        nyx|timex)
            path="$(repo_path "$id" 2>/dev/null || true)"
            [[ -d "$path" ]] && { printf '%s' "$path"; return 0; }
            ;;
    esac
    # Hub concentration folder (the registry source equisdots/plugins).
    if [[ -n "$hub" && -f "$hub/plugins/$id/plugin.json" ]]; then
        printf '%s' "$hub/plugins/$id"; return 0
    fi
    # Registry fallback: clone the source into a private cache (no repo is
    # mutated) and use the optional path.
    [[ -f "$PLUGIN_REGISTRY" ]] || return 1
    src="$(jq -r --arg id "$id" '(.plugins // [])[] | select(.id==$id) | .source' "$PLUGIN_REGISTRY" 2>/dev/null | head -1)"
    [[ -n "$src" ]] || return 1
    local dest="$BASE_NIRI/.plugin-src/$id"
    if [[ ! -d "$dest/.git" ]]; then
        run mkdir -p "$BASE_NIRI/.plugin-src"
        run git clone --depth 1 "https://github.com/$src.git" "$dest" --quiet || return 1
    fi
    path="$(jq -r --arg id "$id" '(.plugins // [])[] | select(.id==$id) | .path // empty' "$PLUGIN_REGISTRY" 2>/dev/null | head -1)"
    [[ -n "$path" ]] && printf '%s' "$dest/$path" || printf '%s' "$dest"
}

plugin_installed_ids() {
    local d
    for d in "$HYPR/plugins" "$HYPR/plugins-user"; do
        [[ -d "$d" ]] || continue
        find "$d" -mindepth 1 -maxdepth 1 -type d -exec sh -c '[ -f "$1/plugin.json" ] && jq -r ".id // empty" "$1/plugin.json"' _ {} \;
    done | sort -u
}

plugin_scan_tsv() {
    local d e pset
    for d in "$HYPR/plugins-user" "$HYPR/plugins"; do
        [[ -d "$d" ]] || continue
        for e in "$d"/*/; do
            [[ -f "${e}plugin.json" ]] || continue
            # Enablement lives in the plugin's OWN settings.json (never the core
            # settings.json): same contract as the shell scan.
            pset='{}'
            [[ -f "${e}settings.json" ]] && pset="$(jq -c . "${e}settings.json" 2>/dev/null || echo '{}')"
            jq -r --arg base "${e%/}" --argjson pset "$pset" '
                . as $m | select(($m.id // "") != "")
                | ($m.toggle // ("plugins." + $m.id + ".enabled")) as $t
                | ($t | split(".")) as $p
                | (try ($pset | getpath($p)) catch null) as $v
                | [ $m.id, ($m.name // $m.id), ($m.version // "-"), ($m.type // "-"),
                    (if (if $v == null then ($m.defaultEnabled // false) else ($v == true) end)
                     then "enabled" else "disabled" end), $base ] | @tsv' \
                "${e}plugin.json" 2>/dev/null || true
        done
    done
}

plugin_set_toggle() {
    local id="$1" on="$2" dir="$HYPR/plugins/$id" manifest="$HYPR/plugins/$id/plugin.json" toggle file path tmp val
    [[ -f "$manifest" ]] || die "plugin $id is not installed (run: dotsniri plugins list)"
    toggle="$(jq -r '.toggle // empty' "$manifest" 2>/dev/null || true)"
    [[ -n "$toggle" ]] || toggle="plugins.$id.enabled"
    file="$dir/settings.json"
    path="$(jq -nc --arg t "$toggle" '$t | split(".")')"
    val="$([[ "$on" == "true" ]] && printf true || printf false)"
    if (( DRY_RUN )); then
        msg "[dry-run] set $toggle=$val in $file"
        return 0
    fi
    mkdir -p "$dir"
    [[ -s "$file" ]] || echo '{}' > "$file"
    tmp="$(mktemp "$file.tmp.XXXXXX")"
    if jq --argjson p "$path" --argjson v "$val" 'setpath($p; $v)' "$file" > "$tmp"; then
        mv "$tmp" "$file"
        ok "plugin $id: $toggle=$val"
    else
        rm -f "$tmp"; die "plugin $id: could not write $file"
    fi
}

cmd_plugins() {
    local sub="${1:-list}" id
    shift || true
    require jq
    case "$sub" in
        list)
            printf '%-16s %-22s %-8s %-8s %s\n' ID NAME VERSION TYPE STATE
            plugin_scan_tsv | awk -F'\t' '!seen[$1]++ {printf "%-16s %-22s %-8s %-8s %s\n",$1,$2,$3,$4,$5}'
            ;;
        available)
            [[ -f "$PLUGIN_REGISTRY" ]] || die "plugins: registry not found ($PLUGIN_REGISTRY)"
            local installed; installed=" $(plugin_installed_ids | tr '\n' ' ')"
            printf '%-16s %-24s %-10s %s\n' ID NAME VERSION STATE
            jq -r '.plugins[] | [.id, (.name // .id), .source, (.path // "-")] | @tsv' "$PLUGIN_REGISTRY" \
                | while IFS=$'\t' read -r pid pname src path; do
                    if [[ "$installed" == *" $pid "* ]]; then st=installed; else st=available; fi
                    printf '%-16s %-24s %-10s %s\n' "$pid" "$pname" "$st" "$src${path:+/$path}"
                done
            ;;
        add)
            id="${1:-}"; [[ -n "$id" ]] || die "usage: dotsniri plugins add <id> [--no-enable] [--force]"
            local no_enable=0 force=0 a src
            shift || true
            for a in "$@"; do
                case "$a" in
                    --no-enable) no_enable=1 ;;
                    --force) force=1 ;;
                esac
            done
            src="$(plugin_source_dir_id "$id" || true)"
            [[ -n "$src" && -f "$src/plugin.json" ]] || die "plugin $id: source not found (try: dotsniri plugins available)"
            deploy_plugin "$src"
            [[ "$no_enable" -eq 1 ]] || plugin_set_toggle "$id" true
            if [[ -f "$src/hypr.lua" ]]; then
                note "plugin $id ships hypr.lua (Hyprland-only); niri uses the static core binds"
            fi
            ;;
        remove)
            id="${1:-}"; [[ -n "$id" ]] || die "usage: dotsniri plugins remove <id>"
            [[ -d "$HYPR/plugins-user/$id" ]] && die "plugin $id: user plugin (plugins-user/), not managed by dotsniri"
            [[ -d "$HYPR/plugins/$id" ]] || die "plugin $id is not installed"
            plugin_set_toggle "$id" false
            run rm -rf "$QS/ui/plugins/$id" "$HYPR/plugins/$id"
            run rm -f "$QS/plugin-$id-"*.qml
            ok "plugin $id removed"
            ;;
        enable|disable)
            id="${1:-}"; [[ -n "$id" ]] || die "usage: dotsniri plugins $sub <id>"
            if [[ "$sub" == "enable" ]]; then plugin_set_toggle "$id" true; else plugin_set_toggle "$id" false; fi
            ;;
        *)
            die "unknown plugins subcommand: $sub (list|available|add|remove|enable|disable)"
            ;;
    esac
}
