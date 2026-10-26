#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Compila o core para o aparelho (ARM) e instala no cartao.
# Uso:  bash scripts/build-install.sh
#
# Deixe o cartao montado antes de rodar (ele e' desmontado no fim).
set -u
REL=$BASE/arm-instala-report.txt
HERE=$(cd "$(dirname "$0")" && pwd)
exec > >(tee "$REL") 2>&1

echo "== arm-instala $(date)"

echo
echo "########## 1/2 build ARM ##########"
bash "$HERE/build-core.sh" "$HERE/../core/cart_hw/paprium.h" || {
    echo "ERRO: build ARM falhou (veja o log acima)"; exit 1; }

echo
echo "########## 2/2 instalando no cartao ##########"
bash "$HERE/install-core.sh"

echo
echo "== pronto. Agora:"
echo "   1) tire o cartao, ponha no console e ligue"
echo "   2) entre no Paprium e deixe ~40 s"
echo "   3) volte o cartao no PC e rode: cat /media/<seu-usuario>/<rotulo-do-cartao>/ui/ra.log"
