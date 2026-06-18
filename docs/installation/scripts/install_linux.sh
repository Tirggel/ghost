#!/usr/bin/env bash
set -eu

# ObjectBox Linux Installation Script
# https://github.com/objectbox/objectbox-c/releases

cLibVersion=5.3.2
cLibArgs="$*"

echo "Installing ObjectBox native library for Linux (v${cLibVersion})..."
bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-c/main/download.sh) ${cLibArgs} ${cLibVersion}
