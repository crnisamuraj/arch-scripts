# Maintainer: Milos Ivancevic
pkgname=cachyos-scripts-git
_realname=cachyos-scripts
pkgver=r0.0
pkgrel=1
pkgdesc="Modular setup scripts for CachyOS: UKI Secure Boot, BTRFS snapshot rollback, ZRAM hibernate, AppArmor"
arch=('any')
url="https://github.com/crnisamuraj/cachyos-scripts"
license=('MIT')
depends=('bash')
makedepends=('git')
optdepends=(
    'sbctl: Secure Boot key management and UKI signing (uki-secureboot, snapper-boot)'
    'systemd-ukify: UKI assembly (uki-secureboot, snapper-boot)'
    'systemd-boot-manager: automatic systemd-boot updates on systemd upgrades (CachyOS)'
    'snapper: BTRFS snapshot management (snapper-boot)'
    'snap-pac: automatic snapper snapshots on pacman operations (snapper-boot)'
    'btrfs-progs: BTRFS filesystem utilities (snapper-boot, zram-hibernate)'
    'apparmor: mandatory access control (apparmor-setup)'
    'audit: AppArmor audit logging (apparmor-setup)'
)
install="${_realname}.install"
source=("${_realname}::git+https://github.com/crnisamuraj/cachyos-scripts.git")
sha256sums=('SKIP')

pkgver() {
    cd "${_realname}"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
    cd "${_realname}"

    local dest="${pkgdir}/usr/share/${_realname}"
    install -dm755 "${dest}"

    # Root orchestrator scripts
    for f in install.sh remove.sh setup.sh reconfigure.sh; do
        [[ -f "${f}" ]] || continue
        install -Dm755 "${f}" "${dest}/${f}"
    done

    # Module directories (everything that's a directory and not hidden)
    for d in */; do
        d="${d%/}"
        [[ "${d}" == .* ]] && continue
        cp -r "${d}" "${dest}/"
        find "${dest}/${d}" -name "*.sh" -exec chmod 755 {} +
    done
}
