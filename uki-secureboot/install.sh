#!/usr/bin/env bash
# install.sh — Deploy UKI + Secure Boot setup to the system
# Usage: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
die()  { echo -e "${RED}[install] ERROR:${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Must run as root: sudo ./install.sh"

# ─── Check dependencies ─────────────────────────────────────────────────────
log "Checking dependencies..."
missing=()
for pkg in systemd-ukify sbctl; do
    if ! pacman -Qi "${pkg}" >/dev/null 2>&1; then
        missing+=("${pkg}")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    log "Installing missing packages: ${missing[*]}"
    pacman -S --needed --noconfirm "${missing[@]}"
fi

# ─── Verify required system hooks are present ───────────────────────────────
# We rely on these distro-provided hooks to update and sign the bootloader.
# Without them the signing chain breaks — abort before modifying anything.
log "Checking required system hooks..."
required_hooks=(
    /usr/share/libalpm/hooks/sdboot-systemd-update.hook  # runs bootctl update on systemd upgrade
    /usr/share/libalpm/hooks/zz-sbctl.hook               # re-signs EFI after updates
)
missing_hooks=()
for hook in "${required_hooks[@]}"; do
    [[ -f "${hook}" ]] || missing_hooks+=("${hook}")
done
if [[ ${#missing_hooks[@]} -gt 0 ]]; then
    die "Required system hooks not found — install the packages that provide them:
$(printf '  %s\n' "${missing_hooks[@]}")
  sdboot-systemd-update.hook → sdboot-manage
  zz-sbctl.hook              → sbctl"
fi
log "Required hooks present."

# ─── Deploy scripts ─────────────────────────────────────────────────────────
log "Deploying scripts to /etc/uki-secureboot/..."
mkdir -p /etc/uki-secureboot

cp "${SCRIPT_DIR}/uki-build.sh"  /etc/uki-secureboot/
cp "${SCRIPT_DIR}/uki-remove.sh" /etc/uki-secureboot/

chmod 700 /etc/uki-secureboot/*.sh

# ─── Kernel command line ─────────────────────────────────────────────────────
if [[ ! -f /etc/uki-secureboot/cmdline ]]; then
    # Strip bootloader-specific tokens that must not be embedded in a UKI:
    #   BOOT_IMAGE=  — set by the bootloader, meaningless inside UKI
    #   initrd=      — the initramfs is embedded; an extra initrd= causes conflicts
    raw_cmdline="$(cat /proc/cmdline)"
    clean_cmdline="$(echo "${raw_cmdline}" \
        | sed 's/BOOT_IMAGE=[^ ]*[[:space:]]*//g' \
        | sed 's/initrd=[^ ]*[[:space:]]*//g' \
        | sed 's/[[:space:]]*$//')"
    log "Writing cmdline: ${clean_cmdline}"
    echo "${clean_cmdline}" > /etc/uki-secureboot/cmdline
    warn "Review /etc/uki-secureboot/cmdline and adjust if needed!"
else
    log "Kernel cmdline already exists, not overwriting."
fi

# ─── Deploy pacman hooks ────────────────────────────────────────────────────
log "Installing pacman hooks..."
mkdir -p /etc/pacman.d/hooks

cp "${SCRIPT_DIR}/99-uki-build.hook"  /etc/pacman.d/hooks/
cp "${SCRIPT_DIR}/99-uki-remove.hook" /etc/pacman.d/hooks/

# ─── Mask systemd-boot-update.service ───────────────────────────────────────
# The service runs bootctl update at boot with no signing step after it.
# Bootloader updates are handled by sdboot-systemd-update.hook + zz-sbctl.hook
# during pacman transactions, which sign after updating.
log "Masking systemd-boot-update.service..."
systemctl mask systemd-boot-update.service

# ─── Disable mkinitcpio's default UKI/copying hooks if present ──────────────
# CachyOS may ship hooks that copy vmlinuz/initramfs to ESP — we handle that now
if [[ -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook ]]; then
    warn "Found existing mkinitcpio install hook — you may want to review"
    warn "  /etc/pacman.d/hooks/90-mkinitcpio-install.hook"
    warn "to avoid duplicate ESP entries."
fi

# ─── Detect ESP and create UKI output dir ───────────────────────────────────
esp_mount=""
for candidate in /efi /boot/efi /boot; do
    if mountpoint -q "${candidate}" 2>/dev/null; then
        esp_mount="${candidate}"
        break
    fi
done

if [[ -z "${esp_mount}" ]]; then
    warn "Could not auto-detect ESP mount point — scripts will detect it at runtime."
else
    log "Detected ESP at: ${esp_mount}"
    mkdir -p "${esp_mount}/EFI/Linux"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
log "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Review /etc/uki-secureboot/cmdline (auto-detected from current boot)"
echo "  2. Generate Secure Boot keys:"
echo "       sudo sbctl create-keys"
echo "  3. Enroll keys in firmware (enter Setup Mode in UEFI first):"
echo "       sudo sbctl enroll-keys --microsoft"
echo "  4. Sign systemd-boot EFI binaries and register with sbctl:"
echo "       sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI"
echo "       sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi"
echo "  5. Build and sign initial UKIs:"
echo "       sudo /etc/uki-secureboot/uki-build.sh"
echo "  6. Verify all binaries are signed:"
echo "       sudo sbctl verify"
echo "  7. Reboot and enable Secure Boot in UEFI settings"
echo ""
echo "Note: systemd-boot-update.service is masked by this installer."
echo "  Bootloader updates are handled by sdboot-systemd-update.hook + zz-sbctl.hook."
echo ""
warn "IMPORTANT: Keep a USB recovery drive ready before enabling Secure Boot!"
