#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Instala no cartao o core recem-compilado (faz .bak e zera o ra.log).
# Uso:  bash scripts/install-core.sh
REL=$BASE/inst-report.txt
SRC=$BASE/gamestick-ui/build/genesis_plus_gx_paprium_libretro.so
exec > >(tee "$REL") 2>&1

echo "== inst-core $(date)"

U=$(dirname "$(find /media/$USER -maxdepth 2 -type d -name retro_lib 2>/dev/null | head -1)" 2>/dev/null)
if [ -z "$U" ] || [ "$U" = "." ] || [ ! -d "$U/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    echo "Monte o cartao e rode de novo."
    exit 1
fi
echo "cartao: $U"

[ -f "$SRC" ] || { echo "ERRO: nao existe $SRC"; exit 1; }
echo "origem: $(md5sum "$SRC")"

DEST=$U/retro_lib/genesis_plus_gx_paprium_libretro.so
if [ ! -f "$DEST.bak" ]; then
    cp -f "$DEST" "$DEST.bak" && echo "backup: $DEST.bak"
fi

cp -f "$SRC" "$DEST" || { echo "ERRO: cp falhou"; exit 1; }
chmod 755 "$DEST"
sync

# guarda o log do teste anterior e zera para o proximo boot
LOG=$U/ui/ra.log
if [ -f "$LOG" ] && [ -s "$LOG" ]; then
    cp -f "$LOG" "$BASE/ra-previous.log" 2>/dev/null && \
        echo "log anterior salvo: $BASE/ra-previous.log ($(wc -c < "$LOG") bytes)"
    : > "$LOG" && echo "log zerado: $LOG"
elif [ -f "$LOG" ]; then
    echo "log ja estava vazio: $LOG"
fi

echo "== verificacao no cartao"
md5sum "$DEST"
ls -l "$DEST"
echo "strings de trace encontradas: $(strings -n 6 "$DEST" | grep -cE 'R1FEA|R1FE4|R1FE6|W1FEA|audio tick=|mp3: loop') (0 = core final limpo)"
sync

echo "== desmontando"
for m in $(findmnt -rno TARGET | grep "^/media/$USER/"); do
    dev=$(findmnt -no SOURCE --target "$m")
    udisksctl unmount -b "$dev" >/dev/null 2>&1 && echo "desmontado: $m" || echo "NAO desmontei: $m"
done
sync
echo "== fim"
