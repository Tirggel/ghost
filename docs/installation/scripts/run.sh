#!/bin/bash
# Einfaches Script um alles zu starten:
# 1. Backend-Gateway in Docker (im Hintergrund)
# 2. Flutter App nativ (das gebundelte Binary aus ./dist/)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

# Schritt 1: Gateway starten
echo "🐳 Starting Ghost Gateway in Docker..."
docker-compose up -d ghost-daemon

# Schritt 2: App starten
# Wenn ./dist/app existiert, starte die vorgefertigte Binary
if [ -f "$DIST_DIR/app" ]; then
    echo "🖥️  Starting Flutter App from $DIST_DIR/app ..."
    "$DIST_DIR/app"
else
    echo "ℹ️  No prebuilt app found in ./dist/. Falling back to 'flutter run -d linux'."
    cd "$SCRIPT_DIR/app"
    flutter run -d linux
fi
