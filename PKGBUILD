pkgname=anarchy-installer
pkgver=20261106.040709319900876
pkgrel=1
pkgdesc="Anarchy Arch Linux installer"
arch=('any')
license=('GPL-3.0-or-later')
options=('!debug')
depends=('bash' 'gum' 'figlet' 'python' 'python-gobject' 'gtk4' 'libadwaita')
source=('Anarchy-Launcher' 'Anarchy-Installer' 'Anarchy-Installer-Offline' 'Anarchy-Installer-Offline-GUI' 'Anarchy-Installer-Offline.desktop' 'Anarchy-Installer-Offline.bak')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

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
    install -Dm755 "$srcdir/Anarchy-Installer-Offline-GUI" \
        "$pkgdir/usr/local/bin/Anarchy-Installer-Offline-GUI"
    install -Dm644 "$srcdir/Anarchy-Installer-Offline.desktop" \
        "$pkgdir/usr/share/applications/Anarchy-Installer-Offline.desktop"
    install -Dm755 "$srcdir/Anarchy-Installer-Offline.bak" \
        "$pkgdir/usr/local/bin/Anarchy-Installer-Offline.bak"
}
