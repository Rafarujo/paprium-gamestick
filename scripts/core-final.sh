#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Gera o core FINAL do Paprium (sem traces, sem ring) e instala no cartao.
#
# Diferenca para o core de depuracao:
#   - PAPRIUM_TRACE=0 / PAPRIUM_TRACE_1FEA=0  -> nao escreve nenhum "PDBG"
#   - sem o gancho de ring PC+SP no laco do 68k -> mais rapido
#
# Uso:  bash scripts/core-final.sh     (cartao montado)
set -u
REL=$BASE/core-final-report.txt
HERE=$(cd "$(dirname "$0")" && pwd)
exec > >(tee "$REL") 2>&1

echo "== core-final $(date)"

U=$(dirname "$(find /media/$USER -maxdepth 3 -type d -name retro_lib 2>/dev/null | head -1)")
if [ -z "$U" ] || [ "$U" = "." ] || [ ! -d "$U/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    exit 1
fi
echo "cartao: $U"
echo

echo "== 1) ROM no cartao (tem que ser 91ccdc0b20af85a16bfe0b1a698c19d0)"
MROM=$(md5sum "$U/game/md/paprium.bin" | cut -d' ' -f1)
echo "   $MROM"
if [ "$MROM" != "91ccdc0b20af85a16bfe0b1a698c19d0" ]; then
    echo "   ATENCAO: ROM diferente da boa! Rode corrige-cartao.sh antes."
fi

echo
echo "== 2) guardando o core atual como .debug.so (para nao perder)"
CUR=$U/retro_lib/genesis_plus_gx_paprium_libretro.so
if [ -f "$CUR" ]; then
    cp -f "$CUR" "${CUR%.so}.debug.so" && \
        echo "   $(md5sum "${CUR%.so}.debug.so" | cut -d' ' -f1)  ->  $(basename "${CUR%.so}.debug.so")"
fi

echo
echo "== 3) build final (TRACE=0)"
TRACE=0 bash "$HERE/build-core.sh" "$HERE/../core/cart_hw/paprium.h" || {
    echo "ERRO: build final falhou"; exit 1; }

echo
echo "== 4) instalando no cartao"
bash "$HERE/install-core.sh"

echo
echo "== resumo"
echo "   core no PC   : $(md5sum "$BASE/gamestick-ui/build/genesis_plus_gx_paprium_libretro.so" | cut -d' ' -f1)"
echo "   core de debug: ${CUR%.so}.debug.so (fica no cartao, nao e' usado)"
echo "   ROM          : $MROM"
echo
echo "Proximo passo: cartao no console, abra o Paprium e jogue."
echo "Se precisar depurar de novo: bash scripts/build-install.sh (regera o core com traces)."
