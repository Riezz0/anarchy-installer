pkgname=anarchy-installer
pkgver=20260815.122418810577920
pkgrel=1
pkgdesc="Tokyo Night Gum-based Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet')
source=('anarchy-installer.sh')
sha256sums=('SKIP')

pkgver() {
    date -u +%Y%m%d.%H%M%S%N
}

package() {
    install -Dm755 "$srcdir/anarchy-installer.sh" \
        "$pkgdir/usr/local/bin/anarchy-installer"
}
