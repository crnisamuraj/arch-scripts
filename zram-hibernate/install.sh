#!/usr/bin/env bash
# install.sh — Deploy zram-hibernate scripts to /etc/zram-hibernate/
# Usage: sudo ./install.sh [--setup]
#   --setup   Also run setup-hibernate.sh immediately after deploying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
die()  { echo -e "${RED}[install] ERROR:${NC} $*" >&2; exit 1; }

RUN_SETUP=false
for arg in "$@"; do
    case "$arg" in
        --setup) RUN_SETUP=true ;;
        *) die "Unknown argument: $arg. Usage: sudo ./install.sh [--setup]" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Must run as root: sudo $0"

# ─── Check dependencies ───────────────────────────────────────────────────────

log "Checking dependencies..."
if ! pacman -Qi btrfs-progs >/dev/null 2>&1; then
    log "Installing btrfs-progs..."
    pacman -S --needed --noconfirm btrfs-progs
else
    log "btrfs-progs already installed."
fi

# ─── Deploy scripts ───────────────────────────────────────────────────────────

log "Deploying scripts to /etc/zram-hibernate/..."
mkdir -p /etc/zram-hibernate

cp "${SCRIPT_DIR}/setup-hibernate.sh"  /etc/zram-hibernate/
cp "${SCRIPT_DIR}/remove-hibernate.sh" /etc/zram-hibernate/
chmod 700 /etc/zram-hibernate/*.sh

log "Scripts deployed."

# ─── Optional: run setup immediately ─────────────────────────────────────────

if $RUN_SETUP; then
    log "Running setup (--setup flag passed)..."
    exec /etc/zram-hibernate/setup-hibernate.sh
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
log "Installation complete!"
echo ""
echo "Now run:"
echo "  sudo /etc/zram-hibernate/setup-hibernate.sh"
echo ""
echo "To undo everything later:"
echo "  sudo /etc/zram-hibernate/remove-hibernate.sh"
echo ""
