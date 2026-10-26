#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Compila o NOSSO core para x86_64 (para testar no RetroArch do PC).
# Uso:  bash scripts/build-x64.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REL=$BASE/build-x64-report.txt
exec > >(tee "$REL") 2>&1

echo "== build x64 $(date)"
X64=1 OUT="$BASE/pc-build/genesis_plus_gx_paprium_libretro.so" \
    bash "$HERE/build-core.sh" "$HERE/../core/cart_hw/paprium.h"
