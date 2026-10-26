#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Copia (ou atualiza) as 52 musicas do Paprium no cartao.
#
#   origem : $BASE/Paprium/PAPRIUM/paprium/   (446 MB)
#   destino: <cartao>/game/md/paprium/
#
# Compara md5 arquivo por arquivo, copia so' o que falta ou difere e confere
# de novo no fim. Nao apaga arquivo que so' existe no cartao (so' avisa).
#
# Uso:  bash scripts/copy-music.sh   (cartao montado)
set -u
REL=$BASE/musicas-cartao-report.txt
exec > >(tee "$REL") 2>&1

echo "== musicas-cartao $(date)"

SRC=$BASE/Paprium/PAPRIUM/paprium
[ -d "$SRC" ] || { echo "ERRO: falta a pasta $SRC"; exit 1; }

U=$(dirname "$(find /media/$USER -maxdepth 3 -type d -name retro_lib 2>/dev/null | head -1)")
if [ -z "$U" ] || [ "$U" = "." ] || [ ! -d "$U/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    exit 1
fi
DST=$U/game/md/paprium
echo "cartao : $U"
echo "origem : $SRC ($(ls "$SRC" | wc -l) arquivos, $(du -sh "$SRC" | cut -f1))"
echo "destino: $DST ($(ls "$DST" 2>/dev/null | wc -l) arquivos, $(du -sh "$DST" 2>/dev/null | cut -f1))"
df -h "$U" | tail -1 | awk '{print "livre no cartao: "$4" de "$2}'
echo

mkdir -p "$DST" || { echo "ERRO: nao consegui criar $DST (somente leitura?)"; exit 1; }

N_OK=0; N_CP=0; N_ERR=0; N_EXTRA=0
LISTA_CP=""

echo "== comparando ($(ls "$SRC" | wc -l) arquivos)"
while IFS= read -r -d '' f; do
    n=$(basename "$f")
    m1=$(md5sum "$f" | cut -d' ' -f1)
    if [ -f "$DST/$n" ]; then
        m2=$(md5sum "$DST/$n" | cut -d' ' -f1)
        if [ "$m1" = "$m2" ]; then
            N_OK=$((N_OK+1))
            continue
        fi
        echo "   difere : $n"
    else
        echo "   falta  : $n"
    fi
    if cp -f "$f" "$DST/$n"; then
        N_CP=$((N_CP+1))
        LISTA_CP="$LISTA_CP$n
"
    else
        N_ERR=$((N_ERR+1))
        echo "            ^ ERRO ao copiar"
    fi
done < <(find "$SRC" -maxdepth 1 -type f -print0 | sort -z)

echo
echo "== arquivos no cartao que nao existem na origem"
while IFS= read -r -d '' f; do
    n=$(basename "$f")
    [ -f "$SRC/$n" ] && continue
    echo "   so' no cartao: $n"
    N_EXTRA=$((N_EXTRA+1))
done < <(find "$DST" -maxdepth 1 -type f -print0)
[ "$N_EXTRA" = "0" ] && echo "   nenhum"

sync

echo
echo "== conferindo o que foi copiado"
FALHA=0
if [ -n "$LISTA_CP" ]; then
    printf '%s' "$LISTA_CP" | while IFS= read -r n; do
        [ -z "$n" ] && continue
        m1=$(md5sum "$SRC/$n" | cut -d' ' -f1)
        m2=$(md5sum "$DST/$n" | cut -d' ' -f1)
        if [ "$m1" = "$m2" ]; then
            echo "   ok     : $n"
        else
            echo "   FALHOU : $n  ($m1 != $m2)"
        fi
    done
else
    echo "   (nada precisou ser copiado)"
fi

echo
echo "== resumo"
echo "   ja' corretos : $N_OK"
echo "   copiados     : $N_CP"
echo "   erros        : $N_ERR"
echo "   so' no cartao: $N_EXTRA"
echo "   total na origem: $(ls "$SRC" | wc -l)   no cartao: $(ls "$DST" | wc -l)"
df -h "$U" | tail -1 | awk '{print "   livre agora: "$4" de "$2}'
