# UKI + Secure Boot Setup for CachyOS — Claude Code Prompt

## Context

I run **CachyOS Linux** with **systemd-boot**. I want Secure Boot enabled using
**Unified Kernel Images (UKI)** built with `ukify` and signed with my **MOK
(Machine Owner Key)**.

## My System

- **Distro**: CachyOS (Arch-based)
- **Bootloader**: systemd-boot
- **ESP mount**: `/boot`
- **UKI output dir**: `/boot/EFI/Linux/`
- **Kernel modules dir**: `/usr/lib/modules/`
- **Installed kernels** (example): `6.18.12-2-cachyos-lts`, `6.19.2-2-cachyos`
- **Kernel naming**: each kver dir has a `pkgbase` file (e.g. `linux-cachyos`, `linux-cachyos-lts`)
- **Initramfs naming**: `/boot/initramfs-<pkgbase>.img` (e.g. `/boot/initramfs-linux-cachyos.img`)
- **Packages needed**: `systemd-ukify`, `sbsigntools`, `mokutil`

## What I Need

Create the following files in `/etc/uki-secureboot/`:

### 1. `generate-mok.sh`
- Generate RSA 2048-bit MOK key pair with `openssl`
- Output: `keys/MOK.key` (private), `keys/MOK.pem` (PEM cert), `keys/MOK.cer` (DER cert)
- Must have `extendedKeyUsage=codeSigning` and `keyUsage=digitalSignature`
- 10-year validity, CN="CachyOS Secure Boot MOK"
- Lock down permissions (600 for key, 700 for keys dir)
- Refuse to overwrite existing keys

### 2. `uki-build.sh`
- Iterate over all installed kernels in `/usr/lib/modules/*/`
- For each kernel: find vmlinuz, match initramfs via `pkgbase` file
- Auto-detect CPU microcode (`/boot/intel-ucode.img` or `/boot/amd-ucode.img`, also check `/usr/lib/firmware/`)
- Build UKI with `ukify build`:
  - `--linux`, `--cmdline=@/etc/uki-secureboot/cmdline`, `--os-release=@/etc/os-release`, `--uname`
  - `--initrd` for microcode FIRST, then main initramfs (order matters!)
- Sign with `sbsign --key MOK.key --cert MOK.pem`
- Verify signature with `sbverify`
- Output to `/boot/EFI/Linux/<pkgbase>-<kver>.efi`
- Use temp file for build, only move to ESP after successful sign

### 3. `uki-remove.sh`
- Scan `/boot/efi/EFI/Linux/*.efi` for UKI files
- Cross-reference with installed kernel versions in `/usr/lib/modules/`
- Remove any `.efi` files whose kver no longer exists

### 4. `cmdline`
- Auto-populate from `/proc/cmdline` during install
- User should review it

### 5. Pacman hooks in `/etc/pacman.d/hooks/`:

**`99-uki-build.hook`** — triggers `uki-build.sh` PostTransaction on:
- Path targets: `usr/lib/modules/*/vmlinuz`, `usr/lib/initcpio/*`, `boot/initramfs-*.img`
- Package targets: `linux*`, `*-ucode`

**`99-uki-remove.hook`** — triggers `uki-remove.sh` PostTransaction on:
- Package target: `linux*` (Remove operation only)

### 6. `install.sh`
- One-shot deployer: installs deps, copies scripts, installs hooks
- Auto-detects ESP, auto-populates cmdline from `/proc/cmdline`
- Prints next-steps summary

## Important Details
- All scripts must run as root, check for it, and exit cleanly on errors (`set -euo pipefail`)
- Use colored log output in install.sh
- The pacman hooks must use `NeedsTargets`
- systemd-boot auto-discovers UKI files in `EFI/Linux/` (Type #2 entries)
- Do NOT overwrite existing cmdline if it already exists

## Workflow After Setup
```
sudo ./install.sh
sudo /etc/uki-secureboot/generate-mok.sh
sudo mokutil --import /etc/uki-secureboot/keys/MOK.cer
# reboot → enroll in MOK Manager
sudo /etc/uki-secureboot/uki-build.sh
# test boot → enable Secure Boot in UEFI
```
