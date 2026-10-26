# Core compilado

Arquivos aqui sao **binarios prontos** (nao precisam ser compilados).

| Arquivo | Para que |
|---|---|
| `genesis_plus_gx_paprium_libretro.so` | nome estavel, sempre a ultima build |
| `genesis_plus_gx_paprium_libretro-<VER>-rk3032.so` | build por data |

Build ARMv7 (RK3032, glibc 2.29), `TRACE=0` (sem log).

## Como usar

1. Monte o cartao do Game Stick no PC.
2. Rode `bash scripts/install-prebuilt.sh` (do repositorio): ele copia o `.so`
   com o nome que o launcher do aparelho usa e guarda o antigo como `.orig`.
3. Desmonte o cartao, ligue o console e abra o Paprium.

Manual, se preferir:

```bash
cd /media/$USER/<cartao>/retro_lib
cp genesisplusgx_libretro.so genesisplusgx_libretro.so.orig   # backup
cp ~/Downloads/paprium-gamestick/dist/genesis_plus_gx_paprium_libretro.so \
   genesisplusgx_libretro.so
```

O nome `genesisplusgx_libretro.so` (sem `_plus_`) e' o que o launcher do Game
Stick usa para `.bin`/`.smd`. Se o seu aparelho usar outro nome, passe como
argumento: `bash scripts/install-prebuilt.sh nome_do_core.so`.

```bash
bash scripts/build-install.sh      # compila e instala
bash scripts/install-prebuilt.sh    # ou instala o .so pronto de dist/
```

## Requisitos

- `/game/md/paprium.bin` — 8 388 608 bytes, md5 `91ccdc0b20af85a16bfe0b1a698c19d0`
- `/game/md/paprium/` — os 52 arquivos `.mp3` da trilha

ROM e MP3 nao acompanham este repositorio.

## Licenca

Este `.so` e' um build do Genesis Plus GX (fork BillyTimeGames), portanto vale a
licenca do projeto original. O codigo-fonte correspondente esta neste
repositorio: `core/cart_hw/paprium.h` + `scripts/build-core.sh`.

## Compatibilidade

O `.so` e' um **core libretro comum**: qualquer frontend que carregue cores
libretro serve (RetroArch, Lakka, RetroPie, o frontend do stick...). Nao depende
de nada do aparelho de origem.

| Precisa | Detalhe |
|---|---|
| Arquitetura | **ARMv7 armhf** (hard-float). Nao carrega em x86_64, aarch64, armel |
| glibc | **>= 2.11** (o binario nao pede simbolo mais novo) |
| Bibliotecas | so' `libc.so.6` e `libm.so.6` (o MP3 e' decodificado por `minimp3`, embutido) |
| Frontend | API libretro padrao (RetroArch 1.9+ ok) |
| CPU | precisa decodificar MP3 em tempo real (RK3032, Cortex-A7 1.2 GHz, da' conta) |

Nao e' o Genesis Plus GX "oficial": Paprium so' roda neste fork (mapper com
streaming de MP3). O `.so` ja' e' o fork completo.

## Conteudo que o usuario precisa ter

```
<jogo>/paprium.bin     8 388 608 bytes, md5 91ccdc0b20af85a16bfe0b1a698c19d0
<jogo>/paprium/        52 .mp3 com os nomes exatos (a trilha)
```

Os nomes dos MP3 sao **fixos no codigo** (`02 90's Acid Dub Character Select.mp3`,
`08 90's Dance.mp3`, ...). Faltando arquivo, o jogo roda mas fica sem musica.
ROM e MP3 nao acompanham o repositorio.
