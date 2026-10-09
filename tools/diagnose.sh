#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# equisdots niri — diagnostic report
#
# READ-ONLY. Collects everything needed to debug why a niri session does not
# start from the display manager. Prints a report to stdout.
#
#   bash tools/diagnose.sh | tee ~/niri-report.txt
#
# Nothing here modifies the system. Review the output before sharing if it
# contains serial numbers or hostnames you consider sensitive.
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
sec()  { printf '\n===== %s =====\n' "$*"; }
try()  { "$@" 2>&1 || printf '(failed: %s)\n' "$*"; }

sec "system"
try cat /etc/os-release
printf 'kernel: %s\n' "$(uname -r)"
printf 'arch:   %s\n' "$(uname -m)"
printf 'user:   %s\n' "$(id)"
printf 'HOME=%s\n' "$HOME"
printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME:-<unset>}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-<unset>}"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-<unset>}"
printf 'XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-<unset>}"

sec "display manager"
try systemctl status display-manager --no-pager
printf 'display-manager unit -> %s\n' "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || echo '<none>')"

sec "gpu"
have lspci && lspci 2>/dev/null | grep -iE 'vga|3d|display' || echo '(lspci unavailable)'
try ls -l /dev/dri

sec "niri binaries"
for b in niri niri-session; do
    printf '%-14s ' "$b"
    if have "$b"; then command -v "$b"; else echo MISSING; fi
done
have niri && try niri --version

sec "session entries"
for d in /usr/share/wayland-sessions /usr/local/share/wayland-sessions "$HOME/.local/share/wayland-sessions"; do
    echo "-- $d"
    if [[ -d "$d" ]]; then
        ls -la "$d"
        for f in "$d"/niri.desktop; do
            [[ -f "$f" ]] && { echo "## $f"; cat "$f"; }
        done
    else
        echo "(missing)"
    fi
done

sec "sddm config"
shopt -s nullglob
for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf /usr/lib/sddm/sddm.conf.d/*.conf; do
    echo "## $f"
    cat "$f" 2>/dev/null
done
shopt -u nullglob

sec "niri config"
if have niri; then
    try niri validate -c "$HOME/.config/niri/config.kdl"
else
    echo "(niri not installed; skipping validate)"
fi
ls -la "$HOME/.config/niri" 2>/dev/null || echo "(no ~/.config/niri)"

sec "sddm wayland session log (last 60)"
if [[ -f "$HOME/.local/share/sddm/wayland-session.log" ]]; then
    tail -n 60 "$HOME/.local/share/sddm/wayland-session.log"
else
    echo "(no ~/.local/share/sddm/wayland-session.log)"
fi

sec "journal: sddm (this boot)"
have journalctl && try journalctl -b -u sddm.service --no-pager -n 60

sec "journal: niri mentions (this boot, user)"
have journalctl && { journalctl --user -b --no-pager 2>/dev/null | grep -i niri | tail -n 40 || echo '(none)'; }

sec "journal: recent user messages"
have journalctl && tail -n 30 <(journalctl --user -b --no-pager 2>/dev/null) || echo '(unavailable)'

sec "coredumps"
have coredumpctl && try coredumpctl list --no-pager

sec "dependencies"
for b in quickshell qs xwayland-satellite dbus-daemon dbus-broker swayidle swaybg; do
    printf '%-22s ' "$b"
    have "$b" && command -v "$b" || echo MISSING
done
for b in xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk; do
    printf '%-32s ' "$b"
    have "$b" && command -v "$b" || echo MISSING
done

sec "logind session"
if have loginctl; then
    sid="$(loginctl --no-legend list-sessions 2>/dev/null | awk 'NR==1{print $1}')"
    [[ -n "$sid" ]] && try loginctl show-session "$sid" || echo '(no session)'
fi

sec "equisdots niri state"
ls -la "$HOME/.local/share/equisdots-niri" 2>/dev/null || echo '(no ~/.local/share/equisdots-niri)'
ls -la "$HOME/.local/bin/dotsniri" 2>/dev/null || echo '(no dotsniri wrapper)'
ls -la "$HOME/.local/state/equisdots-niri" 2>/dev/null || echo '(no state dir)'
if [[ -d "$HOME/.local/state/equisdots-niri/overlay" ]]; then
    for f in "$HOME/.local/state/equisdots-niri/overlay"/*/manifest; do
        [[ -f "$f" ]] && { echo "## $f"; cat "$f"; }
    done
fi

printf '\n===== end of report =====\n'
