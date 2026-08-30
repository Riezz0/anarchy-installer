pkgname=anarchy-installer
pkgver=20260816.065101203935289
pkgrel=1
pkgdesc="Tokyo Night Gum-based Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet' 'python' 'python-gobject' 'libadwaita')
source=('anarchy-installer.sh' 'anarchy-launcher.sh' 'anarchy-welcome/anarchy-welcome.py')
sha256sums=('SKIP' 'SKIP' 'SKIP')

pkgver() {
    date -u +%Y%m%d.%H%M%S%N
}

package() {
    install -Dm755 "$srcdir/anarchy-installer.sh" \
        "$pkgdir/usr/local/bin/anarchy-installer"
    install -Dm755 "$srcdir/anarchy-launcher.sh" \
        "$pkgdir/usr/local/bin/anarchy-launcher"
    install -Dm755 "$srcdir/anarchy-welcome/anarchy-welcome.py" \
        "$pkgdir/usr/local/bin/anarchy-welcome"
}
