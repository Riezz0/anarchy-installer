#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$HOME/git/anarchy-repo"
REPO_PKG_DIR="$REPO_DIR/x86_64"
PACKAGE_NAME="anarchy-installer"

cd "$SCRIPT_DIR"

# Auto-increment version tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
IFS='.' read -r MAJOR MINOR PATCH <<< "${LATEST_TAG#v}"
PATCH=$((PATCH + 1))
NEW_TAG="${MAJOR}.${MINOR}.${PATCH}"

echo "==> Version: $LATEST_TAG -> $NEW_TAG"
git tag -f "$NEW_TAG"

echo "==> Building $PACKAGE_NAME..."
makepkg -sf --noconfirm

echo "==> Cleaning up build directories..."
rm -rf "$SCRIPT_DIR/anarchy-installer" "$SCRIPT_DIR/pkg" "$SCRIPT_DIR/src"

PKG_FILE=$(ls -1 "$SCRIPT_DIR"/${PACKAGE_NAME}-*.pkg.tar.zst 2>/dev/null | head -1)
if [[ -z "$PKG_FILE" ]]; then
    echo "ERROR: Package file not found"
    exit 1
fi

echo "==> Removing old package from repo..."
rm -f "$REPO_PKG_DIR"/${PACKAGE_NAME}-*.pkg.tar.zst

echo "==> Moving new package to repo..."
mv "$PKG_FILE" "$REPO_PKG_DIR/"

echo "==> Updating custom repository..."
bash "$REPO_DIR/repo-maker.sh"

echo "==> Done! Tagged as $NEW_TAG"
