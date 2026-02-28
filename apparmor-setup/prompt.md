  ---
  # AppArmor + apparmor.d (Enforced) Setup for CachyOS — Claude Code Prompt

  ## Context

  I run **CachyOS Linux** with **systemd-boot** and UKI + Secure Boot (via the
  `uki-secureboot/` setup in this repo). The kernel cmdline lives in
  `/etc/uki-secureboot/cmdline` and is embedded into signed UKIs by
  `uki-build.sh`. I also have `zram-hibernate/` which enables hibernate to swapfile with zram enabled. it will expect apparmor to be already setup (with scripts in `apparmor/`).

  I want to install and enforce **[apparmor.d](https://github.com/roddhjav/apparmor.d)** (on cachyos packages cahyos-extra/apparmor and cachyos/apparmor.d.enforced, may differ for arch)
  — the community comprehensive AppArmor profile collection — in **enforce mode**,
  on top of the base `apparmor` package.

  ## My System

  - **Distro**: CachyOS (Arch-based), AUR available (`paru` or `yay`)
  - **Kernel**: `linux-cachyos` (supports LSM stacking)
  - **UKI cmdline file**: `/etc/uki-secureboot/cmdline`
  - **Initramfs tool**: `mkinitcpio`
  - **AppArmor local overrides**: `/etc/apparmor.d/local/` (used by zram-hibernate)
  - **Packages needed**:
    - cachyOS: `apparmor` (cachyos-extra(-zenver4)), `apparmor.d.enforced` (cachyos)
    - arch: `apparmor` (base), `apparmor.d-git` (AUR)

  ## What I Need

  Create the following files in a new `apparmor-setup/` directory in this repo,
  to be installed to `/etc/apparmor-setup/`:

  ---

  ### 1. `setup-apparmor.sh`

  Main installer. Must run as root (`set -euo pipefail`, colored output).

  Steps in order:

  #### Step 1 — Install packages

  ```bash
  pacman -S --needed --noconfirm apparmor audit

  Then check if apparmor.d-git is installed:
  pacman -Qi apparmor.d.enforced &>/dev/null|| pacman -Qi apparmor.d-git &>/dev/null
  If not installed, detect AUR helper (paru or yay, whichever is in PATH)
  and install apparmor.d.enforced || apparmor.d-git with it. If neither is available, print a RED
  warning with instructions to install manually:
  paru -S apparmor.d.enforced || paru -S apparmor.d-git
  # or: yay -S apparmor.d-git
  and exit 1.

  Step 2 — Enable kernel parameters (UKI-aware)

  The file /etc/uki-secureboot/cmdline must contain these parameters.
  For each parameter, append it only if not already present:

  - apparmor=1
  - security=apparmor
  - lsm=landlock,lockdown,yama,integrity,apparmor,bpf

  Important: the lsm= parameter is a comma-separated list. Do not
  blindly append a second lsm= line. Instead:
  - Check if any lsm= entry exists
  - If it does, check if apparmor is already in the list; if not, append
  ,apparmor to the existing value (in-place)
  - If no lsm= entry exists, append the full line

  After modifying cmdline, call:
  /etc/uki-secureboot/uki-build.sh
  to rebuild and re-sign all UKIs with the new cmdline.

  Step 3 — Enable and start AppArmor service

  systemctl enable --now apparmor.service
  

  Step 4 — Enforce all loaded profiles

  aa-enforce /etc/apparmor.d/*
  Ignore errors for directories and non-profile files (use 2>/dev/null || true).

  Then reload all profiles:
  systemctl reload apparmor.service || apparmor_parser -r /etc/apparmor.d/

  Step 5 — Enable audit logging

  AppArmor denials are logged via the audit subsystem. Enable the audit daemon:
  systemctl enable --now auditd.service

  Write /etc/audit/rules.d/apparmor.rules:
  -w /etc/apparmor/ -p wa -k apparmor
  -w /etc/apparmor.d/ -p wa -k apparmor
  Then augenrules --load 2>/dev/null || true.

  Step 6 — Preserve local overrides

  If /etc/apparmor.d/local/ contains any existing files (e.g. from
  zram-hibernate), reload those profiles explicitly to ensure they are active:
  for f in /etc/apparmor.d/local/*; do
      profile=$(basename "$f")
      apparmor_parser -r "/etc/apparmor.d/${profile}" 2>/dev/null || true
  done

  Step 7 — Print next-steps summary (colored)

  AppArmor + apparmor.d setup complete.

  REBOOT REQUIRED: The new kernel parameters (apparmor=1 security=apparmor
  lsm=...) are embedded in the UKI and will only take effect after reboot.

  After reboot, verify with:
    aa-status                          # show loaded + enforced profiles
    cat /sys/module/apparmor/parameters/enabled   # should print Y
    journalctl -b | grep apparmor      # check for denials
    audit2allow -la                    # suggest allow rules for any denials

  If an application breaks, check for denials:
    journalctl -b -g 'apparmor.*DENIED'
    # Then either:
    aa-complain /etc/apparmor.d/<profile>   # switch to complain mode
    # or add a local override in /etc/apparmor.d/local/<profile>

  ---
  2. remove-apparmor.sh

  Undo everything:

  1. Set all profiles to complain mode:
  aa-complain /etc/apparmor.d/* 2>/dev/null || true
  2. Stop and disable services:
  systemctl disable --now apparmor.service
  3. Remove kernel parameters from /etc/uki-secureboot/cmdline:
    - Remove apparmor=1
    - Remove security=apparmor
    - For lsm=: remove only ,apparmor or apparmor, from the list;
  if apparmor was the only LSM, remove the entire lsm= parameter
    - Rebuild UKI: /etc/uki-secureboot/uki-build.sh
  4. Remove /etc/audit/rules.d/apparmor.rules; run augenrules --load 2>/dev/null || true
  5. Print: "Reboot to complete removal."

  Do NOT uninstall apparmor or apparmor.d-git packages — that is left to
  the user.

  ---
  3. enforce-all.sh

  Utility to (re-)enforce all profiles after an apparmor.d package update:

  #!/bin/bash
  set -euo pipefail
  [[ $EUID -ne 0 ]] && { echo "Must run as root"; exit 1; }
  aa-enforce /etc/apparmor.d/* 2>/dev/null || true
  systemctl reload apparmor.service || apparmor_parser -r /etc/apparmor.d/
  echo "All profiles enforced."

  ---
  4. install.sh

  One-shot deployer:
  - mkdir -p /etc/apparmor-setup
  - Copy setup-apparmor.sh, remove-apparmor.sh, enforce-all.sh to
  /etc/apparmor-setup/
  - chmod 700 /etc/apparmor-setup/*.sh
  - Print: "Run sudo /etc/apparmor-setup/setup-apparmor.sh to configure AppArmor"

  ---
  5. README.md

  Document:

  - Prerequisites: existing uki-secureboot/ setup; CachyOS kernel
  (which supports lsm= stacking); AUR helper (paru or yay)
  - What apparmor.d is: link to https://github.com/roddhjav/apparmor.d
  - Why enforced mode: distinction between enforced (blocks) vs complain
  (logs only) — start with the audit step below before enforcing if unsure
  - Coexistence with zram-hibernate: the system_systemd-sleep local
  override written by zram-hibernate/setup-hibernate.sh is preserved;
  run zram-hibernate/setup-hibernate.sh AFTER apparmor-setup/setup-apparmor.sh
  so the profile is loaded when the override is applied
  - Recommended order for fresh installs:
  sudo uki-secureboot/install.sh && sudo /etc/uki-secureboot/generate-mok.sh
  sudo apparmor-setup/install.sh && sudo /etc/apparmor-setup/setup-apparmor.sh
  sudo zram-hibernate/install.sh && sudo /etc/zram-hibernate/setup-hibernate.sh
  # reboot
  - Handling denials:
  # Watch live
  journalctl -f | grep DENIED
  # Generate allow rule suggestions
  audit2allow -la
  # Add to local override
  nano /etc/apparmor.d/local/<profile>
  apparmor_parser -r /etc/apparmor.d/<profile>
  - Profile locations:
    - Main profiles: /etc/apparmor.d/
    - Local overrides (your customizations): /etc/apparmor.d/local/
    - Tunable variables: /etc/apparmor.d/tunables/
  - After apparmor.d-git updates: run sudo /etc/apparmor-setup/enforce-all.sh
  to re-enforce all updated profiles
  - Verification:
  cat /sys/module/apparmor/parameters/enabled   # Y
  aa-status | head -20
  aa-status | grep "profiles in enforce mode"

  ---
  Important Details

  - set -euo pipefail and root check on all scripts
  - Colored output (GREEN/YELLOW/RED/NC)
  - The lsm= parameter handling must be surgical — do not duplicate or
  break the existing LSM list; CachyOS ships with some LSMs pre-configured
  - UKI rebuild (uki-build.sh) must be called after any cmdline change —
  the parameters are embedded into the signed EFI image
  - The aa-enforce /etc/apparmor.d/* glob will hit directories and
  non-profile files; suppress those errors gracefully
  - apparmor.d-git installs profiles that may immediately break applications
  if enforced without auditing first — the README should strongly recommend
  running in complain mode first for new installs:
  aa-complain /etc/apparmor.d/*
  # use system for a day, check journalctl for DENIED
  sudo /etc/apparmor-setup/enforce-all.sh
  - The setup-apparmor.sh script should enforce by default (as requested)
  but print a YELLOW advisory about this

  Workflow After Setup

  sudo ./install.sh
  sudo /etc/apparmor-setup/setup-apparmor.sh
  # reboot (for kernel parameters to take effect)
  aa-status
  journalctl -b | grep 'apparmor.*DENIED'

  ---
