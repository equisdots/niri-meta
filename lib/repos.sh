#!/usr/bin/env bash
# equisdots-niri · niri-meta
# repos.sh — managed repo registry, cloning, updates and listing.
#
# Two kinds of repos:
#   own     the niri stack owned by this meta (cloned into BASE_NIRI, updated
#           on install/update)
#   shared  the equisdots repos this meta consumes READ-ONLY (they live in the
#           shared clone root BASE_SHARED and are updated by `dots`)

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'repos.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

# Registry entries are `kind|org|name`.
REPO_SPECS=(
    "own|equisdots|niri-meta"
    "own|equisdots|niri"
    "own|equisdots|niri-shell"
    "own|equisdots|nyx-niri"
    "shared|equisdots|shell"
    "shared|equisdots|nyx"
    "shared|equisdots|palettes"
    "shared|equisdots|theme-sync"
    "shared|equisdots|davincix"
    "shared|equisdots|timex"
    "shared|equisdots|login"
    "shared|equisdots|background"
)

# Print every managed repo name, one per line.
repos_all() {
    local spec
    for spec in "${REPO_SPECS[@]}"; do
        printf '%s\n' "${spec##*|}"
    done
}

# Print the full spec line for a repo name.
repo_spec_for() {
    local want="$1" spec
    for spec in "${REPO_SPECS[@]}"; do
        if [[ "${spec##*|}" == "$want" ]]; then
            printf '%s' "$spec"
            return 0
        fi
    done
    return 1
}

repo_kind() {
    local spec
    spec="$(repo_spec_for "$1")" || return 1
    printf '%s' "${spec%%|*}"
}

repo_org() {
    local spec rest
    spec="$(repo_spec_for "$1")" || return 1
    rest="${spec#*|}"
    printf '%s' "${rest%%|*}"
}

# Directory that holds the clone of a repo.
repo_root() {
    case "$(repo_kind "$1")" in
        own)    printf '%s' "$BASE_NIRI" ;;
        shared) printf '%s' "$BASE_SHARED" ;;
        *)      return 1 ;;
    esac
}

repo_path() {
    printf '%s/%s' "$(repo_root "$1")" "$1"
}

# ── Cloning and pulling ─────────────────────────────────────────────────────

clone_repo() {
    local name="$1" root org path
    root="$(repo_root "$name")" || return 1
    org="$(repo_org "$name")"
    path="$root/$name"

    [[ -d "$path/.git" ]] && return 0

    # An existing non-git copy (manual install) is parked instead of failing.
    if [[ -e "$path" ]]; then
        warn "$name: $path is not a git clone; parking it as $name.pre-dotsniri"
        run mv "$path" "$path.pre-dotsniri"
    fi

    run mkdir -p "$root"
    msg "cloning $org/$name -> $path"
    if (( DRY_RUN )); then
        return 0
    fi
    if git clone --depth 1 --recurse-submodules \
        "https://github.com/$org/$name.git" "$path" --quiet; then
        ok "$name cloned"
    else
        warn "$name: clone failed (network? git missing?)"
        return 1
    fi
}

# Force the checkout onto origin/main. Own clones are treated as read-only; a
# dirty clone is kept and its payload is skipped elsewhere.
pull_repo() {
    local name="$1" path
    path="$(repo_path "$name")"
    if [[ ! -d "$path/.git" ]]; then
        warn "$name: not cloned"
        return 0
    fi
    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
        warn "$name: local changes; keeping the checkout (its payload is skipped)"
        return 0
    fi
    if (( DRY_RUN )); then
        printf '   [dry-run] git -C %s fetch --depth 1 origin main && reset --hard FETCH_HEAD\n' "$path"
        return 0
    fi
    if git -C "$path" fetch --depth 1 origin main --quiet 2>/dev/null \
        && git -C "$path" reset --hard FETCH_HEAD --quiet; then
        ok "$name updated"
    else
        warn "$name: fetch failed (network?); using the existing checkout"
    fi

    # Keep submodules in sync when the repo ships them.
    if [[ -f "$path/.gitmodules" ]]; then
        if git -C "$path" submodule sync --recursive >/dev/null 2>&1 \
            && git -C "$path" submodule update --init --recursive --quiet 2>/dev/null; then
            ok "$name submodules"
        else
            warn "$name: submodule update failed (network?)"
        fi
    fi
}

# ensure_repo — clone if missing; own repos are updated, shared repos are left
# exactly as they are (read-only contract).
ensure_repo() {
    local name="$1" kind
    kind="$(repo_kind "$name")"
    if [[ -d "$(repo_path "$name")/.git" ]]; then
        if [[ "$kind" == own ]]; then
            pull_repo "$name"
        else
            note "$name: shared clone present (read-only; updated by 'dots')"
        fi
    else
        clone_repo "$name"
    fi
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_install() {
    require git
    local name n=0
    while IFS= read -r name; do
        ensure_repo "$name" || true
        [[ -d "$(repo_path "$name")" ]] && n=$((n + 1))
    done < <(repos_all)
    cmd_deploy
    ok "install finished ($n/${#REPO_SPECS[@]} repos present)"
}

cmd_update() {
    require git
    local name kind
    while IFS= read -r name; do
        kind="$(repo_kind "$name")"
        if [[ "$kind" == own ]]; then
            pull_repo "$name"
        else
            note "$name: shared clone is read-only for dotsniri (use 'dots update')"
        fi
    done < <(repos_all)
    cmd_deploy
}

cmd_list() {
    printf '%-8s %-12s %-10s %s\n' KIND REPO STATE PATH
    local name kind path state
    while IFS= read -r name; do
        kind="$(repo_kind "$name")"
        path="$(repo_path "$name")"
        if [[ -d "$path/.git" ]]; then
            if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
                state=dirty
            else
                state=clean
            fi
        else
            state=missing
        fi
        printf '%-8s %-12s %-10s %s\n' "$kind" "$name" "$state" "$path"
    done < <(repos_all)
}
