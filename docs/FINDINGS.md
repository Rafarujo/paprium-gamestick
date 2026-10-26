# Diagnóstico — Paprium travando no Game Stick

Registro do caminho até a causa. O resumo: **o core estava certo o tempo todo; a
ROM no cartão tinha 32 KB sobrescritos pelo log do RetroArch.**

## 1. Sintoma

- PC (RetroArch x64, mesmo core compilado): o jogo roda.
- Game Stick (RK3032, ARMv7, glibc 2.29): trava depois do logo — tela azul /
  loop, ou não sai do "Loading".
- O mesmo cartão, mesmo core, mesmo jogo: resultados diferentes em plataformas
  diferentes.

## 2. Não-determinismo (confirmado e corrigido)

Duas fontes de aleatoriedade no core, ambas atingindo o boot do Paprium:

1. `core/genesis.c` — a cada frame:
   `m68k.cycles = (MCYCLES_PER_LINE*lines) * ((double)rand() / (double)RAND_MAX)`.
   Ou seja, o *timing* do 68k era sorteado por frame. Trocado por `0.5`.
2. `core/cart_hw/paprium.h` — o mapper respondia a leituras em `0x1880–0x1AFF`
   com `rand()` semeado por um endereço de pilha (`srand(&ptr)`). Virou um LFSR
   de semente fixa (`0x5A17`).

Com os dois fixes, duas execuções do mesmo binário no PC ficaram idênticas até
~comando 1441 / tick 528 (diferença de 1 scanline), contra divergência imediata
antes.

## 3. Instrumentação (traces)

O mapper é um cartucho esperto: o 68k escreve comandos em `0x1FEA` e lê status em
`0x1FE4/0x1FE6/0x1FEA`. O `paprium.h` ganhou traces compiláveis
(`PAPRIUM_TRACE`):

- `R1FEA / W1FEA / CMD xx begin|end` — protocolo 68k ↔ mapper
- `RING BADPC / SPZERO / SILENCE` — as últimas 2048 instruções (PC + SP) quando
  o 68k salta para fora da ROM, quando o A7 desaba para menos de `0x10000`, ou
  quando o jogo para de conversar com o mapper
- `audio tick=…` — batimento de 16 em 16 ticks

No aparelho: 3386 comandos, depois `JSR (A4)` com A4 inválido → `pc=0x79FFFD`
(ímpar) → address error → loop de exceção. O ring mostrou execução de **zeros**
em `0x03E03A–0x040012`.

No PC, com a mesma ROM: os traces eram idênticos até o comando **369**; no 370 o
PC emitia `D1` e o aparelho repetia `AF`/`AE` para sempre.

## 4. A pista errada que valeu a pena descartar

O Paprium tem um quirk conhecido de primeiro boot (grava save e precisa resetar).
Checamos: `/game/md/paprium.srm` tinha **0 bytes** — não havia save no aparelho.
Testes no PC sem save / com save bom / com save de lixo não reproduziam o
travamento. Descartado.

## 5. A causa

`card-check.sh` mostrou que a ROM do cartão e a do PC tinham md5 diferentes:

```
PC     : 91ccdc0b20af85a16bfe0b1a698c19d0
cartão : c3bcd860e8704266e0a4922e959f79a2     (mesmos 8 388 608 bytes)
```

Rodando no PC (x64) a ROM **copiada do cartão**, ela travava também
(`cmd 3221`, `ipc=010106`, pilha zerada). Não era ARM, não era o mapper.

`cmp -l` das duas ROMs: **32 587 bytes diferentes, todos entre `0x38000` e
`0x3FFFF`** — exatamente 32 KB, o começo do `ui/ra.log`:

```
$ xxd -s 0x38000 -l 64 card-paprium.bin
00038000: 4361 7061 6369 6461 6465 733a 204e 454f  Capacidades: NEO
00038010: 4e20 5646 5076 3320 5646 5076 3420 0a42  N VFPv3 VFPv4 .B
00038020: 7569 6c74 3a20 4d61 7220 2037 2032 3032  uilt: Mar  7  202
```

E os primeiros 32 KB do `ra-raw.log` eram **byte a byte idênticos** a esse
bloco. O log e a ROM dividiam um bloco no sistema de arquivos do cartão (exFAT):
cada vez que o frontend gravava o log, ele reescrevia 32 KB da ROM — justamente
a região que o jogo executa mais tarde.

Detalhe importante: só esse bloco diferia. O resto dos 8 MB era idêntico à dump
boa, ou seja, o cartão tinha a ROM correta e ela **foi corrompida depois**.

## 6. Correção

`fix-card.sh`: zera o `ui/ra.log` (libera o bloco compartilhado), apaga a ROM,
recopia a boa e confere o md5. Depois disso o jogo passou a rodar no console.

Prevenção: o core final é compilado com `TRACE=0` — sem `PDBG`, o core não
escreve nada em stderr, e não há mais gravação em cima do bloco compartilhado.

## 7. Lições

1. **Antes de comparar plataformas, confira a ROM.** Um `md5sum` de 5 segundos
   teria economizado dias. Mesmo tamanho não significa mesmo dump.
2. **`cmp -l` primeiro, teoria depois.** Saber que só havia 32 KB diferentes
   teria apontado direto para "arquivo corrompido", não "revisão do jogo".
3. **Rode a ROM suspeita na plataforma que funciona.** Se travar lá também, o
   problema não é a plataforma.
4. **Log de debug em cartão de brinquedo é arma carregada.** Qualquer frontend
   que grava log no mesmo volume pode, com um sistema de arquivos inconsistente,
   escrever em cima de outro arquivo.
5. Determinismo primeiro: sem `rand()` no caminho do emulador, trace serve para
   comparar máquina x máquina.

## 8. Como o jogo abre no stick

O frontend do aparelho é um launcher próprio (MiniGUI + `/lib/retroarch`), não
o menu do RetroArch. O `/ui/ui.log` mostra a cadeia:

```
catalogo: 44 jogos, 8 sistemas
run: id=5 cfg=/usr/local/share/minigui/gbx66.cfg rom=/sdcard/game/md/paprium.bin
+ GAME_LIB=genesisplusgx_libretro.so          # padrao para todo MD
+ basename /sdcard/game/md/paprium.bin
+ GAME_LIB=genesis_plus_gx_paprium_libretro.so  # excecao por nome de ROM
+ /usr/bin/retroarch -v -y 12 -c /usr/local/share/minigui/gbx66.cfg
      -L /sdcard/retro_lib/genesis_plus_gx_paprium_libretro.so
      /sdcard/game/md/paprium.bin
```

Ou seja: o `.so` de Paprium é escolhido por uma exceção no launcher (nome da
ROM). Num aparelho de fábrica essa exceção não existe e o MD sempre cai em
`retro_lib/genesisplusgx_libretro.so` — por isso a instalação recomendada lá é
substituir esse arquivo (com backup) pelo nosso core.
