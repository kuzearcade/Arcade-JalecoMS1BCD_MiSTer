# Arcade-JalecoMS1BCD_MiSTer — Project Plan (draft for review, 2026-09-20)

Jaleco Mega System 1, systems **B**, **C** and **D** (MAME
`jaleco/megasys1.cpp`, driver by **Luca Elia** and **David Haywood**) as a
single MiSTer FPGA core,
built the way `Arcade-NMK16_MiSTer` and `Arcade-SandScrp_MiSTer` were built:
RTL that behaves like the board, MAME as the behavioural oracle, Verilator
harnesses before hardware, the DE10-Nano as the final proof, and the same
user-facing feature set (OSD DIPs, Orientation, Flip screen, CRT Adjust,
direct-video menu split, Autofire, Pause, High scores, Cheats, Savestates,
keyboard mapping, one `.mra` per set, an `autofire_releases/` mirror).

**One `.rbf` — `Arcade-JalecoMS1BCD` — three hardware modes, seventeen sets.**
B and C are the same board family with a different memory map, a different
main-CPU clock and one extra register; they share the video hardware, the sound
board and the protection MCU. D is a cut-down member of the same family: the
same video registers as C, the same sprites, palette and priority PROM, the
same protection chip — but one 68000 instead of two, two tilemap layers instead
of three, one sample chip instead of two and no FM at all. That is a game-mode
split of the kind NMK16 already ships four times over, not three cores.

| mode | sets | main CPU | sound | layers |
|---|---|---|---|---|
| **B** | 8 | 68000 @ 8 MHz | 68000 + YM2151 + 2x OKI | 3 |
| **C** | 7 | 68000 @ 12 MHz | 68000 + YM2151 + 2x OKI | 3 |
| **D** | 2 | 68000 @ 8 MHz | 1x OKI, banked, driven by the main CPU | 2 |

Nothing below has been built. Section 1 is the hardware as MAME describes it,
section 2 the architecture and what is copied from the two finished projects,
section 3 the milestones and their gates, section 4 the lessons from NMK16 and
Sand Scorpion mapped onto this board, section 5 the open questions to settle
first, section 6 what to do on day one.

D is a first-class mode of this core, not an afterthought — but it is
**sequenced last** for the reason section 2.5 gives: adding a mode to a core
that already works is contained, while building three at once is how three
things end up half-finished.

---

## 0. Facts that shape the plan

1. **The protection MCU is a Toshiba TMP91640, and we already have that CPU.**
   It is TLCS-90 family (MAME puts it in `cpu/tlcs90/`), and
   `Arcade-NMK16_MiSTer/rtl/tlcs90/tlcs90.sv` is a 2,314-line from-scratch
   TLCS-90 core already verified against MAME's reference model and already
   shipping as two different Toshiba parts (NMK004 = TMP90C840AF, and the
   NMK-110/113/215 protection MCUs). The TMP91640 differs from those only in
   internal memory sizes: **16 KB ROM at `0x0000-0x3FFF`, 512 B RAM at
   `0xFDC0-0xFFBF`**, against the 90C840's 8 KB / 256 B. This is the single
   biggest reuse win in the project and it turns the highest-risk item —
   "write a CPU core for an undocumented protection MCU" — into a
   parameterisation.
2. **Eleven of the seventeen sets need that MCU in MAME; six do not.** MAME emulates the
   real MCU (`system_B_iomcu` / `system_C_iomcu`) for avspirit, edf ×4,
   64street ×3, bigstrik, chimerab and cybattlr. Two sets use a *behavioural
   simulation* of the same protocol (`iosim`: hayaosi1, chimeraba) and two are
   bootlegs with the protection stripped and the ports wired directly
   (monkelf, edfbl), and **both System D sets carry a dumped TMP91640 that MAME
   does not run at all** — it simulates a ten-line protocol instead, because the
   driver's own notes say that chip is "connected differently". So there is a
   cheap path (simulate the protocol) and an exact path (run the dumped 16 KB
   ROM), and the plan takes the exact one for B and C because the core for it
   already exists, keeping the simulation as the bring-up aid and as the only
   option for the four sets whose MCU is absent or unusable.
3. **Two 68000s in B and C, one in D.** Main plus sound, exactly like Sand Scorpion's 68000+Z80 but
   with a second `fx68k` instead of a T80. Both are already proven in this
   family of projects. In D mode the sound CPU never leaves reset and the main
   CPU drives the single sample chip itself.
4. **A new sound chip: YM2151.** NMK16 and Sand Scorpion use YM2203 (`jt03`)
   and OKIM6295 (`jt6295`). MS1-B/C use **YM2151 + two OKIM6295s**; MS1-D uses
   **one OKIM6295 with eight-bank ROM switching and no FM at all**. `jt51` is the
   matching Jotego core and is the one new third-party dependency. The two
   OKIs are instances of a core we already drive correctly, including the
   `oki_rom_cache` + `stall`-into-`cen` discipline that was mandatory for Sand
   Scorpion — and D's banking is a new path into that sample address, which is
   exactly where that discipline matters.
5. **Three tilemap layers (two in D) and an indirected sprite list.** More video than
   either previous project: three independently scrolling layers with
   selectable 8x8/16x16 tiles and a selectable page layout, 256 sprites whose
   placement comes from a separate 1 KB "Object RAM" with four flip-indexed
   banks, and a **512-byte priority PROM** that resolves layer/sprite order.
6. **No ROM or PROM data is ever compiled into the bitstream.** This is a
   hard rule for the project, not a preference, and it has its own section
   (2.3) and its own gate in M0 and M4. Everything the board reads out of a
   memory device — the priority PROM, the protection MCU's internal ROM, the
   program, graphics and sample ROMs — arrives at run time from the user's own
   `.mra` and is held in RAM the core writes during the ioctl download. NMK16
   paid for getting this wrong once (NMK-22). One set (chimerab) has no PROM
   dump and MAME substitutes 64street's; that is a documented substitution
   declared in the `.mra`, never a table quietly carried in the RTL.
7. **The raster is the NMK16 raster.** `set_raw(6 MHz, 384, 0, 256, 278, 16,
   240)`: 384 x 278 at a 6 MHz pixel clock, visible 256 x 224 at rows 16-239,
   **56.22 Hz**. `video_retime.sv` already defaults to VTOTAL 278 and
   `crt_chain.sv` is already parameterised for it. Unlike Sand Scorpion's
   SS-1, this raster is given explicitly by the driver rather than inferred
   from a sibling board — though the commented-out alternative in the source
   (`406, 0, 256, 263, 16, 240`) is a flag that it has been argued about.
8. **48 MHz `clk_sys` again, and again for a reason.** Every clock but one
   divides exactly: main 68000 8 MHz (B) = /6 and 12 MHz (C) = /4, pixel
   6 MHz = /8, both OKIs 4 MHz = /12. Only the 7 MHz sound 68000 and its
   3.5 MHz YM2151 need an accumulator, and they are a self-contained domain.
9. **cybattlr is ROT90.** One vertical game among sixteen horizontal ones, so
   the Orientation menu must be per-game, not per-core.
10. **ROM budget is small**: 2.77 MB (D), 2.89 MB (B), 3.27 MB (C) per set,
    well inside one SDRAM chip, with no main-CPU bank switching in any mode.

---

## 1. The hardware, from the driver

### 1.1 CPUs, clocks, memory maps

| | System B | System C | System D |
|---|---|---|---|
| Main CPU | 68000 @ **8 MHz** | 68000 @ **12 MHz** (24/2) | 68000 @ **8 MHz** |
| Sound CPU | 68000 @ 7 MHz | same | **none** |
| FM | YM2151 @ 3.5 MHz (7/2) | same | **none** |
| PCM | 2 x OKIM6295 @ 4 MHz | same | **1 x OKIM6295 @ 2 MHz**, banked |
| Tilemap layers | 3 | 3 | **2** |
| Pixel clock | 6 MHz (12/2) | same | same (see section 5 q.9) |
| Raster | 384 x 278, visible 256 x 224 (rows 16-239) | same | not stated upstream; 56.18 Hz assumed |

Main CPU map (B masks to 20 bits, C to 21; D is unmasked):

| | System B | System C | System D |
|---|---|---|---|
| ROM | `000000-03FFFF` + `080000-0BFFFF` | `000000-07FFFF` | `000000-03FFFF` |
| Video regs | `044000-0443FF` | `0C2000-0C23FF` | `0C2000-0C23FF` (**as C**) |
| Palette | `048000-0487FF` | `0F8000-0F87FF` | `0D8000-0D87FF` (mirror +0x3000) |
| Object RAM | `04E000-04FFFF` | `0D2000-0D3FFF` | `0CA000-0CBFFF` |
| Scroll 0 | `050000-053FFF` | `0E0000-0E3FFF` (mirror +0x4000) | **`0E8000-0EBFFF`** |
| Scroll 1 | `054000-057FFF` | `0E8000-0EBFFF` (mirror +0x4000) | **`0D0000-0D3FFF`** |
| Scroll 2 | `058000-05BFFF` | `0F0000-0F3FFF` (mirror +0x4000) | — |
| Work RAM | `060000-06FFFF` (mirror +0x10000) | `1C0000-1CFFFF` (mirror +0x30000) | `1F0000-1FFFFF` |
| Protection port | `0E0000` | `0D8000` | `100000` (P1/P2 only) |
| Direct input ports | — | — | DSW `0E0000`, SYSTEM `0F0000` |
| Sample chip | — | — | `0F8001` (main CPU writes the OKI directly) |
| Sound latch | `044308` (write) | `0C8000` (read latch 2 / write latch 1) | — |

**System D's layer addresses are inverted against its layer indices.** MAME's
`m_tmap[0]` sits at `0E8000` and `m_tmap[1]` at `0D0000` — the opposite order
to System C, where layer 0 is the lower address. This is the naming cross of
section 1.1 in its most confusing form, and it is the single likeliest source
of a "D mode draws the wrong layer" bug.

Note the **register/VRAM naming cross**: MAME's `m_tmap[0]` is shared as
`"scroll1"`, `m_tmap[1]` as `"scroll2"`, `m_tmap[2]` as `"scroll3"`, while the
driver's own documentation calls them Scroll 0/1/2. Sand Scorpion's section 4.D
lists exactly this class of naming cross as a thing that cost days. Fix the
naming once, in one table, and derive both the RTL and the `.mra` from it.

Also note that on System B the video registers put **Scroll 2's** control at
`044008` while Scroll 0 and 1 are at `044200`/`044208`; on System C the three
are at `0C2000`/`0C2008`/`0C2100`. The ordering is not the same between modes.

Sound CPU map (identical for B and C except the latch address):

| | |
|---|---|
| ROM | `000000-01FFFF` |
| Latch from/to main | `040000` (B) / `060000` (C), both read latch 1 and write latch 2 |
| YM2151 | `080000-080003`, low byte |
| OKI #1 | `0A0000-0A0003` write, `0A0001` status read |
| OKI #2 | `0C0000-0C0003` write, `0C0001` status read |
| RAM | `0E0000-0EFFFF`, mirrored at `0F0000` (verified on hardware) |

**The OKI status hack.** The driver carries a `SOUND_HACK` that makes the
M6295 status register return 0, which "fixes the music tempo in avspirit,
64street, astyanax etc. but makes most of the effects in hachoo disappear",
and notes a bootleg patched the game code to do the same thing. This is an
open question in MAME, and therefore an open question here — see section 5.

### 1.2 Interrupts

**B and C**: three levels, all from the scanline timer.

| Level | Scanline | Meaning |
|---|---|---|
| 1 | 96 (80+16) | mid-screen |
| 2 | 16 | end of vblank — **or** from the protection MCU on command |
| 4 | 240 (224+16) | vblank-out |

**D is different and simpler**: a single vblank interrupt at **level 2**, plus
**level 4** raised by every write to the protection port. No scanline timer at
all. A mode-selected interrupt source, not a variation on one scheme.

The driver's own to-do list says "Understand properly how IRQs truly works,
kazan / iganinju solution seems hacky" — that is about System A, but it is a
warning that the interrupt model here is not settled upstream. Level 2 has two
independent sources (scanline 16 and the MCU), which is the kind of merge that
NMK16 built `nmk_irq` for.

### 1.3 Inputs, DIPs, and the protection

The 68000 never reads the input ports directly. It writes a command byte to the
protection port and reads the answer back from the same address, and the MCU
raises IRQ 2 when an answer is ready. MAME models this two ways:

**Behavioural (`iosim`)** — a per-game table of seven command values selects
SYSTEM / P1 / P2 / DSW1 / DSW2, plus two fixed replies (`0x0D` at startup,
`0x06` before each command):

    hayaosi1  0x51 0x52 0x53 0x54 0x55  0xFC 0x06
    chimeraba 0x56 0x52 0x53 0x55 0x54  0xFA 0x06

and, from the driver's comments, the values the now-MCU-driven games used to
need: avspirit `37 35 36 33 34`, 64street `57 53 54 55 56`, bigstrik
`58 54 55 56 57`, cybattlr `56 52 53 54 55`, edf `20 21 22 23 24`.

**Exact (`iomcu`)** — the real TMP91640 runs its dumped 16 KB ROM, reads the
inputs through a banked read (`bank = offset >> 16`: 1=P1, 2=P2, 3=DSW1,
4=DSW2, 5=SYSTEM, 7=raise IRQ2), takes the 68000's command byte on port 1,
returns the answer on port 2, and writes an unknown bit 3 on port 6. It gets
INT1 asserted at scanline 16 and cleared at 240.

**System D's protection is a third thing again**, and much smaller. A write
latches a value, selects the sample ROM bank when `(value & 0x90) == 0x90`
(`bank = value & 7`), and raises IRQ 4. A read returns `0x03` for command
`0x02`, P1 for `0x51`, P2 for `0x52`, and otherwise echoes the value back. DSW
and SYSTEM are read directly, not through it. Ten lines of RTL, no handshake,
no MCU — even though D's TMP91640 is dumped (see section 2.5).

The plan takes the **exact** path for B and C, because the CPU core already
exists. The
behavioural path stays in the design as a per-game fallback for the two sets
whose MCU is not dumped, and as a bring-up aid: it is far easier to get a game
booting against a 30-line protocol model than against a CPU that must first be
correct.

### 1.4 Video

**Three scrolling layers**, one 16-bit word per tile (`fedc` = palette,
`----ba9876543210` = tile number). A page is 256x256; a layer is 8 pages of
16x16 tiles or 32 pages of 8x8, with the horizontal page count and the tile
size chosen by the layer's own control register:

    offset 00   scroll X
    offset 02   scroll Y
    offset 04   bit 4    0 = 16x16 tiles, 1 = 8x8 tiles
                bits 1:0 N, layer H pages = 16 >> N

**Layer enable / priority register** (`044000` on B, `0C2208` on C):

    ---- ba98 ---- ----  priority code (16 values, PROM-translated)
    ---- ---- ---- 3---  enable sprites
    ---- ---- ---- -210  enable layers 2,1,0 (layer 0 cannot be disabled)

**Sprites.** 256 entries of 16 bytes in sprite RAM, but placement is indirect
through **Object RAM** (8 bytes per entry, 256 entries x 4 banks):

    Object RAM  00 index into sprite data    02 H displacement
                04 V displacement            06 number displacement

    Sprite data 08 bit 7 y flip, bit 6 x flip, bits 3:0 colour (bit 3 = priority)
                0A H position   0C V position   0E tile number

The four 256-entry Object RAM banks are selected by the sprite's own flip
state: `000-0FF` no flip, `100-1FF` flip X, `200-2FF` flip Y, `300-3FF` both.
Sprite order is **first entry frontmost** — the opposite of Sand Scorpion's
PANDORA, and exactly the reversal that NMK16's section 4.D item 8 records as
having broken "ships under clouds". Get it from the driver, not from intuition.

System C adds a **sprite bank** bit at `0C2108`. B has no such register.

**Sprite control** (`044100` / `0C2200`): bit 8 splits sprites into two groups
by colour code (0-7 and 8-F) so that some appear over and some below the
layers; bit 4 enables an "effect" (do not clear the sprite framebuffer) with a
4-bit effect number whose meaning the driver admits it does not know.

**Palette**: 0x800 bytes = 1024 colours in four groups of 256 — scroll 0, 1, 2,
sprites. The bit layout is interleaved and is *not* plain RGB555:

    fedc--------3---  red     ----ba98-----2--  blue
    --------7654--1-  green   ---------------0  used, but not colour

**Priority**: a 512-byte PROM indexed by `pri_code * 0x20 + offset +
enable_mask * 2`, where `offset` is 0 or 1 for the sprite-split state and
`enable_mask` is the current layer-enable set. MAME converts the PROM into a
layer order at init by repeatedly asking "which layer is on top of the
remaining set". The RTL can either do the same conversion once at load time or
index the PROM per pixel; measure before choosing.

**Screen control** (`044300` / `0C2308`): bit 0 flip screen, bit 4 resets the
sound CPU on a 1->0 transition, bit 8 "portrait F/F".

### 1.5 ROMs and the SDRAM image

Per set, from the driver's `ROM_REGION`s:

| region | System B | System C | System D |
|---|---|---|---|
| maincpu | 512 K | 512 K | 256 K |
| audiocpu | 256 K | 128 K | — |
| iomcu / mcu | 16 K | 16 K | 16 K (dumped, unused by MAME) |
| scroll1 | 512 K | 512 K | 512 K |
| scroll2 | 512 K | 512 K | 512 K |
| scroll3 | 128 K | 128 K | — |
| sprites | 512 K | 1024 K | 512 K |
| oki1 | 256 K | 256 K | **1024 K**, banked |
| oki2 | 256 K | 256 K | — |
| proms | 512 B | 512 B | 512 B |
| **total** | **2.89 MB** | **3.27 MB** | **2.77 MB** |

Every one of those regions, **including `iomcu` and `proms`**, comes from the
user's own ROM images through the `.mra`; none is carried in the bitstream
(section 2.3).

One contiguous SDRAM layout per game mode, regions in `.mra` part order, sizes
exactly the part sizes, base table and part list generated from **one** table —
the Sand Scorpion rule, and the reason its off-board load model caught its
region bases before any hardware existed.

---

## 2. Architecture and reuse

### 2.1 Repository layout

    rtl/jaleco/        ms1_tilemap.sv    one of the three scroll layers
                       ms1_sprites.sv    Object RAM walk + sprite draw
                       ms1_prio.sv       priority PROM -> layer order
                       ms1_video.sv      composition + palette
                       video_timing_ms1.sv
    rtl/ms1bcd/        ms1bcd_core.sv    the board, all three game modes
                       ms1bcd_rom_hw.sv   SDRAM side: caches, arbiters, download
    rtl/tlcs90/        tlcs90.sv         COPIED from NMK16, re-parameterised
                       tmp91640_periph.sv
    rtl/third_party/   fx68k, jt51 (new), jt6295, hiscore, crt_adjust
    rtl/               sdram, caches, video_retime, crt_chain, cheats, savestate
    sim/               oracle, video_state, ms1bcd, ms1bcd_hw, unit tests
    tools/             .mra generator + load model, decoders, frame gates
    releases/          the .mra files and the current .rbf

### 2.2 Reuse map

**Copied essentially unchanged** from `Arcade-NMK16_MiSTer` (and its Sand
Scorpion fork, whichever is the more recent):

| file | why it transfers |
|---|---|
| `rtl/sdram.sv`, `sdram_req.sv`, `sdram_arb.sv` | same controller, same 96 MHz, same CDC; keep `REFRESH_CYCLES(740)` |
| `rom_cache1*.sv`, `rom_cache_n*.sv`, `oki_rom_cache.sv`, `tile_prefetch_byte.sv` | same problems: a 68000 that stalls without the 16-pair cache, an OKI that ignores `rom_ok` |
| `rtl/video_retime.sv` | already defaults to **VTOTAL 278**, this board's own value |
| `rtl/crt_chain.sv` + `third_party/crt_adjust` | unchanged |
| `rtl/cheats.sv`, `third_party/hiscore` | unchanged |
| `rtl/savestate/*` | unchanged engine; the park modules need a second 68000 park instead of a Z80 park |
| `rtl/third_party/fx68k` | two instances |
| `rtl/third_party/jt6295` | two instances |
| **`rtl/tlcs90/tlcs90.sv`** | **the protection MCU's CPU, already verified** |
| `sys/`, the MiSTer top-level structure, `.qsf`/`.qip`/`.sdc` | unchanged |
| `tools/mister_keys.py` (with the chord fix), `mister_sweep*.sh`, `audio_compare.py`, `compare_frames.py`, `gen_hiscore_mra.py`, `gen_cheats_mra.py`, `gen_autofire_mra.py`, `mk_ioctl_stream.py` | unchanged |
| `tools/board_feature_test.py` (Sand Scorpion) | drives OSD options through `<setname>.CFG` and `.dip`, which is the only way to test them, since the native screenshot has no OSD overlay |

**Adapted**: the `.mra` generator (one table, three outputs), the savestate
image map, `video_timing_*` (parameters only), the top level's CONF_STR.

**New**: the three Jaleco video blocks, the priority resolver, the protection
glue, the TMP91640 peripheral shell, and `jt51`.

**One new third-party dependency**: `jt51` (Jotego's YM2151). Pin it in
`deps.lock` with the rest and fetch it in `bootstrap.sh`.

### 2.3 No baked ROM or PROM data — how it is enforced

**The rule.** The `.rbf` contains logic only. Every byte the board would have
read from a ROM, PROM or MCU mask ROM reaches the core at run time, from the
ROM images the user supplies, through the `.mra`. Nothing in `rtl/` may carry
game data in any form: no `$readmemh` on a hardware path, no initialised
`reg` array, no `case` table transcribed from a dump, no `.mif`/`.hex` in the
Quartus project.

**The three things this covers on this board**, none of which may be an
exception:

| data | size | how it arrives |
|---|---|---|
| Program, graphics and sample ROMs | ~2.9-3.3 MB | `<rom index="0">`, straight into SDRAM |
| **Priority PROM** | 512 B | **`<rom index="1">`**, into a small RAM in `ms1_prio.sv` |
| **TMP91640 internal MCU ROM** | 16 KB | part of `<rom index="0">`, its own SDRAM region behind a cache, as NMK16 does for the NMK004 |

**The mechanism, already proven in NMK16.** `rtl/nmk_irq/nmk_irq.sv` is the
worked example and `ms1_prio.sv` copies its shape exactly:

- the RTL declares a plain write port — `prom_we`, `prom_addr`, `prom_data` —
  and an internal RAM with **no initial contents**;
- `ms1bcd_rom_hw.sv` decodes `ioctl_index == 1` during the download and drives
  that port, exactly as it decodes index 0 into SDRAM writes;
- a `$readmemh` exists **only** inside a `generate` branch guarded by
  `HW_ROMS == 0`, for the Verilator reference sim, where `prom_we` is tied low.
  That branch is never part of a synthesised build, and the guard is the thing
  to check in review.

The MCU ROM takes the SDRAM route rather than a write port because 16 KB is
eight M10K blocks and the CPU's access pattern is a cache's natural workload;
NMK16 reaches the NMK004's ROM through `rom_addr`/`rom_din` with the wrapper
withholding `cen` until the byte is valid, and the same wrapper works here.

**How it is verified, twice.**

1. **M0, off-board.** The `.mra` generator's `--check` model already walks
   every region; extend it to assert that the PROM and MCU regions are present,
   correctly sized and CRC-matched for every one of the seventeen sets. A set
   whose PROM is a documented substitution (chimerab) must say so in the
   `.mra` comment and still carry a real file.
2. **M4, on the bitstream.** A build-time check that greps the synthesised
   file list for `$readmemh` outside an `HW_ROMS == 0` guard and for any
   `.mif`/`.hex` in the `.qip`, plus a scan of the `.rbf` for the PROM's own
   byte sequence. NMK16's NMK-22 was found by noticing a `.mif` in a build
   log; a grep is cheaper than noticing.

**Why it matters beyond licensing.** A baked table also silently breaks the
per-set correctness the rest of the plan depends on: the priority PROM differs
between sets, and a core carrying one set's table would render every other set
wrong in a way that looks like a priority bug rather than a missing file.

### 2.4 Game modes

One `.rbf`, mode selected exactly as NMK16 does it: a **game-id byte in the
`.mra`'s own `<switches>` block**, read at run time, never used to decide
anything during the ROM stream (NMK16's NMK-29: index 254 arrives last).

The mode selects:

| | B | C | D |
|---|---|---|---|
| main CPU clock enable | 8 MHz | 12 MHz | 8 MHz |
| address decode | 20-bit map | 21-bit map | D map |
| sprite-bank register | absent | present | absent |
| third tilemap layer | on | on | **off** |
| sound subsystem | 68000 + YM2151 + 2 OKI | same | **main CPU drives 1 banked OKI** |
| interrupts | 3 scanline levels | same | **vblank IRQ2 + IRQ4 on protection write** |
| protection | TMP91640 handshake | same | **value compare + bank select** |

Everything else is shared. Per-set differences beyond the mode — the protection
command table for the two `iosim` sets, the bootlegs' direct ports — are
further bits in the same byte.

Two consequences for how the RTL is written, and they are cheap now and
expensive later:

1. **The address decode is a per-mode table**, not a chain of `if (mode_b)`
   branches. Three maps that mostly agree but disagree in scattered places is
   precisely the shape that becomes unreadable as branches.
2. **The OKI sample address goes through a bank register** that is hard-wired
   to zero in B and C mode. Retrofitting a bank into a sample path that has
   already been tuned for throughput is the kind of change that reintroduces
   the stale-byte class of bug section 4.B item 6 describes.

### 2.5 System D, the third mode

System D is Peek-a-Boo! (`peekaboo`, `peekaboou` — two sets, 2.77 MB each).
Hardware-wise it is very largely a **subset** of B/C, not a new board, which is
why it earns a mode rather than a project. It is **built last** — see the
sequencing note at the end of this section — but it is a shipped mode, gated
like the other two.

**What it shares, needing no new RTL at all**

| | |
|---|---|
| Main CPU | 68000 at **8 MHz** — the same clock enable System B already needs |
| Video registers | `0C2000`/`0C2008` scroll control, `0C2200` sprite flag, `0C2208` active layers, `0C2308` screen flag — **the same offsets as System C** |
| Tilemaps | the same device, simply two of them instead of three |
| Sprites | identical, including the Object RAM indirection and the same graphics layout (`gfx_abc`) |
| Palette | the same 0x800 bytes and the same interleaved non-RGB bit layout (`megasys1_palette`) |
| Priority PROM | the same 512-byte N82S131N, same role |
| PCM | OKIM6295, an instance we already have |

**What is genuinely new, and it is all small**

1. **A third address map.** Close to C's but not the same: palette at
   `0D8000`, Object RAM at `0CA000`, work RAM at `1F0000`, and the two scroll
   RAMs at `0E8000` and `0D0000`. **Trap:** the tilemap index and the address
   order are *inverted* against C — `m_tmap[0]` lives at `0E8000` while
   `m_tmap[1]` lives at `0D0000`. This is exactly the naming cross section 1.1
   warns about, in its most confusing form.
2. **OKI ROM banking.** `20000-3FFFF` is banked, eight entries, selected by
   `protection_val & 7` but only when `(protection_val & 0x90) == 0x90`. B and
   C have no OKI banking at all. Small, but it is a new path into the sample
   address, and section 4.B item 6's warning about clk-sampled registers
   changing an OKI address applies directly.
3. **A different and much simpler protection.** No MCU handshake: a write
   latches a value and raises **IRQ 4**; a read returns `0x03` for command
   `0x02`, P1 for `0x51`, P2 for `0x52`, and otherwise echoes the value. Ten
   lines. DSW and SYSTEM are read **directly** at `0E0000` and `0F0000`.
4. **A different interrupt model.** One vblank IRQ at level 2, plus level 4
   from the protection write — instead of B/C's three scanline IRQs.
5. **A different OKI clock**: 2 MHz (8/4) against B/C's 4 MHz. Both are exact
   divisions of 48 MHz (/24 and /12), so this costs a mux, not a PLL.

**What sits idle in D mode**: the sound 68000, the YM2151, the second OKI, the
sound latch and the TLCS-90 MCU. They stay in the fit — the area is already
paid for by B and C — and simply do nothing. That is the honest cost of a
shared `.rbf` and it is the same trade NMK16 makes four times. It also means
D adds essentially **no fit cost**: a third decode table, a 3-bit bank register
and ten lines of protection.

**The interesting part.** Peek-a-Boo!'s protection chip is *also* a
**TMP91640**, and its 16 KB internal ROM **is dumped** (`mo-92033.mcu.ic120`,
CRC `9dfba11b`). MAME does not run it — the driver's own to-do list says "Hook
up microcontroller for peekaboo (connected differently to other games)" — and
falls back to the ten-line simulation above. Since this project will already
have a TLCS-90 core executing that exact part for B and C, D is the one place
where this core could plausibly do something MAME currently does not.

That is an **opportunity, not a plan commitment**. "Connected differently"
means the host interface is unknown, so the simulation is the baseline that
must work first; running the real ROM is an experiment to attempt afterwards,
with MAME's simulated behaviour as the reference for what the answers should
be. It would also be the first thing in this project with no oracle to check
against, which section 4.I's working method says to treat with suspicion.

**Risks and unknowns**

- **The raster is a guess upstream.** D does not use `set_raw`; it sets
  `refresh_hz(56.18)` with a comment saying it is "same as nmk16.cpp based on
  YT videos", against B/C's explicit `384 x 278` at 6 MHz (56.22 Hz). Running D
  on the B/C raster is a 0.07 % difference and is arguably better founded than
  MAME's figure, but it is an assumption either way and belongs in the open
  questions.
- **Two sets only**, both the same game, so the payoff is smaller than B's
  eight or C's seven.
- MAME marks neither set imperfect, which is reassuring.

**Sequencing.** D is built after B and C reach M4 and are swept on hardware.
That is a scheduling decision, not a scope one: adding a mode to a core that
already works is contained, while building three at once is how three things
end up half-finished. The two hooks that make the later addition cheap — the
per-mode decode table and the hard-wired-to-zero OKI bank register — go in from
the first commit, and are listed in section 2.4 because they constrain how B
and C are written.

**D's own gates**, mirroring the others: pixel-exact against MAME for a
two-layer scene and a sprite scene (M1); the ten-line protection verified
command by command, and the OKI bank verified by driving all eight banks and
comparing sample output (M2); golden-byte audits over the banked sample region
(M3); boots, plays and is swept on hardware with both sets (M4).

### 2.6 The feature set

Identical to NMK16 and Sand Scorpion, and mostly inherited wholesale: Aspect
ratio, Scandoubler Fx, Orientation (per game — cybattlr is ROT90), Flip screen
done **in the core** so it reaches every output, CRT Adjust on its own page,
DIP switches from the `.mra`, Pause, High scores, Cheats (seven slots), Autofire
(hidden unless the `.mra` opts in), Savestates with four slots, the MAME
keyboard map, and the direct-video menu split.

---

## 3. Milestones and gates

Each milestone ends with a stated, measured gate. "Sim passed" is never the
last word for anything touching the memory path, the park/resume path or byte
order — those need the board.

**M0 — Foundation.** Repo from the layout above; `bootstrap.sh` + `deps.lock`
pinning NMK16 and jt51; copy the verbatim set and prove the inherited unit
tests still pass; obtain the seventeen romsets; MAME oracle captures (attract,
scripted play, a DIP sweep) for at least avspirit (B) and 64street (C);
`gen_ms1bcd_mra.py` with the off-board load model, **covering all three modes
from its first version** — the generator is the one place where a mode is cheap
to add now and expensive to retrofit; decide and write down the clock plan and
the raster. **Gate**: the copied tests build and pass, `.mra`
part CRCs match the zips, the load model agrees with the generator, oracle
frames exist for all three modes, and **every set's `.mra` carries a real priority
PROM and a real MCU ROM** — present, correctly sized and CRC-matched, with
chimerab's documented substitution declared in the file (section 2.3).

**M1 — Video against MAME state.** The three tilemap layers, the sprite engine,
the priority resolver and the palette, driven from a MAME RAM dump through a
`video_state` harness. **Gate**: pixel-exact against MAME's own frame for, at
minimum, a 16x16-tile scene, an 8x8-tile scene, a scene with a non-default page
layout, a scene using all three layers with sprites both over and under them,
a sprite-split scene (control bit 8), and a flipped frame. Report non-blank
pixel counts beside every match.

**M2 — Full reference sim.** Both 68000s, YM2151, both OKIs, the protection MCU
running its real ROM, the three-level interrupt timer, and the latch protocol.
**Gates**: (1) main-CPU bus trace against MAME through boot; (2) frames
pixel-exact over the attract at a fixed offset for one B game and one C game;
(3) YM/OKI write counts within a few percent over the same span; (4) audio band
correlation >= 0.95 with **FM and each OKI isolated separately** — Sand
Scorpion's SS-10 is still open precisely because it was judged from a mix;
(5) the protection handshake verified command by command against MAME's MCU
trace, not merely "the game boots".

**M3 — Hardware-path sim.** Real `sdram.sv` + model, ioctl stream in loader
order, `TB_RAM_PER2=5`. **Gates**: golden-byte audits with 0 wrong for every
region; frames identical to the reference sim; under autoplay, main-CPU
`romwait` < 1 % per frame and the sprite pass comfortably inside a frame with
0 late swaps; savestate round trip pixel-exact after frame 0.

**M4 — Quartus and board.** `quartus_map` first as a RAM-inference probe (every
array a real M10K, no duplicate copies), then fit and timing. **Gates**: **no ROM or PROM data in the
bitstream** — no `$readmemh` outside an `HW_ROMS == 0` guard, no `.mif`/`.hex`
in the `.qip`, and the PROM's byte sequence absent from the `.rbf` (section
2.3); timing met with the worst path identified; boots to attract on the first
`.mra`;
native screenshots of static scenes byte-identical to the reference sim; a demo
frame with sprites pixel-identical (the byte-order check); audio correlation
against MAME >= 0.95 over 60 s; coin/start/play on keyboard **and** gamepad; all
seventeen `.mra` swept, all three modes.

**M5 — Feature parity and release.** Every OSD feature exercised on hardware by
its effect, using the `.CFG`/`.dip` harness rather than blind menu navigation;
Orientation proved on the HDMI path (the native screenshot cannot show it);
high scores proved by patching the `.nvm`; each cheat slot proved against
MAME-comparable behaviour; savestates proved by save, reload-core, load.
README, `docs/known-issues.md` numbered `MS1-n`, `docs/hw-bringup.md`, tracked
`.rbf`, tag, and publication through the kuzecores downloader database.

---

## 4. Lessons carried in, mapped onto this board

Everything here was paid for once already in NMK16 or Sand Scorpion. The
reference is given so the full evidence can be re-read.

### 4.A ROM loading, `.mra`, ioctl

1. **Gate every ioctl SDRAM write on `ioctl_index == 0`.** The `.mra` sends
   `<switches>` as a second session on index 254 with the address restarting at
   0; ungated it lands on the 68000's reset vector. NMK16's first black screen.
2. **The ROM loader must not be held in reset while it loads.** Sand Scorpion's
   SS-15 cost three bitstreams: the loader's request register is cleared by its
   reset, so *any* reset asserted during the transfer means not one byte
   reaches the SDRAM — and because `ioctl_wait` is suppressed too, the loader
   streams every byte at full speed and reports success. Two separate signals
   did it: `ioctl_download` and the framework's own `RESET`, which the HPS
   raises for the whole transfer. Give the loader a **power-on-only reset**.
3. **Index 254 arrives last**; nothing decided during the ROM stream may depend
   on it. The game-mode byte is read at run time only.
4. Region bases are 24-bit byte offsets. `23'h8C0000` silently lost bit 23 once
   and the second OKI played tile graphics for a week.
5. Byte order is a per-consumer decision; a title screen is not a sprite test.
6. `<buttons>` count and order is the gamepad's positional map and must equal
   the CONF_STR `J1` list.
7. `?` cannot appear in `.mra` file names (exFAT drops the copy silently).
8. `START_WAIT` for hiscore must outlast the game's RAM test.
9. **No ROM or PROM data in the bitstream** (NMK-22), enforced as section 2.3
   describes and checked at M0 and again at M4. The priority PROM streams as
   `<rom index="1">` into a write port with no initial contents; the 16 KB MCU
   ROM streams inside `<rom index="0">` as its own SDRAM region behind a cache.
   A `$readmemh` may exist **only** inside a `generate` branch guarded by
   `HW_ROMS == 0` for the reference sim. NMK16's own rule — keep `$readmemh`
   out of every hardware path — is the thing to grep for in review, because
   the failure is invisible: the core works perfectly on the developer's
   machine and ships game data inside the bitstream.
10. A saved `config/dips/<mra>.dip` overrides the whole `<switches>` value,
    third byte included.
11. **Every `.mra` must be well-formed XML.** Sand Scorpion shipped ten NMK16
    files and three of its own with a bare `&` or a `--` inside a comment;
    MiSTer's reader is lenient, the downloader database's is not, and those
    files lost every content-derived tag. Escape at generation time.

### 4.B SDRAM, caches, buses

1. 96 MHz controller, consumers on `clk_sys`, toggle-handshake CDC, `SDRAM_DQ`
   captured by exactly one register, each PLL output its own exclusive SDC
   clock group, `REFRESH_CYCLES(740)`.
2. `sdram_req` accepts on the **rising edge** of `req`; `sdram_arb` holds a
   served channel off until its `req` has been seen low.
3. **Throughput, not latency.** Three 4bpp tilemap layers plus sprites is more
   simultaneous demand than either previous core: budget separate ports per
   real-time layer, prefetch ahead, pair reads, and judge with a miss-paint
   debug mode and the sound-CPU write counters, never with frame diffs.
4. Speculative-fetch race: feed the caches the bus address only while the ROM
   select is asserted; registered `*_ready` flags are stale-high for one clock.
   **12 MHz is exactly the speed that exposed this** in raphero, and System C
   runs its 68000 at 12 MHz.
5. The 68000 needs the 16-pair prefetching cache; re-run the `romwait` audit
   after any port change.
6. **Two OKIs, so two `oki_rom_cache`s**, each with `stall` ANDed into its
   `cen`. jt6295 ignores `rom_ok`; Sand Scorpion shipped 37.6 % stale sample
   bytes for a week without it.
7. OKI clock and pin 7 straight from the driver (4 MHz here, both chips).
8. Unmapped reads return MAME's unmap value, never 0xFFFF.
9. A ternary chain with an unsigned concatenation evaluates unsigned and turns
   `>>>` logical: every mix term gets its own signed wire. With FM plus **two**
   OKIs the mix has three terms and the routing weights come from the driver.
10. If a watchdog exists, pausing the CPU must pause it too.

### 4.C Quartus, fit, timing

1. **Asynchronous reads of any array become flip-flops.** Sand Scorpion's
   SS-14: the sprite RAM's CPU read sat inside a byte-lane `case`, Quartus
   called it asynchronous, and the design needed 41,709 ALMs of 41,910 until
   the read was moved outside the case. Read all lanes every clock and select
   after the register.
2. **Two readers cannot share one array.** An M10K has two ports and one is the
   write. Duplicate the array explicitly and write both banks on the same
   clock. With three tilemaps, sprites and a palette all wanting CPU access
   *and* a video read, this will come up repeatedly.
3. A 16-bit array with byte-lane writes and a second read port is duplicated
   per port; use two 8-bit lane arrays.
4. The silent M10K cliff at ~539/553 blocks: Quartus 17 stops inferring the
   framework's own RAMs with no message. Watch the total.
5. `build_id.v` is written by the pre-flow script, which does **not** run under
   a direct `quartus_map`; a bitstream built that way is named for today and
   reports a week-old version in the OSD.
6. Check the fit report's RAM summary for `__N` twins and the entity table for
   a large *own* ALM count on a wrapper.

### 4.D Video correctness

1. **Bitmap coordinates**: the visible area starts at bitmap row 16, so tilemap
   source y = screen y + 16 + scroll y. NMK16 was displaced by its blanking
   widths for a week.
2. Use the full-width x in every wide-tilemap index.
3. Index sprite planes with a real offset, never a concatenation.
4. Registered header reads need a settle cycle per word — Sand Scorpion's
   sprite attributes all came from the previous word, invisible because the
   compared frames had no sprites.
5. Swap the sprite plane only at the vblank trigger; hold a finished pass.
6. The CPU can rewrite sprite/Object RAM while it is being walked; MAME's copy
   is instantaneous and ours is not. MS1 already **double-buffers Object RAM
   and sprite RAM twice over** in MAME (`m_buffer_*` and `m_buffer2_*`) — read
   that code before choosing a snapshot strategy, because it encodes when the
   hardware latches.
7. Tile codes wrap modulo the region's element count (NMK-25).
8. **Sprite order here is first-entry-frontmost**, the opposite of PANDORA.
   Priority comes from a PROM, not from intuition; read the semantics.
9. Nibble order: decode every graphics layout against MAME's `gfx_element` in
   Python before writing RTL.
10. Flip is rot180 of the readback coordinates over the whole visible window,
    with the prefetch lookahead direction-aware. "RTL flip == rot180(RTL
    no-flip)" is tautological; compare against MAME.
11. Compare demo frames **with sprites** at exact frame numbers; prove two
    frames are the same scene before diffing.
12. Boot-phase software timers land a few frames apart; align by a diff
    matrix's diagonal.
13. Native MiSTer screenshots are the right tool for pixel proofs but capture
    the video **before** the rotation framebuffer and without the OSD overlay.
14. **When pixels resist, read the driver line by line against the RTL.** For
    this board the candidates are: the scroll-register naming cross, the
    differing register order between B and C, the page-layout decode
    (`16 >> N`), the 8x8-vs-16x16 tile-size bit, the Object RAM flip-bank
    selection, the sprite-split colour groups, and the palette's interleaved
    non-RGB bit layout.

### 4.E Audio

1. **Isolate per source on both sides before trusting a mix number.** NMK16
   found an 8-13 dB error in one source hiding inside a correct aggregate;
   Sand Scorpion's SS-10 is *still open* because the only available comparison
   was a mix. Build the per-source taps into the testbench on day one — with
   three sources here (FM, OKI1, OKI2) a mix number is nearly meaningless.
2. MAME exposes **no per-device gain**: `set_output_gain` is not bound in Lua
   and the config's `<mixer>` carries the speaker map, not device volumes. Plan
   the MAME-side isolation method before M2, or the gate cannot be met.
3. `TB_DUMP_AUDIO` in every testbench from the start.
4. Trim silent intros; MAME renders silence for many seconds after reset.
5. A sound CPU that "plays but sounds subtly wrong" is a CPU flag bug until
   proven otherwise.
6. Beware the driver's own `SOUND_HACK`: the OKI status register is deliberately
   forced to 0, and doing so fixes some games and breaks others.

### 4.F Simulation harness

1. `HW_ROMS` as an additive parameter; hash the reference frames after every
   hardware-path change.
2. The hardware-mode testbench drives readback from the core's **live**
   counters and samples continuously.
3. Open dump files before the long loop; check a dump's format, not its
   existence; drive every clock enable of a standalone module's testbench (the
   TLCS-90 self-tests ran nothing for days — and this project reuses that very
   core, so re-run its self-tests after re-parameterising it).
4. `TB_CYCLES` counts clock cycles, not frames. Sand Scorpion's default stopped
   at frame 496 and silently truncated a 620-frame dump.
5. Never wait on a simulator with `pgrep -f <name>`: the waiting shell matches
   its own command line and a finished run looks like a hung one.
6. Never accept a rare-event counter reaching 0 without a per-event diagnostic.
7. MAME Lua traps: keep tap tokens in globals; `frame_done` fires at VBOUT;
   `screen:vpos()` is not exposed; prove an experiment applied before reading
   its result.
8. A control that fails in MAME too means the harness is broken, not the game.

### 4.G Board tooling and process

1. `SSH_ASKPASS` + `DISPLAY` + `< /dev/null`; `load_core` via
   `/dev/MiSTer_cmd`; wrap `screenshot` in `timeout`; a core switch takes ~15 s.
2. **The native screenshot has no OSD overlay**, so menus cannot be read back.
   Drive options through `config/<setname>.CFG` (the 128-bit status word, 16
   bytes little-endian) and `config/dips/<mra>.dip` (8 bytes), and judge each
   option by its effect. `tools/board_feature_test.py` already does this.
3. Use a **static screen** for any two-run pixel comparison; an attract mode
   never phase-locks between runs. A game's own service-mode test screen is
   ideal and doubles as a DIP-path proof.
4. Key holds shorter than ~0.5 s are unreliable for savestate hotkeys, and
   chords must be sent as chords.
5. Sweep every `.mra` with one script that logs a line per game.

### 4.H Feature-specific traps

- **Savestates**: the CPU park overlay must outlive the bus cycle that fetches
  the RTE (fx68k captures the data bus on every phi2 until the cycle ends) —
  board-only, never reproduced in Verilator. **Here there are two 68000s and an
  MCU to park**, which is strictly more than either previous project. Park and
  release at VBlank edges; a load waits extra VBlanks for the sprite buffers;
  `pause` masked while the engine runs; the DDRAM port is shared with
  `screen_rotate`; hiscore's RAM grant gated with `~ss_active`.
- **Hiscore**: `hiscore.v` ignores its reset for extraction/upload, has no
  synchronous reset, needs two reset windows, a faked OSD edge for Save Scores,
  a `START_WAIT` past the RAM test, and dump validation. The proof is patching
  the `.nvm`.
- **Savestate slot 2 is F5, not F2**, because F2 is the Service Mode toggle and
  the two collided in both previous projects (NMK-34).
- **Pause**: video keeps running, audio muted.
- **CRT Adjust**: VBlank sampled at each HSync rise for the *following* window;
  the ring wider than the line; Off must be bit-identical to native. Only
  Cabinet-mode V-Size changes the captured active area — the other controls move
  analog timing and a digital capture cannot show them.
- **Orientation/scandoubler**: `screen_rotate` has no backpressure, so the
  scandoubler must be off while the framebuffer is active (NMK-28).
- **Autofire**: pattern clocked by the game's vblank; hidden unless the `.mra`
  opts in.

### 4.I Working method

- Dump the **value**, not just the address.
- Isolate before trusting an aggregate.
- Do the ratio check first: a CPU paused 1 % of the time that executes 0
  instructions is stalled, not starved.
- **A counter that is cleared by the signal under investigation measures
  nothing.** Sand Scorpion's first on-screen diagnostic read zero for the
  download counters because they lived inside the block held in reset; a
  healthy download would have read zero too.
- Every retracted conclusion in both projects traced to comparing frames that
  were not the same scene, or to a probe not proven to apply.
- Ship only what was measured; write the number and the method next to the
  claim; keep retractions in the record.

---

## 5. Open questions to settle in M0 (each is a measurement, not a guess)

1. **Does the `iosim` protocol suffice, or is the real MCU required?** MAME
   moved every dumped game to the real MCU. Run both against the same oracle
   capture and diff. This decides whether the TLCS-90 core is on the critical
   path or a refinement.
2. **The `SOUND_HACK`.** Does the real board's OKI status register read 0?
   Emulate it faithfully first and measure which games misbehave; the bootleg
   patch is evidence, not proof.
3. **The raster.** `384 x 278` is explicit, but the source carries a
   commented-out `406 x 263` alternative. Which did the board use? A PCB
   measurement settles it; until then 384 x 278 is the documented default and
   every timing-dependent number hangs off a parameter.
4. **Priority PROM at load time or per pixel?** Converting once is cheaper per
   pixel but assumes the layer-enable set is stable within a frame; the enable
   register is written mid-frame by `active_layers_w`, which calls
   `update_partial`. Measure how often, then choose.
5. **chimerab's missing priority PROM.** MAME substitutes 64street's. Confirm
   by comparison, and record it as a substitution in the `.mra`.
6. **Sprite/Object RAM double buffering.** MAME keeps two levels. Establish
   from the driver when the hardware latches each, and whether the 68000 can be
   allowed to write during the walk.
7. **The 7 MHz sound domain.** Accumulator from 48 MHz, or a second PLL output?
   Decide with the same reasoning Sand Scorpion used for its exact dividers.
8. **hayaosi1's `MACHINE_IMPERFECT_GRAPHICS`.** What is imperfect, and will it
   look like our bug? Establish the known-bad baseline before comparing.
9. **Which raster does System D use?** D does not use
   `set_raw` at all — MAME sets 56.18 Hz from video footage, while B and C get
   an explicit 384 x 278 at 6 MHz (56.22 Hz). Sharing the B/C raster is a
   0.07 % difference and better founded than the upstream guess, but it is
   still an assumption and should be measured on a PCB alongside question 3.

---

## 6. What I would do first

1. Scaffold the repo and `bootstrap.sh`; copy the verbatim set from NMK16 and
   **re-run its unit tests, including the TLCS-90 self-tests**, before changing
   anything.
2. Write `gen_ms1bcd_mra.py` from one table and its off-board load model, for
   all seventeen sets across all three modes. Generate, check part CRCs against
   the zips, and check each mode's region bases against its intended map —
   before any RTL.
3. Capture the MAME oracle for avspirit (B), 64street (C) and peekaboo (D):
   exact-frame
   snapshots, VRAM/Object RAM/palette/register dumps at chosen frames, a
   main-CPU bus trace through boot, and an MCU command trace. Capturing D's
   oracle now costs an afternoon and means the mode can be built later without
   re-entering the driver.
4. Re-parameterise `tlcs90.sv` for the TMP91640's 16 KB/512 B and run it
   standalone against MAME's MCU trace. This is the one genuinely new CPU
   integration, it is mostly already done, and it gates M2.
5. Only then start `ms1_tilemap.sv`, against a `video_state` harness, one layer
   at a time.

---

*Nothing in this document has been measured on this board. Every number comes
from MAME's driver or from the two finished projects it is modelled on.*
