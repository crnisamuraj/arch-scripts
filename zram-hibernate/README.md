# zram-hibernate

Hibernate-to-swapfile on BTRFS with ZRAM coexistence, for CachyOS (Arch-based)
with systemd-boot + UKI + Secure Boot.

## Prerequisites

- [`uki-secureboot/`](../uki-secureboot/) set up and working (UKIs built, MOK enrolled)
- BTRFS root filesystem
- ZRAM swap active (via `zram-generator`)
- `btrfs-progs` installed (or let `install.sh` install it)

## How it works

| Swap device | Priority | Used for |
|-------------|----------|----------|
| ZRAM | 100 (high) | All normal memory pressure |
| `/var/swap/swapfile` | 0 (low) | Hibernate target only |

ZRAM stays primary. The swapfile sits idle at priority 0 — the kernel only
writes to it during `systemctl hibernate`.

## Required manual step (before setup)

**You must add the `resume` hook to `/etc/mkinitcpio.conf` before running setup.**
The script gates on this and will not proceed without it.

Edit `/etc/mkinitcpio.conf` and add `resume` **after** `filesystems`:

```
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)
```

The hook must come after `filesystems` so the swap device is available when
the kernel tries to resume.

## Setup

```bash
# 1. Install scripts
sudo ./install.sh

# 2. Add 'resume' hook to /etc/mkinitcpio.conf (see above — manual step)

# 3. Run setup
#    This will: create swapfile, update /etc/fstab, update UKI cmdline,
#    run mkinitcpio -P, rebuild UKIs, write AppArmor override, configure systemd.
sudo /etc/zram-hibernate/setup-hibernate.sh

# 4. Reboot
systemctl reboot

# 5. Test
systemctl hibernate
```

Or combine steps 1 and 3 (still requires the mkinitcpio.conf step first):

```bash
sudo ./install.sh --setup
```

## UKI integration

This setup modifies `/etc/uki-secureboot/cmdline` to append:

```
resume=UUID=<filesystem-uuid> resume_offset=<btrfs-file-offset>
```

After modifying the cmdline, `setup-hibernate.sh` runs:
1. `mkinitcpio -P` — rebuilds the initramfs with the `resume` hook
2. `/etc/uki-secureboot/uki-build.sh` — embeds the new initramfs **and** the
   updated cmdline into signed UKIs on the ESP

Both steps are required. The pacman hook (`99-uki-build.hook`) only fires on
package updates, not on a manual `mkinitcpio -P` run.

The `resume_offset` is a physical block offset computed by:
```bash
btrfs inspect-internal map-swapfile -r /var/swap/swapfile
```
This differs from the logical file offset — using the wrong value silently
breaks resume.

## AppArmor note

Bazzite (Fedora) uses SELinux. CachyOS uses AppArmor — the approach is different.

The AppArmor profile for systemd-sleep is at `/etc/apparmor.d/systemd-sleep`.
It already contains `include if exists <local/systemd-sleep>`, so writing to
`/etc/apparmor.d/local/systemd-sleep` is sufficient — no patching of the main
profile required.

The local override grants:
- `/sys/power/{disk,resume,resume_offset,image_size}` — hibernate sysfs nodes
- `/var/swap/swapfile` — the hibernate target

## Verification

Run these after rebooting:

```bash
# Resume device (major:minor of your BTRFS filesystem partition)
cat /sys/power/resume

# Resume offset (should match btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
cat /sys/power/resume_offset

# Both ZRAM and swapfile should appear; swapfile pri=0, zram pri=100
swapon --show

# Memory overview
free -h

# Full hibernate test
systemctl hibernate
```

## Removal

```bash
sudo /etc/zram-hibernate/remove-hibernate.sh
```

Then manually:
1. Remove `resume` from HOOKS in `/etc/mkinitcpio.conf`
2. `sudo mkinitcpio -P`
3. `sudo /etc/uki-secureboot/uki-build.sh`
4. Reboot

## Troubleshooting

**Resume fails / system reboots instead of resuming:**
- Verify `resume` hook is in HOOKS and comes after `filesystems`
- Verify the UKI cmdline has the correct UUID and offset:
  ```bash
  # Check what the running kernel sees
  cat /proc/cmdline | grep -o 'resume[^ ]*'
  # Compare offset
  cat /sys/power/resume_offset
  btrfs inspect-internal map-swapfile -r /var/swap/swapfile
  ```
- If values differ, re-run `setup-hibernate.sh` (it will strip-and-replace)

**AppArmor denials:**
```bash
# Check active profiles
aa-status | grep systemd-sleep
# Check recent denials
journalctl -b | grep -i 'apparmor.*DENIED'
# Reload profile manually if needed
sudo apparmor_parser -r /etc/apparmor.d/systemd-sleep
```

**Swapfile not showing in `swapon --show`:**
```bash
# Activate manually and check for errors
sudo swapon /var/swap/swapfile
# Verify fstab entry
grep swap /etc/fstab
```

**`btrfs inspect-internal map-swapfile` fails:**
- The swapfile must be active (`swapon`) before running this command
- Verify with `swapon --show`
