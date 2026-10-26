#!/bin/bash
BASE=${BASE:-$HOME/Downloads}; export BASE
# Compila o Genesis Plus GX (fork BillyTimeGames) com Paprium em streaming
# + trace do registrador 0x1FEA.
#
# Uso:
#   bash scripts/build-core.sh [arquivo-paprium.h]
#
# Requisitos: arm-linux-gnueabihf-gcc e um sysroot glibc <= 2.29
#   (SYSROOT=/caminho/do/sysroot, padrao /tmp/opencode/sysroot)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NEW_H=${1:-$HERE/../core/cart_hw/paprium.h}

WORK=${WORK:-/tmp/opencode/gpgx}
SYSROOT=${SYSROOT:-/tmp/opencode/sysroot}
X64=${X64:-0}
TRACE=${TRACE:-1}
if [ "$X64" = "1" ]; then
    OUT=${OUT:-$HERE/pc-build/genesis_plus_gx_paprium_libretro.so}
else
    OUT=${OUT:-$BASE/gamestick-ui/build/genesis_plus_gx_paprium_libretro.so}
fi
REPO=https://github.com/BillyTimeGames/Genesis-Plus-GX-Expanded-Rom-Size
LOG=/tmp/paprium-build.log

echo "== paprium.h de origem: $NEW_H"
[ -f "$NEW_H" ] || { echo "ERRO: $NEW_H nao existe"; exit 1; }
md5sum "$NEW_H" | awk '{print "   md5: "$1}'
grep -c "R1FEA" "$NEW_H" | awk '{print "   linhas com R1FEA: "$1}'
grep -c "PAPRIUM_TRACE_1FEA" "$NEW_H" | awk '{print "   linhas com PAPRIUM_TRACE_1FEA: "$1}'

if [ "$X64" != "1" ]; then
    command -v arm-linux-gnueabihf-gcc >/dev/null || { echo "ERRO: falta o cross gcc"; exit 1; }
    [ -d "$SYSROOT/usr/include/arm-linux-gnueabihf" ] || { echo "ERRO: falta o sysroot em $SYSROOT"; exit 1; }
fi
[ -d "$WORK" ] || git clone --depth 1 "$REPO" "$WORK"

cd "$WORK"
cp -f "$NEW_H" core/cart_hw/paprium.h
echo "== copiado para $WORK/core/cart_hw/paprium.h"
md5sum core/cart_hw/paprium.h | awk '{print "   md5 na arvore: "$1}'

# --- build limpo (TRACE=0): volta os arquivos do core ao original -----------
# A arvore em /tmp/opencode/gpgx e' reaproveitada entre builds, entao os
# patches (ring do m68k) ficariam para tras. Revertemos e reaplicamos so' o
# que o jogo precisa (jitter do genesis.c abaixo).
if [ "$TRACE" != "1" ]; then
    echo "== TRACE=0: revertendo m68kcpu.c/genesis.c ao original"
    git checkout -- core/m68k/m68kcpu.c core/genesis.c 2>/dev/null || \
        { echo "ERRO: git checkout falhou em $WORK"; exit 1; }
    ! grep -q "PATCH-PAPRIUM" core/m68k/m68kcpu.c || {
        echo "ERRO: ainda ha patch no m68kcpu.c"; exit 1; }
fi

# --- patch do genesis.c: tirar o jitter de ciclos por frame ------------------
# genesis.c faz m68k.cycles = (MCYCLES_PER_LINE*lines) * (rand()/RAND_MAX).
# Isso injeta aleatoriedade no TIMING do 68k a cada frame: duas execucoes do
# mesmo binario divergem e o boot do Paprium toma caminhos diferentes.
# Trocamos a fracao aleatoria por 0.5 (fixo).
GENESIS=core/genesis.c
[ -f "$GENESIS" ] || { echo "ERRO: $GENESIS nao existe"; exit 1; }
if ! grep -q "PATCH-PAPRIUM-NOJITTER" "$GENESIS"; then
    NJ=$(grep -c "((double)rand() / (double)RAND_MAX)" "$GENESIS" || true)
    [ "$NJ" = "1" ] || { echo "ERRO: jitter de m68k.cycles aparece $NJ vezes em $GENESIS"; exit 1; }
    sed -i 's|((double)rand() / (double)RAND_MAX)|0.5 /* PATCH-PAPRIUM-NOJITTER */|' "$GENESIS"
fi
[ "$(grep -c -F "PATCH-PAPRIUM-NOJITTER" "$GENESIS" || true)" = "1" ] || {
    echo "ERRO: patch do jitter nao entrou em $GENESIS"; exit 1; }
echo "   genesis.c: jitter do m68k.cycles fixado em 0.5"
grep -n "PATCH-PAPRIUM-NOJITTER" "$GENESIS" | cut -c1-110 | sed 's/^/      /'

# --- patch do m68kcpu.c: guardar o PC da instrucao em execucao ---------
# O prev_pc do core so' e' preenchido com DEBUG_TRACE, que vem desligado.
# Sem isso, todo trace de 0x1FEA sai com pc=000000.
M68KCPU=core/m68k/m68kcpu.c
[ -f "$M68KCPU" ] || { echo "ERRO: $M68KCPU nao existe"; exit 1; }
if ! grep -q "pap_last_pc" "$M68KCPU"; then
    N1=$(grep -c "^m68ki_cpu_core m68k;" "$M68KCPU" || true)
    N2=$(grep -c "/\* Decode next instruction \*/" "$M68KCPU" || true)
    [ "$N1" = "1" ] || { echo "ERRO: anchor 'm68ki_cpu_core m68k;' aparece $N1 vezes em $M68KCPU"; exit 1; }
    [ "$N2" = "1" ] || { echo "ERRO: anchor 'Decode next instruction' aparece $N2 vezes em $M68KCPU"; exit 1; }
    cp -f "$M68KCPU" "$M68KCPU.orig-paprium" 2>/dev/null || true

    # insere sem depender de fim de linha (o arquivo do repo usa CRLF)
    sed -i 's|m68ki_cpu_core m68k;|m68ki_cpu_core m68k;\nunsigned int pap_last_pc; /* PATCH-PAPRIUM */|' "$M68KCPU"
    sed -i 's|/\* Decode next instruction \*/|/* Decode next instruction */\n    pap_last_pc = m68k.pc; /* PATCH-PAPRIUM */|' "$M68KCPU"
fi
grep -q "pap_last_pc;" "$M68KCPU" || { echo "ERRO: nao defini pap_last_pc em $M68KCPU"; exit 1; }
grep -q "pap_last_pc = m68k.pc;" "$M68KCPU" || { echo "ERRO: nao achei o laco do m68k para setar pap_last_pc"; exit 1; }

if [ "$TRACE" = "1" ]; then
# --- v9: ring de PC+SP (2048) + histograma + snapshot no 1o PC invalido e
# no instante em que o SP (A7) cai para < 0x10000 --------------------------
# O PC do m68k chega aqui com lixo no byte alto (0xFF79FFFD), por isso a
# mascara de 24 bits: sem ela a comparacao de faixa nunca dispara.
N3=$(grep -c "pap_last_pc = m68k.pc;" "$M68KCPU" || true)
[ "$N3" = "1" ] || { echo "ERRO: 'pap_last_pc = m68k.pc;' aparece $N3 vezes em $M68KCPU"; exit 1; }

# remove a instrumentacao das versoes anteriores (v5..v8)
sed -i '/PATCH-PAPRIUM-RING-BEGIN/,/PATCH-PAPRIUM-RING-END/d' "$M68KCPU"
sed -i '/PATCH-PAPRIUM-RING/d' "$M68KCPU"

BLK=$(mktemp)
cat > "$BLK" <<'CEOF'
/* PATCH-PAPRIUM-RING-BEGIN */
#define PAP_RING_LEN 2048
#define PAP_RING_MASK 2047
unsigned int pap_ring_pc[PAP_RING_LEN]; unsigned int pap_ring_sp[PAP_RING_LEN]; unsigned int pap_ring_i;
unsigned int pap_hist[256];
unsigned int pap_snap_pc[PAP_RING_LEN]; unsigned int pap_snap_sp[PAP_RING_LEN];
unsigned int pap_snap_n; unsigned int pap_snap_i; unsigned int pap_snap_bad; unsigned int pap_bad_hits;
unsigned int pap_snap_regs[16]; unsigned int pap_snap_sr; unsigned int pap_snap_ipl;
unsigned int pap_snap_stop; unsigned int pap_snap_pcval;
unsigned int pap_sp_pc[PAP_RING_LEN]; unsigned int pap_sp_sp[PAP_RING_LEN];
unsigned int pap_sp_n; unsigned int pap_sp_i; unsigned int pap_sp_pcval; unsigned int pap_sp_hits; unsigned int pap_sp_low;
unsigned int pap_sp_regs[16]; unsigned int pap_sp_sr; unsigned int pap_sp_ipl; unsigned int pap_sp_stop;

static void pap_ring_copy(unsigned int *dp, unsigned int *ds, unsigned int *pn,
                          unsigned int *pidx, unsigned int *rg, unsigned int *psr,
                          unsigned int *pipl, unsigned int *pst, unsigned int *ppc)
{
	unsigned int i;

	for (i = 0; i < PAP_RING_LEN; i++) { dp[i] = pap_ring_pc[i]; ds[i] = pap_ring_sp[i]; }

	*pn = (pap_ring_i < PAP_RING_LEN) ? pap_ring_i : PAP_RING_LEN;
	*pidx = pap_ring_i;

	for (i = 0; i < 16; i++) rg[i] = m68k.dar[i];
	*psr = m68k.s_flag; *pipl = m68k.int_mask; *pst = m68k.stopped; *ppc = m68k.pc;
}

static void pap_ring_bad(unsigned int pc)
{
	pap_bad_hits++;
	if (pap_snap_n) return;
	pap_ring_copy(pap_snap_pc, pap_snap_sp, &pap_snap_n, &pap_snap_i, pap_snap_regs,
	              &pap_snap_sr, &pap_snap_ipl, &pap_snap_stop, &pap_snap_pcval);
	pap_snap_bad = pc ? pc : 1;
}

static void pap_ring_lowsp(void)
{
	pap_sp_hits++;
	if (pap_sp_n) return;
	pap_ring_copy(pap_sp_pc, pap_sp_sp, &pap_sp_n, &pap_sp_i, pap_sp_regs,
	              &pap_sp_sr, &pap_sp_ipl, &pap_sp_stop, &pap_sp_pcval);
}
/* PATCH-PAPRIUM-RING-END */
CEOF
sed -i "/m68ki_cpu_core m68k;/r $BLK" "$M68KCPU"
rm -f "$BLK"

BLKP=$(mktemp)
cat > "$BLKP" <<'CEOF'
    /* PATCH-PAPRIUM-RING-BEGIN */
    { unsigned int _p = m68k.pc; unsigned int _m = _p & 0xffffff;
      pap_ring_pc[pap_ring_i & PAP_RING_MASK] = _p;
      pap_ring_sp[pap_ring_i & PAP_RING_MASK] = m68k.dar[15];
      pap_ring_i++;
      pap_hist[(_m >> 8) & 255]++;
      if (m68k.dar[15] >= 0x10000) pap_sp_low = 1;
      else if (pap_sp_low) pap_ring_lowsp();
      if (_m >= 0x400000 && _m < 0xFE0000) pap_ring_bad(_p); }
    /* PATCH-PAPRIUM-RING-END */
CEOF
sed -i "/pap_last_pc = m68k.pc;/r $BLKP" "$M68KCPU"
rm -f "$BLKP"

[ "$(grep -c -F 'PAP_RING_LEN' "$M68KCPU" || true)" -ge 1 ] || { echo "ERRO: declaracoes do v9 nao entraram em $M68KCPU"; exit 1; }
[ "$(grep -c -F 'pap_ring_sp[' "$M68KCPU" || true)" -ge 2 ] || { echo "ERRO: ring de SP nao entrou em $M68KCPU"; exit 1; }
[ "$(grep -c -F 'pap_ring_lowsp();' "$M68KCPU" || true)" -ge 1 ] || { echo "ERRO: gancho do SP nao entrou em $M68KCPU"; exit 1; }
[ "$(grep -c -F 'pap_ring_bad(_p);' "$M68KCPU" || true)" -ge 1 ] || { echo "ERRO: ring de PCs nao entrou em $M68KCPU"; exit 1; }

echo "== patch do m68k:"
grep -n "pap_last_pc\|pap_ring" "$M68KCPU" | cut -c1-100 | sed 's/^/   /'
else
    echo "== TRACE=0: sem ring no m68k (gancho por instrucao desligado)"
fi

if [ "$X64" = "1" ]; then
    CC=${CC:-cc}
    PDEF="-O2"
else
    GI=$(arm-linux-gnueabihf-gcc -print-file-name=include)
    CC="arm-linux-gnueabihf-gcc --sysroot=$SYSROOT -nostdinc \
        -isystem $SYSROOT/usr/include -isystem $SYSROOT/usr/include/arm-linux-gnueabihf \
        -isystem $GI -isystem /usr/arm-linux-gnueabihf/include \
        -L$SYSROOT/usr/lib/arm-linux-gnueabihf"
    PDEF="-DARM -marm -march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
fi

if [ "$TRACE" != "1" ]; then
    PDEF="$PDEF -DPAPRIUM_TRACE=0 -DPAPRIUM_TRACE_1FEA=0"
    echo "== build final: PAPRIUM_TRACE=0 (sem PDBG, sem ring)"
fi
make -f Makefile.libretro clean >/dev/null 2>&1 || echo "AVISO: make clean falhou"rm -f genesis_plus_gx_libretro.so

echo "== compilando (log em $LOG)"
if ! make -f Makefile.libretro platform=unix \
     CC="$CC" \
     HAVE_CDROM=0 HAVE_CHD=0 LTO= \
     PLATFORM_DEFINES="$PDEF" \
     -j"$(nproc)" > "$LOG" 2>&1; then
    echo "ERRO: make falhou"
    grep -E "error:|Error [0-9]|cannot find|No such file" "$LOG" | head -30
    exit 1
fi
grep -E "warning:.*paprium|paprium\.[ch]:[0-9]+:[0-9]+: (error|warning)" "$LOG" | head -20 || true

[ -f genesis_plus_gx_libretro.so ] || { echo "ERRO: core nao gerado"; exit 1; }

if [ "$X64" != "1" ]; then
    MAXV=$(arm-linux-gnueabihf-objdump -T genesis_plus_gx_libretro.so \
           | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1 || true)
    echo "== GLIBC maxima exigida: ${MAXV:-?} (aparelho: 2.29)"
    [ -z "${MAXV:-}" ] || [ "$(printf '%s\n' "$MAXV" "GLIBC_2.29" | sort -V | tail -1)" = "GLIBC_2.29" ] || {
        echo "ERRO: o core pede $MAXV, o aparelho so' tem 2.29"; exit 1; }
fi

echo "== strings de trace no binario:"
for s in "R1FEA" "R1FE4" "R1FE6" "W1FEA" "CMD %02X begin" "mp3: %d Hz" "audio tick=" "RING %s n="; do
    printf "   %-16s %s\n" "$s" "$(strings -n 4 genesis_plus_gx_libretro.so | grep -c -F "$s" || true)"
done

NM=arm-linux-gnueabihf-nm
if [ "$X64" = "1" ]; then NM=nm; fi
if command -v "$NM" >/dev/null 2>&1; then
    SYM=$("$NM" genesis_plus_gx_libretro.so | grep -w "pap_last_pc" || true)
else
    SYM=$(strings -n 4 genesis_plus_gx_libretro.so | grep -x "pap_last_pc" || true)
fi
if [ -z "$SYM" ]; then
    echo "ERRO: simbolo pap_last_pc nao esta no binario (patch do m68kcpu.c nao entrou)"
    exit 1
fi
echo "   pap_last_pc       OK ($SYM)"

if [ "$TRACE" = "1" ]; then
    if command -v "$NM" >/dev/null 2>&1; then
        RSYM=$("$NM" genesis_plus_gx_libretro.so | grep -w "pap_ring_pc" || true)
    else
        RSYM=$(strings -n 4 genesis_plus_gx_libretro.so | grep -x "pap_ring_pc" || true)
    fi
    [ -n "$RSYM" ] || { echo "ERRO: simbolo pap_ring_pc nao esta no binario"; exit 1; }
    RN=$(strings -n 4 genesis_plus_gx_libretro.so | grep -c -F "RING %s n=" || true)
    [ "${RN:-0}" -gt 0 ] || { echo "ERRO: string do ring dump nao esta no binario"; exit 1; }
    echo "   pap_ring_pc       OK"
else
    TL=$(strings -n 4 genesis_plus_gx_libretro.so \
         | grep -c -E "^(R1FEA|R1FE4|R1FE6|W1FEA|RING %s n=|CMD %02X begin|RAMDUMP |audio tick=)" || true)
    if [ "${TL:-0}" != "0" ]; then
        echo "ERRO: build limpo ainda tem $TL formatos de trace no binario"
        exit 1
    fi
    ISYM=$(strings -n 4 genesis_plus_gx_libretro.so | grep -x "pap_ring_pc" || true)
    [ -z "$ISYM" ] || { echo "ERRO: ring ainda presente no binario"; exit 1; }
    echo "   sem traces        OK"
fi

mkdir -p "$(dirname "$OUT")"
cp -f genesis_plus_gx_libretro.so "$OUT"
chmod 755 "$OUT"
ls -l "$OUT"
md5sum "$OUT"
echo "OK: $OUT"
