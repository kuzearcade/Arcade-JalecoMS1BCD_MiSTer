# Hardware bring-up — the MiSTer top level

`docs/PLAN.md` M4: "the core becomes a .rbf". This is the record of that
build. **Nothing here has been on a DE10-Nano yet** — every number below comes
from Quartus, not from a board.

## What was built

| file | what it is |
|---|---|
| `MS1BCD.sv` | the `emu` top level, 730 lines |
| `JalecoMS1BCD.qpf` / `.qsf` | the Quartus project |
| `JalecoMS1BCD.sdc` | timing constraints |
| `files_ms1bcd.qip` | the file list — **add files here, never in the IDE** |

Adapted from `Arcade-SandScrp_MiSTer/SandScrp.sv`, which is itself adapted from
`Arcade-NMK16_MiSTer/NMK16_Macross2.sv`. The OSD layout, keyboard map,
autofire, savestate and CRT Adjust wiring come from there unchanged.

One `.rbf` covers all 17 romsets. `<rbf>JalecoMS1BCD</rbf>` in every `.mra`
matches the project revision, so the output file name is already right.

## Result

```
Analysis & Synthesis   Successful,  0 errors
Fitter                 Successful
TimeQuest              no violations
Assembler              JalecoMS1BCD.rbf, 4,291,788 bytes
```

| resource | used | of | |
|---|---:|---:|---:|
| Logic (ALMs) | 27,132 | 41,910 | 65 % |
| **M10K blocks** | **537** | **553** | **97 %** |
| Block memory bits | 4,084,095 | 5,662,720 | 72 % |
| DSP blocks | 51 | 112 | 46 % |
| Pins | 145 | 314 | 46 % |

| clock | worst setup slack |
|---|---:|
| `clk_sys` (48 MHz) | +4.116 ns |
| `clk_ram` / `CLK_VIDEO` (96 MHz) | +1.732 ns |
| `pll_hdmi` | +0.460 ns |

Worst case across the whole design: setup +0.460, hold +0.248, recovery
+3.851, removal +0.653, minimum pulse width +1.041.

## 537 of 553 M10K is the headline, and it is not comfortable

`docs/known-issues.md` MS1-37 closed with the core alone at 332 of 557 and
this sentence: *"225 left for the framework, and docs/PLAN.md 4.C.4 records a
silent cliff near 539/553 where Quartus stops inferring the framework's own
RAMs with no message at all. The number to check is the total after `sys/` is
added."*

The number is **537**. Two blocks under the cliff.

So the design fits, and it fits with essentially nothing to spare. That is the
constraint every later decision runs into:

- **MS1-39's four deferred OSD features are not free.** `hiscore.v` wants a
  RAM for its config table and cheats wants another. They may simply not fit,
  and finding out is part of M5 rather than an afterthought.
- Anything that adds a buffer, a cache line or a savestate region has to come
  out of 16 blocks.
- If a future change goes one block over, the symptom will not be an error.
  It will be `sys/` quietly turning its own RAMs into registers and the ALM
  count exploding. **Read `Total RAM Blocks` after every fit.**

## Three things the first fit taught

**1. The protection MCU is a multicycle island (MS1-43).** The first fit failed
at -13.703 ns, TNS -178.678, and all twelve worst paths were the same pair
inside `tlcs90:u_cpu`. Its whole datapath sits under one `if (cen)`, and `cen`
fires once per 4 (System C) or 6 (System B/D) `clk_sys` cycles. Constrained as
the multicycle it is: `clk_sys` went to +3.901.

**2. The mode byte is configuration, and had to be made so (MS1-44).** Next
were paths from `dip_sw[2][1]` — `mode` — into that same MCU, at -2.153.
`mode` fans out further than anything else here. Declaring `dip_sw` a false
path is only *true* because `reset` now covers the download plus a 255-cycle
settling tail; without that RTL change the constraint would have been a lie.

**3. The seed mattered, because the device is full.** At the default seed the
core's own clocks passed with margin but MiSTer's own HDMI scaler missed by
-0.195 ns — `ascal|o_hcpt`, on `pll_hdmi`. Not a constraint bug and not ours to
restructure: the far emptier SandScrp project passes that same path at +0.495.
With 537 of 553 M10K placed, the fitter has little room left for `sys/`. Seed
11 closes it.

The first two are real constraint work. The third is a reminder that at 97 %
occupancy, *the framework's* timing becomes this core's problem.

## What the top level does NOT wire

Deliberately absent from the CONF_STR rather than wired to constants — an OSD
entry that does nothing reads as broken, not unfinished:

| feature | why | issue |
|---|---|---|
| Pause | no clock-enable gate on the core | MS1-39 |
| High Scores | no work-RAM back door | MS1-39, **closed** |
| Cheats | same back door | MS1-39, **closed** |
| Flip Screen | no `osd_flip` input | MS1-39, **closed** |

Autofire is hidden (`h1`) unless the loaded `.mra`'s third `<switches>` byte
sets **bit 7**, and `tools/gen_autofire_mra.py` writes the
`autofire_releases/` tree that sets it -- the same two-tree arrangement the
sibling cores use.

**Bit 7, where the siblings use bit 6.** On this board that byte is the
game-mode byte and bits 6:5 are the protection field, so setting bit 6 would
not unlock a menu: it would tell the core the game has a different protection
device, hold the real MCU in reset and break it. The layout is `[1:0]` mode,
`[4]` sample clock, `[6:5]` protection, with `[3:2]` and `[7]` spare. The
generator was inherited from NMK16 and still set bit 6 until it was rewritten
for this core; running the old one against this `releases/` tree would have
been actively harmful, not merely useless.

Measured on the board: `cybattlr` with byte 2 = `01` and with `81` renders the
same attract, 57084 lit pixels either way, so the unlock bit is inert to the
mode, protection and sample-clock decode. The menu's *visibility* is not
screenshot-testable -- MiSTer's `screenshot` captures the core's video without
the OSD overlay -- so that half rests on the `h1` prefix and
`status_menumask` bit 1 being wired to `dip_sw[2][7]`, which is a two-line
path.

Only the three shoot-'em-up families get a copy (`Cybattler`, `Chimera Beast`,
`E.D.F.`, with their `_alternatives`). Autofire costs button 3 for the player
using it, which is a bad trade on a belt-scroller, a football game, a quiz
panel or a paddle game.

## Inputs: three layouts from one byte

The game-mode byte identifies the board, and that turns out to be enough to
pick the input layout too — no new `.mra` field:

| layout | selected by | covers |
|---|---|---|
| peekaboo | `mode == D` | both System D sets, and only those |
| hayaosi1 | `mode == B && prot == 1` | the only simulated-protection System B set |
| generic | everything else | the other 14 |

`chimeraba` is the other `iosim` set and is System C, so the hayaosi1 test is
exact.

The generic layout's direction order is right/left/down/up, which is the MiSTer
pad's own bit order — so unlike Sand Scorpion, nothing has to be reversed.

The two special layouts are both lossy: MS1-41 (hayaosi1's buttons 4/5 and
player 3) and MS1-42 (peekaboo's 16-bit SYSTEM port). Both are recorded rather
than hidden.

## Video and audio

- Raster 384 x 278 at 6 MHz, visible 256 x 224 from row 16 — 56.2 Hz. 278 is
  `video_retime`'s *default* `VTOTAL_P`; this is the raster that parameter was
  written for.
- `LINE_CLKS` 6144 and `DIV` 16: 96 MHz / (6 MHz / 384).
- `CLK_VIDEO` is `clk_ram`, not a third PLL — a second 96 MHz altpll from the
  same reference would just be merged by the fitter.
- Stereo. `ms1_sound.sv` pans the YM2151 and the two OKIM6295s as MAME's
  machine configuration does, so `AUDIO_L` and `AUDIO_R` differ.
- `oki_status_real` is tied 0: MAME returns 0 from both OKI status registers,
  and every audio measurement in this project was taken against that. Whether
  real silicon agrees is MS1-31, which only a PCB can settle.

## Savestates

`SS_WORDS` 0x30000 (the image `docs/m3-gate4.md` maps), `SLOT_STRIDE`
0x10000 64-bit words = 0x80000 bytes per slot, four slots from 0x3E000000, and
`CONF_STR` says `SS3E000000:80000` to match. `RD_LAT` 3 is the latency
`sim/rtl/ms1_frames/tb_frames.cpp` streams the image at — three ticks between
`ss_addr` and the `ss_rdata` it samples — so the engine sees exactly what every
round-trip measurement so far has seen.

MS1-33 (a 25-pixel residue after a restore) is still open and is not a
bring-up problem.

## Benign build noise

- `Warning (125092): Tcl Script File rtl/pll.qip not found` — `sys/pll_q17.qip`
  references it, for cores whose PLL is MegaWizard IP with a `.qip`. Ours is a
  hand-written altpll in `rtl/pll.v`, listed directly. The sibling projects
  carry the same warning.
- `Found 9 instances of uninferred RAM logic` — seven are small constant LUTs
  inside jt51/jt6295 ("inappropriate RAM size"), which is what they should be,
  and two are `oki_rom_cache|pair`, a deliberately small fully-associative
  register file. None is an MS1-37 regression.

## Next

`build_id.v` is generated by `sys/build_id.tcl` as a pre-flow script, so it
only appears under `quartus_sh --flow compile`. Running `quartus_map` alone
fails with `can't open Verilog Design File "build_id.v"` until one full flow
has run.

The bitstream is at `releases/Arcade-JalecoMS1BCD_20260923.rbf`: 69 % of the
ALMs, **544 of 553 M10K**, **0 timing violations**. It carries System D
(MS1-56), the lookahead fix (MS1-57), the video alignment fix (MS1-59) and
the four OSD features (MS1-39).

MS1-39 is what made the M10K figure tight: 538 -> 544, nine blocks spare. The
cost is not the high-score and cheat engines themselves -- their tables are
too small for an M10K and land in LUTs -- but the byte-lane write the back
door needs on `wram`/`wram_s`. Both still infer as `altsyncram`; that was
checked with `quartus_map` alone before committing to a full compile, which is
what MS1-38 exists to say.

**All 16 shipped sets boot on the board** — System B 7 of 7, System C 7 of 7,
System D 2 of 2 — and the picture is now bit-identical to MAME's: MS1-59 had
the whole frame five columns to the right, with the previous line's tail in
the gap, on every game. The remaining M4 gates are audio correlation, the input
sweep and savestates on hardware, all of which need the board and none of
which is a bring-up problem.
