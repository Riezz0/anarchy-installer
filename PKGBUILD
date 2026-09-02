pkgname=anarchy-installer
pkgver=20260902.064631423819933
pkgrel=1
pkgdesc="Tokyo Night Gum-based Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet' 'python' 'python-gobject' 'libadwaita')
source=('anarchy-installer.sh' 'anarchy-launcher.sh')
sha256sums=('SKIP' 'SKIP')

pkgver() {
    date -u +%Y%m%d.%H%M%S%N
}

package() {
    install -Dm755 "$srcdir/anarchy-installer.sh" \
        "$pkgdir/usr/local/bin/anarchy-installer"
    install -Dm755 "$srcdir/anarchy-launcher.sh" \
        "$pkgdir/usr/local/bin/anarchy-launcher"
}
