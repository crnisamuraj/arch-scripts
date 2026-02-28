# apparmor-setup

Installs and enforces **[apparmor.d](https://github.com/roddhjav/apparmor.d)** — a
comprehensive community AppArmor profile collection — on CachyOS (Arch-based) with
UKI + Secure Boot via the `uki-secureboot/` setup in this repo.

---

## Prerequisites

- **uki-secureboot/** installed and working (`/etc/uki-secureboot/uki-build.sh` present)
- **CachyOS kernel** (`linux-cachyos`) or another kernel that supports `lsm=` stacking
- **AUR helper**: `paru` or `yay` (for `apparmor.d.enforced` / `apparmor.d-git`)
- Run all scripts as root

---

## What is apparmor.d?

[apparmor.d](https://github.com/roddhjav/apparmor.d) is a large collection of AppArmor
profiles covering most common desktop and server applications. On CachyOS it ships as
`apparmor.d.enforced`; on plain Arch the AUR package is `apparmor.d-git`.

---

## Enforce vs Complain mode

| Mode | Behaviour |
|---|---|
| **enforce** | Policy violations are **blocked** and logged |
| **complain** | Policy violations are **logged only** — nothing is blocked |

`setup-apparmor.sh` enforces by default. If you are unsure, use `--complain` on first
run, audit denials for a day or two, then switch to enforce:

```bash
sudo /etc/apparmor-setup/setup-apparmor.sh --complain
# use system, then:
sudo /etc/apparmor-setup/enforce-all.sh
```

---

## Recommended install order (fresh system)

```bash
# 1. UKI + Secure Boot
sudo uki-secureboot/install.sh
sudo /etc/uki-secureboot/generate-mok.sh

# 2. AppArmor (enforce, or --complain for audit-first workflow)
sudo apparmor-setup/install.sh
sudo /etc/apparmor-setup/setup-apparmor.sh        # or: ... --complain

# 3. zram-hibernate (AFTER apparmor — it writes a local override)
sudo zram-hibernate/install.sh
sudo /etc/zram-hibernate/setup-hibernate.sh

# 4. Reboot
reboot
```

---

## Coexistence with zram-hibernate

`zram-hibernate/setup-hibernate.sh` writes a local override to
`/etc/apparmor.d/local/system_systemd-sleep`. Run **apparmor-setup first**, then
zram-hibernate, so the `system_systemd-sleep` profile is already loaded when the
override is applied. `setup-apparmor.sh` reloads local overrides at the end (Step 6),
so any override written before the next re-run will be picked up automatically.

---

## Profile locations

| Path | Purpose |
|---|---|
| `/etc/apparmor.d/` | Main profiles (managed by apparmor.d package) |
| `/etc/apparmor.d/local/` | Your local overrides (preserved across package updates) |
| `/etc/apparmor.d/tunables/` | Tunable variables (home dirs, proc paths, etc.) |

---

## After an apparmor.d package update

Re-enforce all updated profiles:

```bash
sudo /etc/apparmor-setup/enforce-all.sh
```

---

## Handling denials

```bash
# Watch live
journalctl -f | grep DENIED

# Review after reboot
journalctl -b -g 'apparmor.*DENIED'

# Generate suggested allow rules
audit2allow -la

# Add a local override for a specific profile
nano /etc/apparmor.d/local/<profile>
apparmor_parser -r /etc/apparmor.d/<profile>

# Or switch a single profile to complain mode temporarily
aa-complain /etc/apparmor.d/<profile>
```

---

## Verification

```bash
# AppArmor active in kernel?
cat /sys/module/apparmor/parameters/enabled   # expect: Y

# Profile summary
aa-status | head -20
aa-status | grep "profiles in enforce mode"
```

---

## Troubleshooting

### `aa-status` shows 0 profiles after running setup

This is expected if you have not rebooted yet. The kernel parameters (`apparmor=1`,
`lsm=...`) are embedded in the signed UKI and only activate on next boot. After reboot,
`aa-status` should list all loaded profiles.

### Application breaks after reboot

```bash
# Identify the denial
journalctl -b -g 'apparmor.*DENIED'

# Switch that profile to complain mode
aa-complain /etc/apparmor.d/<profile>

# Or add a local override
nano /etc/apparmor.d/local/<profile>
apparmor_parser -r /etc/apparmor.d/<profile>
```

### `security=apparmor` in cmdline

The `security=` parameter was deprecated in kernel 5.1+ in favour of `lsm=`. It is
included by `setup-apparmor.sh` for compatibility with older kernels; on modern kernels
it is a no-op when `apparmor` is already present in the `lsm=` list. You can safely
leave it.

### apparmor.d.enforced vs apparmor.d-git

`apparmor.d.enforced` (CachyOS repo) ships pre-built profiles. `apparmor.d-git` (AUR)
compiles profiles from the upstream git HEAD. After an update to either package, run
`sudo /etc/apparmor-setup/enforce-all.sh` to re-enforce all profiles.

---

## Removal

```bash
sudo /etc/apparmor-setup/remove-apparmor.sh
# then reboot
# optionally: sudo pacman -Rns apparmor apparmor.d.enforced
```
