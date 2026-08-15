#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARGET_USER=${USER:?USER must be set}
REPO_ROOT="/home/$TARGET_USER/git/anarchy-repo"
PACKAGE_DIR="$REPO_ROOT/x86_64"

if [[ $EUID -eq 0 ]]; then
    printf 'Do not run the package builder as root.\n' >&2
    exit 1
fi

if ! command -v makepkg >/dev/null 2>&1; then
    printf 'makepkg is required to build this package.\n' >&2
    exit 1
fi

if [[ ! -x "$REPO_ROOT/repo-maker.sh" ]]; then
    printf 'Missing executable repo-maker: %s\n' "$REPO_ROOT/repo-maker.sh" >&2
    exit 1
fi

mkdir -p "$PACKAGE_DIR"

cd "$SCRIPT_DIR"
rm -f ./*.pkg.tar.*
makepkg --cleanbuild --clean --force

published=0
for package in ./*.pkg.tar.*; do
    [[ -f "$package" ]] || continue
    mv -- "$package" "$PACKAGE_DIR/"
    published=1
done

if (( published == 0 )); then
    printf 'makepkg did not produce a package artifact.\n' >&2
    exit 1
fi

cd "$REPO_ROOT"
bash "$REPO_ROOT/repo-maker.sh"
