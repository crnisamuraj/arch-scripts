#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }

[[ $EUID -ne 0 ]] && { error "Must run as root"; exit 1; }

info "Enforcing all AppArmor profiles..."
find /etc/apparmor.d/ -maxdepth 1 -type f -exec aa-enforce {} + 2>/dev/null || true

info "Reloading AppArmor profiles..."
if ! systemctl reload apparmor.service 2>/dev/null; then
    if ! apparmor_parser -r /etc/apparmor.d/ 2>/dev/null; then
        error "Failed to reload AppArmor profiles via both systemctl and apparmor_parser."
        error "Is AppArmor active? Check: cat /sys/module/apparmor/parameters/enabled"
        exit 1
    fi
fi

info "All profiles enforced."
