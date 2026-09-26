pkgname=anarchy-installer
pkgver=20260926.171258616511992
pkgrel=1
pkgdesc="Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet' 'python' 'python-gobject' 'libadwaita')
source=('Anarchy-Launcher' 'Anarchy-Installer')
sha256sums=('SKIP' 'SKIP')

pkgver() {
    date -u +%Y%m%d.%H%M%S%N
}

package() {
    install -Dm755 "$srcdir/Anarchy-Launcher" \
        "$pkgdir/usr/local/bin/Anarchy-Launcher"
    install -Dm755 "$srcdir/Anarchy-Installer" \
        "$pkgdir/usr/local/bin/Anarchy-Installer"
}
