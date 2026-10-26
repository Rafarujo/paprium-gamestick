#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Repara o Paprium no cartao do Game Stick.
#
# Descoberta: 32 KB da ROM (offset 0x38000-0x3FFFF) foram sobrescritos pelo
# proprio log do RetroArch (ui/ra.log). Ou seja, o log e a ROM compartilham um
# bloco no cartao (cross-link do FAT) e a gravacao do log estragou a ROM.
#
# O que este script faz:
#   1. zera ui/ra.log          (libera o bloco compartilhado)
#   2. apaga game/md/paprium.bin corrompido
#   3. copia a ROM boa e confere o md5
#
# Uso:  bash scripts/fix-card.sh
set -u
REL=$BASE/corrige-cartao-report.txt
exec > >(tee "$REL") 2>&1

echo "== corrige-cartao $(date)"

GOOD=$BASE/Paprium/PAPRIUM/paprium.bin
GOODMD5=91ccdc0b20af85a16bfe0b1a698c19d0
[ -f "$GOOD" ] || { echo "ERRO: falta $GOOD"; exit 1; }
M0=$(md5sum "$GOOD" | cut -d' ' -f1)
[ "$M0" = "$GOODMD5" ] || { echo "ERRO: ROM fonte com md5 $M0 (esperado $GOODMD5)"; exit 1; }
echo "ROM fonte OK: $M0"

U=$(dirname "$(find /media/$USER -maxdepth 3 -type d -name retro_lib 2>/dev/null | head -1)")
if [ -z "$U" ] || [ "$U" = "." ] || [ ! -d "$U/retro_lib" ]; then
    echo "ERRO: cartao nao encontrado em /media/$USER/*/retro_lib"
    exit 1
fi
ROM=$U/game/md/paprium.bin
LOG=$U/ui/ra.log
echo "cartao: $U"
echo

echo "== antes"
if [ -f "$ROM" ]; then
    echo "   ROM: $(stat -c%s "$ROM") bytes  md5 $(md5sum "$ROM" | cut -d' ' -f1)"
    echo "   assinatura do log na ROM: $(dd if="$ROM" bs=1 skip=229376 count=20 status=none | tr -c '[:print:]' '.')"
else
    echo "   ROM nao existe"
fi
[ -f "$LOG" ] && echo "   log: $(stat -c%s "$LOG") bytes"
df -h "$U" | tail -1 | awk '{print "   livre no cartao: "$4" de "$2}'
echo

echo "== 1) zerando ui/ra.log"
if [ -f "$LOG" ]; then
    : > "$LOG" && echo "   ui/ra.log -> 0 bytes"
else
    echo "   ui/ra.log nao existe (ok)"
fi

echo
echo "== 2) apagando a ROM corrompida"
rm -f "$ROM" "$ROM.md5"
sync
if [ -e "$ROM" ]; then
    echo "ERRO: nao consegui apagar $ROM (cartao montado como somente leitura?)"
    exit 1
fi
echo "   apagada"

echo
echo "== 3) copiando a ROM boa"
if ! cp -f "$GOOD" "$ROM"; then
    echo "ERRO: cp falhou (sem espaco? df acima)"
    exit 1
fi
sync
echo "   copiada"

echo
echo "== 4) conferindo"
M=$(md5sum "$ROM" | cut -d' ' -f1)
if [ "$M" = "$GOODMD5" ]; then
    echo "   OK: $M"
    echo "$M  paprium.bin" > "$ROM.md5"
else
    echo "   FALHOU: md5 $M (esperado $GOODMD5)"
    echo "   -> cartao com defeito; copie de novo ou troque o cartao"
    exit 1
fi
ls -l "$ROM" | sed 's/^/   /'
df -h "$U" | tail -1 | awk '{print "   livre no cartao: "$4" de "$2}'

echo
echo "== 5) sistema de arquivos (leitura, sem alterar nada)"
FS=$(findmnt -no FSTYPE "$U" 2>/dev/null)
DEV=$(findmnt -no SOURCE "$U" 2>/dev/null)
echo "   $DEV  ($FS)"
CHK=""
command -v dosfsck  >/dev/null 2>&1 && CHK=dosfsck
[ -z "$CHK" ] && command -v fsck.vfat >/dev/null 2>&1 && CHK=fsck.vfat
if [ -n "$CHK" ]; then
    echo "   rodando $CHK -n (pode avisar que esta montado; e' so leitura):"
    $CHK -n "$DEV" 2>&1 | grep -aiE "cross|share|truncat|cluster|fragment|error|differ|free" | head -12 | sed 's/^/      /'
    echo "   (nada acima = FAT sem problema estrutural)"
else
    echo "   dosfsck/fsck.vfat nao instalado -- pule esta checagem"
fi

echo
echo "== resumo"
echo "   ROM no cartao  : $M"
echo "   core instalado : $(md5sum "$U/retro_lib/genesis_plus_gx_paprium_libretro.so" 2>/dev/null | cut -d' ' -f1)"
echo "   log            : $(stat -c%s "$LOG" 2>/dev/null) bytes"
echo
echo "Proximo passo: ligue o stick, abra o Paprium, deixe ~40 s e rode"
echo "   cat /media/<seu-usuario>/<rotulo-do-cartao>/ui/ra.log"
