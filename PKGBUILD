pkgname=anarchy-installer
pkgver=1.0.0
pkgrel=1
pkgdesc="Tokyo Night Gum-based Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet')
source=('anarchy-installer.sh')
sha256sums=('SKIP')

package() {
    install -Dm755 "$srcdir/anarchy-installer.sh" \
        "$pkgdir/usr/local/bin/anarchy-installer"
}
