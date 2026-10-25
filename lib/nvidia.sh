#!/usr/bin/env bash
# equisdots-niri · niri-meta
# nvidia.sh — detect an NVIDIA GPU and offer/apply the Arch Wayland setup.
#
# The setup mirrors equisdots/hyprland: nvidia-dkms + kernel headers, the
# mkinitcpio modules, nvidia_drm.modeset on GRUB/systemd-boot, nouveau
# blacklisting, nvidia-drm options and the optional envycontrol sudoers rule.
# It runs only when the user accepts the offer (or with --nvidia); without an
# NVIDIA GPU it is a no-op. AMD/Intel drivers stay distro-managed.

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    printf 'nvidia.sh must be sourced, not executed\n' >&2
    exit 1
}
set -euo pipefail

nvidia_detected() {
    local dev vendor
    for dev in /sys/bus/pci/devices/*; do
        [[ -r "$dev/vendor" ]] || continue
        read -r vendor < "$dev/vendor" 2>/dev/null || continue
        [[ "$vendor" == "0x10de" ]] && return 0
    done
    if have lspci; then
        lspci -nn 2>/dev/null | grep -qi '\[10de:'
    else
        return 1
    fi
}

nvidia_kernel_headers() {
    case "$(uname -r)" in
        *-zen*) printf 'linux-zen-headers' ;;
        *-lts*) printf 'linux-lts-headers' ;;
        *)      printf 'linux-headers' ;;
    esac
}

# Arch-only NVIDIA configuration. Returns non-zero if a required step fails so
# the caller can abort the system phase instead of silently skipping it.
nvidia_arch_configure() {
    local headers driver conf entry boot_configured=0

    headers="$(nvidia_kernel_headers)"
    driver="nvidia-dkms"
    msg "NVIDIA: installing $driver, $headers and Wayland userspace"
    if ! as_root pacman -S --needed --noconfirm \
        "$headers" "$driver" nvidia-utils nvidia-settings \
        libva-nvidia-driver egl-wayland; then
        warn "NVIDIA: driver package installation failed"
        return 1
    fi

    if ! have envycontrol; then
        if have paru; then
            paru -S --needed --noconfirm envycontrol || { warn "NVIDIA: envycontrol install failed"; return 1; }
        elif have yay; then
            yay -S --needed --noconfirm envycontrol || { warn "NVIDIA: envycontrol install failed"; return 1; }
        else
            warn "NVIDIA: envycontrol needs an AUR helper (paru/yay)"
            return 1
        fi
    fi

    conf="/etc/mkinitcpio.conf"
    if [[ ! -f "$conf" ]]; then
        warn "NVIDIA: $conf not found"
        return 1
    fi
    [[ -f "$conf.equisdots-backup" ]] || as_root cp -a "$conf" "$conf.equisdots-backup" || return 1
    if ! grep -q 'nvidia nvidia_modeset nvidia_uvm nvidia_drm' "$conf"; then
        as_root sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$conf" \
            || return 1
    fi
    msg "NVIDIA: regenerating the initramfs"
    as_root mkinitcpio -P || { warn "NVIDIA: mkinitcpio failed"; return 1; }

    if have grub-mkconfig && [[ -f /etc/default/grub ]]; then
        [[ -f /etc/default/grub.equisdots-backup ]] \
            || as_root cp -a /etc/default/grub /etc/default/grub.equisdots-backup || return 1
        if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
            as_root sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1 /' \
                /etc/default/grub || return 1
        fi
        as_root grub-mkconfig -o /boot/grub/grub.cfg || { warn "NVIDIA: grub-mkconfig failed"; return 1; }
        boot_configured=1
    fi

    for entry in /boot/loader/entries/*.conf; do
        [[ -f "$entry" ]] || continue
        if ! grep -q 'nvidia_drm.modeset=1' "$entry"; then
            as_root sed -i '/^options/ s/$/ nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1/' "$entry" \
                || return 1
        fi
        boot_configured=1
    done
    if (( ! boot_configured )); then
        warn "NVIDIA: no GRUB or systemd-boot configuration found; add nvidia_drm.modeset=1 manually"
        return 1
    fi

    as_root systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service \
        >/dev/null 2>&1 || warn "NVIDIA: could not enable all power-management services"

    printf 'blacklist nouveau\noptions nouveau modeset=0\n' \
        | as_root tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null || return 1
    printf 'options nvidia-drm modeset=1 fbdev=1\n' \
        | as_root tee /etc/modprobe.d/nvidia.conf >/dev/null || return 1

    if (( ASSUME_YES )) || confirm "Enable GPU performance mode (envycontrol) with a sudoers rule? [y/N]"; then
        printf '%%wheel ALL=(ALL) NOPASSWD: /usr/bin/envycontrol -s *\n' \
            | as_root tee /etc/sudoers.d/99-gpu-mode >/dev/null || return 1
        as_root chmod 440 /etc/sudoers.d/99-gpu-mode || return 1
    fi

    ok "NVIDIA: driver and boot configuration installed (reboot required)"
    return 0
}

# nvidia_step auto|yes|no
#   auto: detect and offer; no GPU (or declined) is a successful skip
#   yes:  require an NVIDIA GPU and apply without asking
#   no:   explicit opt-out
nvidia_step() {
    local mode="${1:-auto}"

    case "$mode" in
        no)
            note "NVIDIA: skipped (--no-nvidia)"
            return 0
            ;;
        yes|auto) ;;
        *) mode=auto ;;
    esac

    if ! nvidia_detected; then
        if [[ "$mode" == yes ]]; then
            warn "NVIDIA: --nvidia requested but no NVIDIA GPU was detected"
            return 1
        fi
        note "NVIDIA: no NVIDIA GPU detected; skipping"
        return 0
    fi

    if ! distro_ids | grep -qx arch; then
        warn "NVIDIA: automatic driver setup is Arch-only; configure the driver manually"
        [[ "$mode" == yes ]] && return 1
        return 0
    fi

    if [[ "$mode" == auto ]]; then
        if (( DRY_RUN )); then
            msg "[dry-run] NVIDIA GPU detected; would offer nvidia-dkms and boot configuration"
            return 0
        fi
        if ! confirm "NVIDIA GPU detected. Install nvidia-dkms and configure Wayland boot parameters? [y/N]"; then
            note "NVIDIA: skipped by user"
            return 0
        fi
    fi

    if (( DRY_RUN )); then
        msg "[dry-run] would run the NVIDIA Arch setup (nvidia-dkms, mkinitcpio, boot params)"
        return 0
    fi

    nvidia_arch_configure
}
