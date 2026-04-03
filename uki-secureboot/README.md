# UKI + Secure Boot Setup for CachyOS (systemd-boot)

## Overview

This setup enables **Unified Kernel Images (UKI)** using mkinitcpio's native UKI
generation, signed automatically via **sbctl** (Secure Boot Certificate Tool).
Everything is handled by existing system hooks — no custom scripts or pacman hooks
are needed.

> **Note**: This project targets **CachyOS** specifically. The `systemd-boot-manager`
> package is from the CachyOS repositories and may not be available on other Arch-based
> distros.

## How It Works

- **mkinitcpio** builds UKIs natively via `default_uki=` in preset files
- **sbctl** manages Secure Boot keys and auto-signs EFI binaries via its `zz-sbctl.hook`
- **systemd-boot-manager** keeps systemd-boot entries in sync via `sdboot-systemd-update.hook`
- **systemd-boot** auto-discovers UKI files in `<ESP>/EFI/Linux/` (Type #2 entries)

No custom pacman hooks or signing scripts are required.

## Configuration Files

| File | Purpose |
|---|---|
| `/etc/kernel/cmdline` | Kernel command line parameters |
| `/etc/kernel/uki.conf` | UKI build configuration for ukify |
| `/etc/mkinitcpio.d/*.preset` | `default_uki=` enables UKI output per kernel |

## Setup

### 1. Prerequisites

Ensure sbctl Secure Boot keys are enrolled before running the installer:

```bash
# Create keys (if not already done)
sudo sbctl create-keys

# Enroll keys into UEFI firmware
sudo sbctl enroll-keys --microsoft
```

> **Note**: `--microsoft` includes Microsoft's keys alongside yours, which is
> needed for booting with third-party UEFI drivers and Option ROMs.

### 2. Run the Installer

```bash
sudo ./install.sh
```

This will:
1. Install dependencies (`systemd-ukify`, `sbctl`, `systemd-boot-manager`)
2. Verify required system hooks exist
3. Create `/etc/kernel/cmdline` (from current boot parameters or legacy location)
4. Create `/etc/kernel/uki.conf`
5. Enable `default_uki=` in all mkinitcpio presets
6. Mask `systemd-boot-update.service` (UKIs replace direct boot entries)
7. Rebuild initramfs + UKIs via mkinitcpio
8. Sign and register all UKIs with sbctl for automatic re-signing

### 3. Verify

```bash
sudo sbctl verify
```

This shows all registered EFI binaries and whether they are properly signed.

### 4. Enable Secure Boot

After confirming the system boots correctly with UKIs, enable Secure Boot in
your UEFI firmware settings.

## Removal

```bash
sudo ./remove.sh
```

This reverts configuration changes:
- Comments out `default_uki=` in mkinitcpio presets
- Unmasks `systemd-boot-update.service`
- Deregisters and removes UKI files from sbctl
- Cleans up legacy install directories

It does **not** uninstall packages or remove `/etc/kernel/cmdline` and
`/etc/kernel/uki.conf` (which may be used by other tools).

## Automatic Updates

After installation, everything is automatic:

- **Kernel install/update**: mkinitcpio rebuilds initramfs + UKI, then
  `zz-sbctl.hook` re-signs the UKI
- **systemd-boot update**: `sdboot-systemd-update.hook` updates the bootloader,
  then `zz-sbctl.hook` re-signs it

## Troubleshooting

### Boot fails after enabling Secure Boot

Disable Secure Boot in BIOS, boot normally, then check signing status:

```bash
sudo sbctl verify
```

Re-sign any unsigned files:

```bash
sudo sbctl sign-all
```

### UKIs not being generated

Check that `default_uki=` is uncommented in your mkinitcpio preset:

```bash
grep default_uki /etc/mkinitcpio.d/*.preset
```

Manually rebuild:

```bash
sudo mkinitcpio -P
```

### sbctl keys not enrolled

```bash
sudo sbctl status
```

If keys aren't enrolled, run:

```bash
sudo sbctl create-keys
sudo sbctl enroll-keys --microsoft
```
