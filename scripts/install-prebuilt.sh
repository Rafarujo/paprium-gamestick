#!/bin/bash
# Instala o core JA' COMPILADO (dist/*.so) no cartao, sem precisar de toolchain.
# Faz backup do core antigo, confere o que foi copiado e testa os requisitos
# (ROM, pasta de MP3).
#
# Uso:
#   bash scripts/install-prebuilt.sh                 # detecta o cartao sozinho
#   bash scripts/install-prebuilt.sh genesisplusgx_libretro.so   # forca o nome
#   CARD=/media/$USER/EEFF-FCD8 TARGET=nome.so bash scripts/install-prebuilt.sh
set -u
BASE=${BASE:-$HOME/Downloads}; export BASE
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
REL=$BASE/install-prebuilt.txt
exec > >(tee "$REL") 2>&1

echo "== install-prebuilt $(date)"
echo "repositorio: $REPO"

# --- core de origem
CORE=${CORE:-$REPO/dist/genesis_plus_gx_paprium_libretro.so}
if [ ! -f "$CORE" ]; then
    CORE=$(ls -t "$REPO"/dist/*.so 2>/dev/null | head -1)
fi
if [ -z "$CORE" ] || [ ! -f "$CORE" ]; then
    echo "ERRO: nenhum .so em $REPO/dist"
    echo "      baixe da release: https://github.com/rafarujo/paprium-gamestick/releases"
    echo "      ou compile com: bash scripts/core-final.sh"
    exit 1
fi
echo "core: $CORE ($(stat -c%s "$CORE") bytes, md5 $(md5sum "$CORE" | cut -d' ' -f1))"

if [ "$(od -An -tx1 -N4 "$CORE" 2>/dev/null | tr -d ' \n')" != "7f454c46" ]; then
    echo "ERRO: $CORE nao e' um ELF (arquivo corrompido ou LFS sem baixar)"
    exit 1
fi

# --- cartao
if [ -z "${CARD:-}" ]; then
    CARD=$(dirname "$(find /media/$USER -maxdepth 3 -type d -name retro_lib 2>/dev/null | head -1)")
fi
if [ -z "${CARD:-}" ] || [ "$CARD" = "." ] || [ ! -d "$CARD/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    echo "      monte o cartao ou passe CARD=/media/\$USER/<rotulo>"
    exit 1
fi
echo "cartao: $CARD"

# --- nome de destino
if [ -n "${1:-}" ]; then
    TARGET=$1
elif [ -n "${TARGET:-}" ]; then
    TARGET=$TARGET
elif grep -aq "genesis_plus_gx_paprium_libretro" "$CARD/ui/ui.log" "$CARD/ui/"*.txt 2>/dev/null; then
    TARGET=genesis_plus_gx_paprium_libretro.so
    echo "launcher deste cartao conhece o core do Paprium (excecao por ROM)"
else
    TARGET=genesisplusgx_libretro.so
    echo "launcher sem excecao para Paprium: usando o nome padrao de MD"
fi
echo "destino: retro_lib/$TARGET"

# --- backup
if [ -f "$CARD/retro_lib/$TARGET" ] && [ ! -f "$CARD/retro_lib/$TARGET.orig" ]; then
    cp -p "$CARD/retro_lib/$TARGET" "$CARD/retro_lib/$TARGET.orig" || exit 1
    echo "backup: retro_lib/$TARGET.orig ($(stat -c%s "$CARD/retro_lib/$TARGET.orig") bytes)"
elif [ -f "$CARD/retro_lib/$TARGET.orig" ]; then
    echo "backup: retro_lib/$TARGET.orig ja' existe (mantido)"
else
    echo "backup: nao havia core com esse nome no cartao"
fi

# --- copia
cp "$CORE" "$CARD/retro_lib/$TARGET" || exit 1
chmod +x "$CARD/retro_lib/$TARGET"
sync 2>/dev/null || true

A=$(md5sum "$CORE" | cut -d' ' -f1)
B=$(md5sum "$CARD/retro_lib/$TARGET" | cut -d' ' -f1)
echo "copiado: $(stat -c%s "$CARD/retro_lib/$TARGET") bytes"
if [ "$A" != "$B" ]; then
    echo "ERRO: md5 diferente apos a copia ($A != $B)"
    echo "      cartao cheio, corrompido ou com problema de escrita"
    exit 1
fi
echo "md5 confere: $B"

# --- requisitos do jogo
echo
echo "== requisitos do jogo"
ROM=$CARD/game/md/paprium.bin
if [ -f "$ROM" ]; then
    printf "   ROM: %s bytes  md5 %s\n" "$(stat -c%s "$ROM")" "$(md5sum "$ROM" | cut -d' ' -f1)"
    [ "$(stat -c%s "$ROM")" = "8388608" ] || echo "      AVISO: esperado 8388608 bytes"
    [ "$(md5sum "$ROM" | cut -d' ' -f1)" = "91ccdc0b20af85a16bfe0b1a698c19d0" ] || \
        echo "      AVISO: md5 diferente do dump bom (veja scripts/fix-card.sh)"
else
    echo "   ROM: FALTANDO em game/md/paprium.bin (8 388 608 bytes)"
fi
if [ -d "$CARD/game/md/paprium" ]; then
    N=$(find "$CARD/game/md/paprium" -maxdepth 1 -type f -name '*.mp3' 2>/dev/null | wc -l)
    echo "   MP3: $N de 52 na pasta game/md/paprium/"
    [ "$N" -ge 52 ] || echo "      AVISO: faltando faixa - o jogo roda, mas sem musica"
else
    echo "   MP3: pasta game/md/paprium/ ausente - o jogo roda mudo"
fi

echo
echo "== pronto"
echo "   desmonte o cartao (ou 'sync') e ligue o console; o Paprium deve abrir."
echo "   para voltar ao core original:"
echo "     cp retro_lib/$TARGET.orig retro_lib/$TARGET"
