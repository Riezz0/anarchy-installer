# Maintainer: Riezz0 <https://github.com/Riezz0>
pkgname=anarchy-installer
pkgver=0.0.97
pkgrel=1
pkgdesc="Offline Arch Linux + Hyprland (UWSM) + SDDM installer with local pacman repo"
arch=('any')
url="https://github.com/Riezz0/anarchy-installer"
license=('GPL-3.0-or-later')
depends=('bash' 'gum' 'python' 'python-gobject' 'gtk4' 'libadwaita' 'vte4' 'sudo')
source=("$pkgname::git+$url.git")
sha256sums=('SKIP')

pkgver() {
    cd "$srcdir/$pkgname"
    local ver
    ver=$(git describe --tags --abbrev=7 2>/dev/null | sed 's/^v//;s/-/./g')
    if [[ -n "$ver" ]]; then
        echo "$ver"
    else
        echo "0.$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
    fi
}

package() {
    install -Dm755 "$srcdir/$pkgname/anarchy-installer.sh" \
        "$pkgdir/usr/local/bin/anarchy-installer.sh"
    install -Dm755 "$srcdir/$pkgname/anarchy-gui.py" \
        "$pkgdir/usr/local/bin/anarchy-gui"
    install -Dm644 "$srcdir/$pkgname/anarchy-gui.desktop" \
        "$pkgdir/usr/share/applications/anarchy-gui.desktop"
}
