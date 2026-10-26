#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Confere o que esta' no cartao: ROM do Paprium (md5), pasta de mp3 e saves.
# Nao altera nada. Uso:  bash scripts/card-check.sh   (com o cartao montado)
set -u
REL=$BASE/confere-rom-report.txt
exec > >(tee "$REL") 2>&1

echo "== confere-rom $(date)"

U=$(dirname "$(find /media/$USER -maxdepth 2 -type d -name retro_lib 2>/dev/null | head -1)" 2>/dev/null)
if [ -z "$U" ] || [ "$U" = "." ] || [ ! -d "$U/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    echo "Monte o cartao e rode de novo."
    exit 1
fi
echo "cartao: $U"
echo

echo "== ROMs encontradas (*.bin *.md *.gen *.smd)"
find "$U" -maxdepth 5 -type f \( -iname '*.bin' -o -iname '*.md' -o -iname '*.gen' -o -iname '*.smd' \) -size +1M 2>/dev/null | while read -r f; do
    printf "%10s  %s\n         md5 %s\n" "$(stat -c%s "$f")" "${f#$U}" "$(md5sum "$f" | cut -d' ' -f1)"
done
echo "   (esperado do PC: 8388608 bytes, md5 91ccdc0b20af85a16bfe0b1a698c19d0)"
echo

echo "== pasta de mp3 do Paprium"
find "$U" -maxdepth 6 -type d -iname paprium 2>/dev/null | while read -r d; do
    echo "   $d -> $(ls "$d" 2>/dev/null | wc -l) arquivos, $(du -sh "$d" 2>/dev/null | cut -f1)"
done
echo

echo "== saves / SRAM"
find "$U" -maxdepth 6 -type f \( -iname '*.srm' -o -iname '*.sav' -o -iname '*.nv' \) 2>/dev/null | while read -r f; do
    printf "   %s (%s bytes, %s)\n" "${f#$U}" "$(stat -c%s "$f")" "$(date -r "$f" '+%d/%m %H:%M')"
done
echo

echo "== core instalado"
ls -l "$U/retro_lib/" 2>/dev/null | sed 's/^/   /'
md5sum "$U/retro_lib/genesis_plus_gx_paprium_libretro.so" 2>/dev/null | sed 's/^/   /'
echo

echo "== config do RetroArch (proxy/save/video) "
CFG=$(find "$U" -maxdepth 3 -name 'retroarch.cfg' 2>/dev/null | head -1)
if [ -n "$CFG" ]; then
    echo "   $CFG"
    grep -aE "savefile_directory|savestate_directory|video_driver|audio_driver|rewind|run_ahead|sram" "$CFG" | sed 's/^/     /'
else
    echo "   retroarch.cfg nao encontrado"
fi
