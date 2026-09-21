#!/bin/sh
# Installs Redacción Local from GitHub Releases and clears the quarantine
# flag macOS adds to browser downloads. Unsigned apps cannot skip that
# warning without a paid Developer ID; this is the free alternative.
set -e

REPO="drax10/local-redaction"
DEST="/Applications/LocalRedaction.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# /releases/latest/download often serves a cached previous zip. Resolve the
# current tag, then fetch that versioned asset URL instead.
TAG_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
TAG="${TAG_URL##*/}"
if [ -z "$TAG" ] || [ "$TAG" = "latest" ]; then
  echo "Could not determine the latest release." >&2
  exit 1
fi
URL="https://github.com/${REPO}/releases/download/${TAG}/RedaccionLocal.zip"

echo "Downloading Redacción Local ${TAG}…"
curl -fL "$URL" -o "$TMP/RedaccionLocal.zip"

echo "Installing to ${DEST}…"
ditto -xk "$TMP/RedaccionLocal.zip" "$TMP/unpacked"
APP="$(find "$TMP/unpacked" -name '*.app' -print | head -n 1)"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "The download did not contain LocalRedaction.app." >&2
  exit 1
fi

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Installed. Opening…"
open "$DEST"
