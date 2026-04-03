#!/usr/bin/env bash
# setup.sh — Discover all modules and run their setup.sh if present
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[cachyos-scripts]${NC} $*"; }
warn()  { echo -e "${YELLOW}[cachyos-scripts]${NC} $*"; }
error() { echo -e "${RED}[cachyos-scripts]${NC} $*" >&2; }

[[ $EUID -eq 0 ]] || { error "Must run as root: sudo $0"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=()

for module_dir in "$SCRIPT_DIR"/*/; do
    module="$(basename "$module_dir")"
    [[ "$module" != .* ]] || continue
    script="$module_dir/setup.sh"
    [[ -f "$script" ]] || continue

    info "Setting up module: $module"
    if bash "$script"; then
        info "$module — done"
    else
        error "$module — failed (exit $?)"
        failed+=("$module")
    fi
    echo ""
done

if (( ${#failed[@]} )); then
    error "Failed modules: ${failed[*]}"
    exit 1
else
    info "All modules set up successfully."
fi
