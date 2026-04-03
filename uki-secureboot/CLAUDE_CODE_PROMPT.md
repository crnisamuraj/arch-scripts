# UKI + Secure Boot Setup for CachyOS — Claude Code Prompt

## Context

I run **CachyOS Linux** with **systemd-boot**. I have Secure Boot enabled using
**Unified Kernel Images (UKI)** built natively by **mkinitcpio** and signed
automatically by **sbctl**.

## My System

- **Distro**: CachyOS (Arch-based)
- **Bootloader**: systemd-boot
- **ESP mount**: `/boot`
- **UKI output dir**: `/boot/EFI/Linux/`
- **Signing**: sbctl (manages Secure Boot keys and auto-signs via `zz-sbctl.hook`)
- **Packages**: `systemd-ukify`, `sbctl`, `systemd-boot-manager`

## Architecture

This uses mkinitcpio's native UKI generation — no custom build/sign scripts needed.

### Key config files
- `/etc/kernel/cmdline` — kernel command line
- `/etc/kernel/uki.conf` — UKI build configuration (cmdline + os-release refs)
- `/etc/mkinitcpio.d/*.preset` — `default_uki=` enables UKI output per kernel

### System hooks (from packages, not custom)
- `zz-sbctl.hook` (from `sbctl`) — auto-signs EFI binaries after updates
- `sdboot-systemd-update.hook` (from `systemd-boot-manager`) — updates systemd-boot

### Scripts in this repo
- `install.sh` — one-shot setup: installs deps, creates config, enables UKI in
  presets, rebuilds, signs, registers with sbctl
- `remove.sh` — reverts: comments out `default_uki=`, unmasks systemd-boot-update,
  deregisters UKIs from sbctl, cleans up

## Workflow

```
# First time: create and enroll sbctl keys
sudo sbctl create-keys
sudo sbctl enroll-keys --microsoft

# Run installer
sudo ./install.sh

# Verify
sudo sbctl verify

# Enable Secure Boot in UEFI firmware
```

## Important Details
- All scripts run as root, check for it, and use `set -euo pipefail`
- `systemd-boot-update.service` is masked (UKIs replace direct boot entries)
- `default_image` is kept active in presets (needed by snapper-boot)
- Snapshot UKIs (`snapshot-*`) are skipped during sbctl registration (managed by snapper-boot)
- Legacy paths (`/etc/uki-secureboot/`) are cleaned up during install/remove
