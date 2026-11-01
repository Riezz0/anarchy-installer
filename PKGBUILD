pkgname=anarchy-installer
pkgver=20261101.181649918785324
pkgrel=1
pkgdesc="Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet' 'python' 'python-gobject' 'libadwaita')
source=('Anarchy-Launcher' 'Anarchy-Installer' 'Anarchy-Installer-Offline')
sha256sums=('SKIP' 'SKIP' 'SKIP')

pkgver() {
    date -u +%Y%m%d.%H%M%S%N
}

package() {
    install -Dm755 "$srcdir/Anarchy-Launcher" \
        "$pkgdir/usr/local/bin/Anarchy-Launcher"
    install -Dm755 "$srcdir/Anarchy-Installer" \
        "$pkgdir/usr/local/bin/Anarchy-Installer"
    install -Dm755 "$srcdir/Anarchy-Installer-Offline" \
        "$pkgdir/usr/local/bin/Anarchy-Installer-Offline"
}
