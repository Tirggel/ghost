#!/usr/bin/env bash
set -eu

# ObjectBox macOS Installation Script
# https://github.com/objectbox/objectbox-c/releases

cLibVersion=5.1.0
cLibArgs="$*"

echo "Installing ObjectBox native library for macOS (v${cLibVersion})..."
bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-c/main/download.sh) ${cLibArgs} ${cLibVersion}
