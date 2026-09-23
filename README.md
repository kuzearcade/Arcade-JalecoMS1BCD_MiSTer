# Arcade-JalecoMS1BCD_MiSTer

Jaleco **Mega System 1**, types **B**, **C** and **D**, for the MiSTer FPGA
platform — a from-scratch RTL implementation of the board's tilemap, sprite
and priority hardware, built against MAME's `jaleco/megasys1.cpp` as the
behavioural reference. See [Attribution](#attribution).

**One `.rbf` serves all sixteen sets across three board types.** Nothing in
the bitstream is per-game: the `.mra` carries a *game-mode byte* — the third
`<switches>` byte — that tells the core which board it is (`[1:0]` type,
`[4]` sample clock, `[6:5]` protection model, `[7]` autofire menu), and the
memory map, video layout, interrupt model and I/O all follow from it.

## Goals

- One core for every Mega System 1 B/C/D set, verified against MAME
- **Every claim a measurement.** An entry in `docs/known-issues.md` is only
  closed by a number, never by reasoning. The simulation harnesses compare
  frames pixel-for-pixel with MAME captures, the 68000 bus against MAME's own
  trace, and every ROM byte through the real SDRAM controller and cache.

## Status

**All 16 shipped sets boot and run on a DE10-Nano** — System B 7 of 7,
System C 7 of 7, System D 2 of 2.

See `docs/PLAN.md` for the plan, `docs/hw-bringup.md` for build numbers and
the bring-up log, and `docs/known-issues.md` for what is measured, what is
assumed and what is still open.

## Supported games

Sixteen sets. `iosim` is MAME's simulated I/O protection, `mcu` is the real
TLCS-90 (TMP91640) running its dumped ROM.

### System B — 68000 @ 8 MHz, sound 68000 @ 7 MHz, YM2151, 2 × OKIM6295 @ 4 MHz

| set | game | protection |
|---|---|---|
| `avspirit` | Avenging Spirit (1991) | mcu |
| `monkelf` | Monky Elf (Korean bootleg of Avenging Spirit) | none |
| `edf` | E.D.F.: Earth Defense Force (set 1, 1991) | mcu |
| `edfa` | E.D.F.: Earth Defense Force (set 2) | mcu |
| `edfb` | E.D.F.: Earth Defense Force (set 3) | mcu |
| `edfu` | E.D.F.: Earth Defense Force (North America) | mcu |
| `hayaosi1` | Hayaoshi Quiz Ouza Ketteisen: The King Of Quiz (1993) | iosim |

### System C — as B, but the main 68000 runs at 12 MHz

| set | game | protection |
|---|---|---|
| `64street` | 64th. Street: A Detective Story (World, 1991) | mcu |
| `64streetj` | 64th. Street (Japan, set 1) | mcu |
| `64streetja` | 64th. Street (Japan, set 2) | mcu |
| `bigstrik` | Big Striker (1992) | mcu |
| `chimerab` | Chimera Beast (Japan, prototype, set 1, 1993) | mcu |
| `chimeraba` | Chimera Beast (Japan, prototype, set 2) | iosim |
| `cybattlr` | Cybattler (1993) — ROT90 | mcu |

### System D — one 68000 @ 8 MHz, one banked OKIM6295 @ 2 MHz, no sound CPU

| set | game | protection |
|---|---|---|
| `peekaboo` | Peek-a-Boo! (Japan, ver. 1.1, 1993) | its own |
| `peekaboou` | Peek-a-Boo! (North America, ver 1.0) | its own |

`edfbl` is deliberately excluded: it is not a System B board (a PIC in place
of the TMP91640, no sound CPU, a banked OKI), and MAME flags the whole
machine `MACHINE_NO_SOUND`.

System D is a different board rather than a variant — two scroll layers
instead of three, an `RGBx_555` palette, no `global_mask`, one vblank IRQ
instead of three scanline IRQs, and its own protection port that doubles as
the sample-bank latch.

`clk_sys` is 48 MHz. Most of the board divides out of it exactly — main
68000 /6 (B, D) or /4 (C), OKI /12 or /24, pixel clock /8 = 6 MHz — but the
7 MHz sound CPU does not, so its phi enables come from a fractional
accumulator rather than a divider, with the YM2151 at exactly half of it.
The raster is 384 × 278, visible 256 × 224 from row 16.

## Attribution

**The MAME driver is the reference this core was built against, and the debt
is a large one.** `jaleco/megasys1.cpp` is the work of **Luca Elia**, who
wrote the Mega System 1 driver, and **David Haywood**; the two are its
copyright holders, and the file is BSD-3-Clause.

Every behavioural claim in this repository is measured against that code
running as MAME 0.289. Nothing here is copied from it — the RTL is written
from scratch — but the memory maps, the protection models, the tilemap and
sprite formats, the priority PROM semantics and the machine configurations
were all read out of that driver first. Without it this core would have been
guesswork against a PCB.

Built on the MiSTer framework and on these cores, fetched by
`tools/bootstrap.sh` at the commits pinned in `deps.lock`:

| | |
|---|---|
| `fx68k` — 68000 | Jorge Cwik (ijor) |
| `jt51` — YM2151 | Jose Tejada (jotego) |
| `jt6295` — OKIM6295 | Jose Tejada (jotego) |
| Hiscores_MiSTer | Alan Steremberg, Jim Gregory |
| CRT Adjust | Umberto Parisi (rmonic79) |
| `sdram.sv` | Sorgelig lineage, via Arcade-Darius_MiSTer |
| Template_MiSTer | MiSTer-devel |

The SDRAM controller and the hiscore module carry local modifications,
described in `deps.lock`. `rtl/tlcs90/` is this project family's own
from-scratch TLCS-90 CPU, re-parameterised here as the TMP91640 I/O MCU — no
open-source RTL for that ISA existed to vendor.

High-score definitions come from MAME's `hiscore.dat`; cheat tables come from
Pugsy's MAME cheat database.

## Licensing

This repository is GPL-3.0. One caveat is recorded rather than glossed over:
`Template_MiSTer` is GPL-2.0-only, which is not compatible by default with
the GPL-3.0-only components in a combined work. It is flagged in
`docs/PLAN.md` and `deps.lock` and must be resolved before any binary
release.

Mega System 1 games are © Jaleco. **No ROM data is included in this
repository**, and none ever will be.
