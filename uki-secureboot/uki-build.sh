#!/usr/bin/env bash
# uki-build.sh — Build and sign Unified Kernel Images for all installed kernels
# Triggered by pacman hook or run manually: sudo /etc/uki-secureboot/uki-build.sh

set -euo pipefail

log()  { echo "[uki-build] $*"; }
warn() { echo "[uki-build] WARNING: $*" >&2; }
die()  { echo "[uki-build] ERROR: $*" >&2; exit 1; }

# ─── Configuration ───────────────────────────────────────────────────────────
# Auto-detect ESP mount point (override by setting ESP= in environment)
if [[ -z "${ESP:-}" ]]; then
    for _esp in /efi /boot/efi /boot; do
        if mountpoint -q "${_esp}" 2>/dev/null; then
            ESP="${_esp}"
            break
        fi
    done
fi
[[ -n "${ESP:-}" ]] || die "Cannot detect ESP mount point. Run: ESP=/your/esp $0"
UKI_DIR="${ESP}/EFI/Linux"                   # systemd-boot Type #2 auto-discovery
MODULES_DIR="/usr/lib/modules"               # Where kernel modules + vmlinuz live
CMDLINE="/etc/uki-secureboot/cmdline"        # Kernel command line file
OSRELEASE="/etc/os-release"                  # OS release file for UKI
SPLASH=""                                    # Optional: path to BMP splash image
UCODE=""                                     # Auto-detected below
# ─────────────────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || die "Must run as root."

# Validate prerequisites
command -v ukify  >/dev/null 2>&1 || die "ukify not found. Install systemd-ukify."
command -v sbctl  >/dev/null 2>&1 || die "sbctl not found. Install sbctl."
[[ -f "${CMDLINE}" ]]             || die "Kernel cmdline not found at ${CMDLINE}."

# Ensure output directory exists
mkdir -p "${UKI_DIR}"

# Auto-detect CPU microcode initrd
for ucode_candidate in \
    "/boot/intel-ucode.img" \
    "/boot/amd-ucode.img" \
    "/efi/intel-ucode.img" \
    "/efi/amd-ucode.img" \
    "/usr/lib/firmware/intel-ucode.img" \
    "/usr/lib/firmware/amd-ucode.img"; do
    if [[ -f "${ucode_candidate}" ]]; then
        UCODE="${ucode_candidate}"
        log "Detected microcode: ${UCODE}"
        break
    fi
done

# Build UKI for each installed kernel
built=0
for kdir in "${MODULES_DIR}"/*/; do
    [[ -d "${kdir}" ]] || continue

    kver="$(basename "${kdir}")"
    vmlinuz="${kdir}vmlinuz"
    initrd="/boot/initramfs-${kver}.img"

    # CachyOS may use different naming — try fallbacks
    if [[ ! -f "${initrd}" ]]; then
        # Try without full kver (e.g., initramfs-linux-cachyos.img)
        for candidate in /boot/initramfs-*.img; do
            # Match by checking if the preset references this kver
            if [[ -f "${candidate}" ]] && [[ "${candidate}" != *"-fallback"* ]]; then
                # Check if this initramfs corresponds to our kernel version
                preset_name="$(basename "${candidate}" .img)"
                preset_name="${preset_name#initramfs-}"
                if [[ -f "/usr/lib/modules/${kver}/pkgbase" ]]; then
                    pkgbase="$(< "/usr/lib/modules/${kver}/pkgbase")"
                    if [[ "${preset_name}" == "${pkgbase}" ]]; then
                        initrd="${candidate}"
                        break
                    fi
                fi
            fi
        done
    fi

    if [[ ! -f "${vmlinuz}" ]]; then
        warn "No vmlinuz for ${kver}, skipping."
        continue
    fi

    if [[ ! -f "${initrd}" ]]; then
        warn "No initramfs for ${kver}, skipping."
        continue
    fi

    # Determine output filename
    # Use pkgbase if available for cleaner names (e.g., cachyos-linux-6.12.1.efi)
    if [[ -f "${MODULES_DIR}/${kver}/pkgbase" ]]; then
        pkgbase="$(< "${MODULES_DIR}/${kver}/pkgbase")"
        uki_name="${pkgbase}-${kver}.efi"
    else
        uki_name="linux-${kver}.efi"
    fi

    uki_path="${UKI_DIR}/${uki_name}"
    uki_backup="${uki_path}.bak"

    # Back up existing UKI so it can be restored if the build or signing fails
    [[ -f "${uki_path}" ]] && cp "${uki_path}" "${uki_backup}"

    log "Building UKI: ${uki_name}"
    log "  Kernel  : ${vmlinuz}"
    log "  Initrd  : ${initrd}"
    [[ -n "${UCODE}" ]] && log "  Microcode: ${UCODE}"

    _restore() {
        if [[ -f "${uki_backup}" ]]; then
            mv "${uki_backup}" "${uki_path}"
            warn "Restored previous UKI: ${uki_path}"
        else
            rm -f "${uki_path}"
        fi
    }

    # Assemble ukify arguments
    # NOTE: --initrd order matters! Microcode must come BEFORE main initramfs.
    ukify_args=(
        build
        --linux="${vmlinuz}"
        --cmdline="@${CMDLINE}"
        --os-release="@${OSRELEASE}"
        --uname="${kver}"
        --output="${uki_path}"
    )

    # Microcode first (if available), then main initrd
    if [[ -n "${UCODE}" ]]; then
        ukify_args+=(--initrd="${UCODE}")
    fi
    ukify_args+=(--initrd="${initrd}")

    # Optional splash
    if [[ -n "${SPLASH}" && -f "${SPLASH}" ]]; then
        ukify_args+=(--splash="${SPLASH}")
    fi

    # Build the UKI
    if ! ukify "${ukify_args[@]}"; then
        warn "ukify failed for ${kver}"
        _restore
        continue
    fi

    # Sign with sbctl and register in database for automatic re-signing on future updates
    log "Signing and registering UKI with sbctl..."
    if ! sbctl sign -s "${uki_path}"; then
        warn "sbctl sign failed for ${kver}"
        _restore
        continue
    fi

    rm -f "${uki_backup}"
    log "Built and signed: ${uki_path}"
    built=$((built + 1))
done

if [[ ${built} -eq 0 ]]; then
    warn "No UKIs were built. Check kernel installations."
    exit 1
fi

log "Done. Built and signed ${built} UKI(s)."
