# Hibernate-to-File with ZRAM on CachyOS — Claude Code Prompt

## Context

I run **CachyOS Linux** with **systemd-boot** and already have the **UKI +
Secure Boot** setup from `uki-secureboot/` in this repo. I want to enable
**hibernate-to-swapfile** on a **BTRFS** filesystem, co-existing with **ZRAM**
(which stays as the primary swap for normal use). The system uses **AppArmor**
(not SELinux).

Reference implementation: `zram-hibernate/bazzite-hibernate.sh` (written for
Fedora Atomic / rpm-ostree / SELinux — adapted for CachyOS/Arch/AppArmor here).

## My System

- **Distro**: CachyOS (Arch-based)
- **Bootloader**: systemd-boot + UKI (via existing `uki-secureboot/` setup)
- **Kernel cmdline file**: `/etc/uki-secureboot/cmdline` (single-line file —
  UKI embeds the cmdline and is rebuilt by `uki-build.sh`)
- **Initramfs tool**: `mkinitcpio` (not dracut)
- **MAC system**: AppArmor (not SELinux)
- **Filesystem**: BTRFS
- **ZRAM**: configured via `zram-generator`, typically priority 100
- **Swapfile target**: `/var/swap/swapfile`
- **Packages needed**: `btrfs-progs` (already installed)

## What I Need

Create the following files in `zram-hibernate/` in this repo,
to be installed to `/etc/zram-hibernate/`:

---

### 1. `setup-hibernate.sh`

Main installer. Must run as root (`set -euo pipefail`, colored output).

Use consistent log helpers matching `uki-secureboot/` style:
```bash
log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup]${NC} $*"; }
die()  { echo -e "${RED}[setup] ERROR:${NC} $*" >&2; exit 1; }
```

#### Pre-flight checks (before any changes)

1. Root check (`$EUID -ne 0`)
2. Dependency check: `btrfs`, `findmnt`, `bc` — die if any missing
3. **`resume` hook gate** — check `/etc/mkinitcpio.conf` HOOKS line:
   - If `resume` is present but NOT after `filesystems`: warn and die
   - If `resume` is absent entirely: die with clear instructions:
     ```
     ERROR: 'resume' hook not found in /etc/mkinitcpio.conf HOOKS.
     Add 'resume' after 'filesystems' in the HOOKS line, e.g.:
       HOOKS=(base udev autodetect ... filesystems resume fsck)
     Then re-run this script.
     ```
   - Rationale: running mkinitcpio without the resume hook builds a useless
     initramfs that silently fails to resume — blocking here is safer.

#### Steps (in order, after pre-flight passes)

1. **Calculate swap size**: RAM (rounded up to GB) + 4 GB buffer
2. **Create BTRFS swapfile** at `/var/swap/swapfile`:
   - If `/var/swap` does not exist: `btrfs subvolume create /var/swap`
   - If `/var/swap` exists as a regular directory (not a subvolume): die with
     explanation (user must investigate)
   - Check with: `btrfs subvolume show /var/swap 2>/dev/null`
   - `chattr +C /var/swap` (disable CoW — required for BTRFS swap)
   - `btrfs filesystem mkswapfile --size ${N}G /var/swap/swapfile`
   - `chmod 600 /var/swap/swapfile`
   - Skip silently if swapfile already exists
3. **Configure /etc/fstab**:
   - Append: `/var/swap/swapfile none swap defaults,pri=0 0 0`
   - `pri=0` keeps ZRAM (pri=100) as default swap; swapfile only used for hibernate
   - Skip if already present
   - Run `swapon /var/swap/swapfile` immediately (ignore if already active)
4. **Get resume parameters**:
   - `RESUME_UUID=$(findmnt -no UUID -T /var/swap/swapfile)`
   - `RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /var/swap/swapfile)`
   - Print both for user confirmation
5. **Update kernel cmdline** (UKI-aware):
   - File: `/etc/uki-secureboot/cmdline` (single-line format)
   - **Strip-and-replace** approach (handles re-runs with updated values):
     - Remove any existing `resume=UUID=...` and `resume_offset=...` tokens
     - Append `resume=UUID=$RESUME_UUID resume_offset=$RESUME_OFFSET`
   - Do NOT modify anything else in the cmdline
   - Log the old and new cmdline for the user to review
6. **Configure mkinitcpio**:
   - Do NOT auto-edit `/etc/mkinitcpio.conf` (too risky)
   - Do NOT write a drop-in (mkinitcpio drop-in syntax for HOOKS is not
     straightforward without knowing the user's full HOOKS array)
   - Pre-flight already verified `resume` is present and correctly ordered
   - Run `mkinitcpio -P` here (pre-flight gate guarantees it will be correct)
7. **Rebuild UKI**:
   - Call `/etc/uki-secureboot/uki-build.sh` (no `sudo` — already root)
   - Must run AFTER `mkinitcpio -P` so the UKI embeds the latest initramfs
     AND the updated cmdline
   - Note: the pacman hook (`99-uki-build.hook`) only fires on package updates,
     not on manual `mkinitcpio -P` — explicit call is required
8. **Install AppArmor local override** for systemd-sleep:
   - See AppArmor section below
9. **Configure systemd sleep** (drop-in files, not editing originals):
   - Write `/etc/systemd/logind.conf.d/hibernate.conf`:
     ```
     [Login]
     HandleLidSwitch=suspend-then-hibernate
     HandleLidSwitchExternalPower=suspend-then-hibernate
     ```
   - Write `/etc/systemd/sleep.conf.d/hibernate.conf`:
     ```
     [Sleep]
     HibernateDelaySec=2h
     HibernateMode=platform
     ```
   - `systemctl daemon-reload` after
10. **Print next-steps summary** (colored):
    - Remind to reboot before testing hibernate
    - Manual test: `systemctl hibernate`
    - Verify: `cat /sys/power/resume`, `cat /sys/power/resume_offset`

---

### 2. AppArmor override for systemd-sleep

The AppArmor profile for systemd-sleep is at:
`/etc/apparmor.d/systemd-sleep`

It already contains `include if exists <local/systemd-sleep>` at the bottom,
so the local override at `/etc/apparmor.d/local/systemd-sleep` will be
automatically included when the profile is loaded.

The profile currently allows `@{sys}/power/state rw` but NOT the paths needed
for hibernate (`resume`, `resume_offset`, `disk`) or the swapfile.

Write `/etc/apparmor.d/local/systemd-sleep`:

```
# Allow hibernate to write resume parameters to sysfs
/sys/power/ r,
/sys/power/disk rw,
/sys/power/resume rw,
/sys/power/resume_offset rw,
/sys/power/image_size rw,

# Allow access to swapfile
/var/swap/ r,
/var/swap/swapfile rw,
```

The `setup-hibernate.sh` should:
- Write the above file
- Run `apparmor_parser -r /etc/apparmor.d/systemd-sleep 2>/dev/null || true`
  (graceful — reload the main profile which will pick up the local override)
- Skip writing if file already exists with the same content

---

### 3. `remove-hibernate.sh`

Undo everything `setup-hibernate.sh` did:

1. `swapoff /var/swap/swapfile 2>/dev/null || true`
2. Remove swapfile entry from `/etc/fstab`
3. `btrfs subvolume delete /var/swap` (and `rm -rf /var/swap` fallback)
4. Remove `resume=UUID=...` and `resume_offset=...` tokens from
   `/etc/uki-secureboot/cmdline` using sed (appropriate here — stripping
   tokens from a single-line cmdline file), then call
   `/etc/uki-secureboot/uki-build.sh` to rebuild UKIs
5. Warn user to manually remove `resume` from `/etc/mkinitcpio.conf` HOOKS
   if they added it; run `mkinitcpio -P` after they do
6. Remove `/etc/apparmor.d/local/systemd-sleep`; reload AppArmor profile
7. Remove `/etc/systemd/logind.conf.d/hibernate.conf`
8. Remove `/etc/systemd/sleep.conf.d/hibernate.conf`
9. `systemctl daemon-reload`
10. Print summary of what was removed and what needs a reboot

Use same log helpers and colored output as `setup-hibernate.sh`.

---

### 4. `install.sh`

One-shot deployer (like `uki-secureboot/install.sh`):

- Root check
- Check `btrfs-progs` is installed (via `pacman -Qi btrfs-progs`)
- Copy `setup-hibernate.sh` and `remove-hibernate.sh` to `/etc/zram-hibernate/`
- `chmod 700 /etc/zram-hibernate/*.sh`
- Print: "Run `sudo /etc/zram-hibernate/setup-hibernate.sh` to configure hibernate"
- Accept optional `--setup` flag: if passed, run `setup-hibernate.sh`
  immediately after deploying (opt-in, not default)

---

### 5. `README.md`

Document:
- Prerequisites (existing `uki-secureboot/` setup, BTRFS root, ZRAM active)
- **The exact manual step required before running setup**:
  ```
  # Edit /etc/mkinitcpio.conf — add 'resume' after 'filesystems':
  HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)
  ```
- Full setup steps with commands
- How ZRAM coexists (priority explanation)
- The UKI integration detail (why cmdline is in `/etc/uki-secureboot/cmdline`,
  why both `mkinitcpio -P` and `uki-build.sh` must run)
- AppArmor note (why it's different from SELinux/Bazzite, how local overrides
  work, why we target `local/systemd-sleep` specifically)
- Verification commands:
  ```bash
  cat /sys/power/resume          # major:minor of your resume device
  cat /sys/power/resume_offset   # should match btrfs map-swapfile output
  free -h                        # both ZRAM and swapfile visible
  swapon --show                  # swapfile pri=0, zram pri=100
  systemctl hibernate            # test
  ```
- Troubleshooting:
  - AppArmor denials: `aa-status`, `journalctl -b | grep apparmor`
  - Resume fails: verify `resume` hook is in mkinitcpio HOOKS after `filesystems`
  - Wrong offset: re-run `btrfs inspect-internal map-swapfile -r /var/swap/swapfile`
    and compare with `cat /sys/power/resume_offset`

---

## Important Details

- `set -euo pipefail` on all scripts
- Root check on all scripts
- Colored output (`GREEN`/`YELLOW`/`RED`/`NC`) with `log()`/`warn()`/`die()` helpers
- Do NOT use `sed -i` to edit `/etc/mkinitcpio.conf` or `/etc/systemd/logind.conf`
  or `/etc/systemd/sleep.conf` — use drop-in files and `conf.d` directories
- Do NOT auto-edit `/etc/mkinitcpio.conf` — gate on it and die if `resume` hook
  is missing; the user must add it manually
- cmdline update uses strip-and-replace (not append-only) to handle re-runs
- After cmdline is modified, run `mkinitcpio -P` THEN `uki-build.sh` in that
  order — `mkinitcpio` rebuilds the initramfs; `uki-build.sh` embeds it + the
  new cmdline into the signed UKI
- Do NOT prefix `uki-build.sh` with `sudo` — scripts run as root already
- ZRAM must remain the primary swap (pri=100+); swapfile is hibernate-only (pri=0)
- `HibernateMode=platform` uses ACPI S4 with shutdown as fallback

## Workflow After Setup

```bash
# 1. Install scripts
sudo ./install.sh

# 2. Add 'resume' hook manually to /etc/mkinitcpio.conf (after 'filesystems')

# 3. Run setup (includes mkinitcpio -P and uki-build.sh)
sudo /etc/zram-hibernate/setup-hibernate.sh

# 4. Reboot
systemctl reboot

# 5. Test
systemctl hibernate
```
