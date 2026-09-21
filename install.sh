#!/bin/sh
# Installs Redacción Local from GitHub Releases and clears the quarantine
# flag macOS adds to browser downloads. Unsigned apps cannot skip that
# warning without a paid Developer ID; this is the free alternative.
set -e

DEST="/Applications/LocalRedaction.app"
URL="https://github.com/drax10/local-redaction/releases/latest/download/RedaccionLocal.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Redacción Local…"
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
