# Paprium no Game Stick Lite 4K (RK3032) — Genesis Plus GX

Correções no suporte ao cartucho **Paprium** (mapper com streaming de MP3 e
decodificador de vídeo) do fork
[Genesis-Plus-GX-Expanded-Rom-Size](https://github.com/BillyTimeGames/Genesis-Plus-GX-Expanded-Rom-Size),
mais os scripts de build e de diagnóstico usados para fazer o jogo rodar em um
Game Stick chinês com **Rockchip RK3032** (ARMv7, glibc 2.29).

Estado atual: **o jogo roda no console** — boot, música e jogo normal.

## Instalação rápida (sem compilar)

Para quem só quer jogar, não precisa de toolchain: use o core pronto de
[`dist/`](dist/LEIAME.md) ou das [releases](https://github.com/rafarujo/paprium-gamestick/releases).

```bash
git clone https://github.com/rafarujo/paprium-gamestick && cd paprium-gamestick
bash scripts/install-prebuilt.sh            # cartão montado
```

O script encontra o cartão, escolhe o nome de `.so` que o launcher daquele
aparelho usa, guarda o core antigo como `.orig`, confere o md5 da cópia e avisa
se faltar a ROM ou a pasta de MP3. Depois é só desmontar e ligar o console.

Se o cartão não for detectado (ou tiver mais de um), informe na mão:

```bash
CARD=/media/$USER/EEFF-FCD8 bash scripts/install-prebuilt.sh
```

## O que o usuário precisa ter

A ROM e a trilha **não** acompanham o repositório (são conteúdo comercial):
use o dump do seu próprio cartucho.

```
/game/md/paprium.bin     8 388 608 bytes, md5 91ccdc0b20af85a16bfe0b1a698c19d0
/game/md/paprium/        52 arquivos .mp3 (trilha, ~446 MB)
```

## Compilando do zero

```bash
$ git clone https://github.com/rafarujo/paprium-gamestick && cd paprium-gamestick
$ SYSROOT=/caminho/sysroot bash scripts/build-core.sh      # core de depuracao
$ bash scripts/core-final.sh                               # build limpo + instala no cartão
```

## O que este repositório traz

| Item | O que é |
|---|---|
| `core/cart_hw/paprium.h` | mapper do Paprium corrigido (streaming de MP3, vídeo, áudio, RNG determinístico) |
| `docs/paprium-h.diff` | diff completo contra o `paprium.h` do fork |
| `docs/FINDINGS.md` | o diagnóstico: por que travava e como foi descoberto |
| `scripts/` | build ARM/x64, instalação no cartão, diagnósticos, coleta de log |

Três correções que fizeram diferença:

1. **Streaming de MP3 sem estourar o ring buffer** — o jogo toca 52 faixas
   (`/game/md/paprium/*.mp3`) direto do cartão; o decoder agora é alimentado
   dentro de `paprium_audio()`, sem abrir buraco na saída de áudio.
2. **RNG determinístico** (`0x1880–0x1AFF` virou LFSR de semente fixa). Antes o
   mapper usava `rand()` semeado com um endereço de pilha: cada execução (e cada
   build) tomava um caminho diferente no boot.
3. **Jitter de ciclos fixo** (`core/genesis.c`): o core sorteava a fração de
   ciclos do 68k por frame com `rand()`. Trocado por `0.5` — sem isso, duas
   execuções do mesmo binário divergiam.

## Build

Pré-requisitos: `arm-linux-gnueabihf-gcc`, um sysroot com glibc ≤ 2.29, `git`.

```bash
WORK=/caminho/para/clone  SYSROOT=/caminho/do/sysroot  bash scripts/build-core.sh
```

- `TRACE=1` (padrão) → core de depuração, com os traces `PDBG`
- `TRACE=0` → core final, sem log e sem o ring de PC/SP (mais rápido)
- `X64=1` → build para o RetroArch do PC, usado nas comparações

O script clona o fork, aplica os patches no `genesis.c`/`m68kcpu.c` (o patch do
jitter é idempotente), copia `core/cart_hw/paprium.h` e confere o binário
(símbolos, strings de trace, glibc máxima exigida).

Saídas:

| Variável | Padrão | Para quê |
|---|---|---|
| `WORK` | `/tmp/opencode/gpgx` | clone reaproveitado entre builds |
| `SYSROOT` | `/tmp/opencode/sysroot` | sysroot ARM (glibc do aparelho) |
| `OUT` | `$BASE/gamestick-ui/build/…` | onde o `.so` é gravado |

## Instalação no cartão

O cartão é montado em `/media/$USER/<LABEL>`; o core fica em
`retro_lib/genesis_plus_gx_paprium_libretro.so`.

```bash
bash scripts/install-prebuilt.sh  # instala um .so já compilado (dist/ ou release)
bash scripts/install-core.sh      # copia o .so, faz .bak, zera o ra.log, desmonta
bash scripts/build-install.sh     # build ARM + instala
bash scripts/core-final.sh        # build TRACE=0 + instala
```

## Layout esperado no cartão

```
/game/md/paprium.bin          8 388 608 bytes, md5 91ccdc0b20af85a16bfe0b1a698c19d0
/game/md/paprium/             52 arquivos .mp3  (trilha, ~446 MB)
/retro_lib/genesis_plus_gx_paprium_libretro.so
/ui/ra.log                    log do frontend
```

ROM e MP3 **não** estão neste repositório.

## Download do core

Binarios prontos ficam em [`dist/`](dist/LEIAME.md) e nas
[releases](https://github.com/rafarujo/paprium-gamestick/releases) — build ARMv7
para RK3032, glibc 2.29, `TRACE=0`.

```
dist/genesis_plus_gx_paprium_libretro.so                      (nome estavel)
dist/genesis_plus_gx_paprium_libretro-<VER>-rk3032.so         (por data)
```

Para atualizar o core: compile (`scripts/core-final.sh`) e copie o `.so` novo
para `dist/genesis_plus_gx_paprium_libretro.so` e
`dist/genesis_plus_gx_paprium_libretro-<data>-rk3032.so`. Opcional: anexar o
arquivo datado numa Release em **Releases → Draft a new release**.

## Scripts

| Script | Onde roda | O que faz |
|---|---|---|
| `scripts/install-prebuilt.sh` | PC + cartão | instala o `.so` pronto, com backup `.orig`, escolhendo o nome que o launcher usa |
| `scripts/install-core.sh` | PC + cartão | copia o `.so` compilado, faz `.bak`, zera o `ra.log` |
| `scripts/card-check.sh` | PC + cartão | inventário: ROM/md5, mp3, saves, core, config |
| `scripts/fix-card.sh` | PC + cartão | reescreve a ROM boa no cartão e confere o md5 |
| `scripts/copy-music.sh` | PC + cartão | confere/copia as 52 músicas por md5 |
| `scripts/build-core.sh` | PC | compila o core ARM (ou x64 com `X64=1`) |
| `scripts/build-x64.sh` | PC | build para o RetroArch do PC |
| `scripts/build-install.sh` | PC + cartão | build ARM + instala no cartão |
| `scripts/core-final.sh` | PC + cartão | build `TRACE=0` + instala |

Cada script grava um relatório (`*.txt`) em `$BASE` (padrão `~/Downloads`).

## O caso que custou mais caro

O jogo travava no console e funcionava no PC. Depois de muito trace, a causa não
era emulação: **32 KB da ROM no cartão tinham sido sobrescritos pelo próprio
`ra.log`** (o log e a ROM compartilhavam um bloco no sistema de arquivos). Com a
ROM recopiada, o mesmo core que "travava" passou a rodar. O caminho completo
está em [`docs/FINDINGS.md`](docs/FINDINGS.md).

## Compatibilidade

O core é um libretro comum — serve em qualquer frontend que carregue `.so`
libretro (RetroArch, Lakka, RetroPie, o frontend do próprio stick):

| Precisa | Detalhe |
|---|---|
| Arquitetura | ARMv7 **armhf** (o build de `dist/`); x86_64 tem build próprio (`X64=1`) |
| glibc | >= 2.11 |
| Bibliotecas | só `libc.so.6` e `libm.so.6` (MP3 via `minimp3`, embutido) |
| Conteúdo | `paprium.bin` (8 388 608 bytes) + pasta `paprium/` com os 52 MP3 de nomes fixos |

Num Game Stick de fábrica o core carrega igual: ele não depende de nada do
aparelho de origem. O que muda é **qual `.so` o frontend carrega**. No stick
investigado (launcher MiniGUI + RetroArch), o Mega Drive carrega:

```
/sdcard/retro_lib/genesisplusgx_libretro.so     (3 009 696 bytes, jan/2021)
```

(é o nome **sem** `_plus_`; o `genesis_plus_gx_libretro.so` também existe em
`retro_lib/`, mas não é o que o launcher usa para `.bin`/`.smd`). Um stick de
fábrica não conhece `genesis_plus_gx_paprium_libretro.so`, então a instalação
mais simples é:

```sh
cp retro_lib/genesisplusgx_libretro.so retro_lib/genesisplusgx_libretro.so.orig
cp dist/genesis_plus_gx_paprium_libretro.so retro_lib/genesisplusgx_libretro.so
```

Como este core é o fork completo do Genesis Plus GX, os Mega Drive normais
continuam rodando — só ganham o suporte a Paprium. Para voltar ao original,
basta restaurar o `.orig`. Outros aparelhos podem usar outro nome de core: é o
que aparece no comando que abre o jogo (`-L .../nome_libretro.so`); passe esse
nome para `scripts/install-prebuilt.sh`.

Não é o Genesis Plus GX oficial: Paprium só roda neste fork.

## Se não funcionar

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| trava na tela "Loading" ou no logo | ROM do cartão corrompida (log do frontend gravando em cima) | `bash scripts/fix-card.sh` |
| abre e volta para o menu | o launcher não conhece o nome do `.so` instalado | confira o comando `-L` do seu launcher e reinstale com `bash scripts/install-prebuilt.sh nome_libretro.so` |
| jogo roda, mas sem música | faltam MP3 em `/game/md/paprium/` | `bash scripts/copy-music.sh` |
| tela preta / erro ao carregar o core | `.so` de arquitetura errada (x86_64, aarch64, armel) | use o build ARMv7 armhf de `dist/` |
| trava só em um trecho específico | build de depuração escrevendo log sem parar | use o `TRACE=0` de `dist/` |

Antes de reinstalar qualquer coisa, rode `bash scripts/card-check.sh`: ele lista
ROM (tamanho + md5), músicas, saves, core instalado e config, e mostra o que
está fora do esperado.

## Licença e créditos

- `core/cart_hw/paprium.h` deriva do fork de BillyTimeGames / Genesis Plus GX —
  vale a licença do projeto original (GPL, uso não comercial).
- Scripts e documentação deste repositório: MIT (veja `LICENSE`).
