# M3 gate 4 — savestate round trip  (NOT MET)

`docs/PLAN.md` M3 gate: "savestate round trip pixel-exact after frame 0".

## Result

Save at a frame boundary, run 8 frames (span A), restore, run the same 8
frames (span B), compare.

| frame after restore | differing pixels | lit pixels |
|---|---:|---:|
| 0 | **0** | 1812 |
| 1 | **0** | 1812 |
| 2 | **0** | 1812 |
| 3 | 497 | 4741 |
| 4-7 | 25 each | 4741 |

**The gate is not met.** Frames 1 and 2 are exact; from frame 3 -- the moment
the game draws a new scene -- one 14x7 glyph at x 153-166, y 201-207 is wrong
and stays wrong. Frame 0 is exact, which the gate does not even require.

## What is built and verified

The core exposes its whole state on a flat 16-bit bus while every CPU is
parked: 0x30000 words covering work RAM, three scroll VRAMs, palette, object
RAM, video registers, the four object/sprite double-buffers, sound RAM, the
sprite plane, the MCU's internal RAM, both 68000s' park registers, the
TLCS-90's and its peripheral's register files, the YM2151 register shadow, the
raster, and the scalar state of every block.

Both 68000s park with `ss_m68k_park`, which needs an unmapped window for its
monitor overlay: **0x0C0000** is free on System B (above rom1's
0x80000-0xBFFFF, below the protection port at 0xE0000) and on System C (below
`c_vreg` at 0xC2000); the sound CPU uses **0x020000**, between its ROM and its
latch. The TLCS-90 and `nmk004_periph` already carried savestate register files
from the NMK16 lineage, so the MCU needed only its RAM and a few scalars.

**The image itself is proven sound.** A loopback -- park, stream out, stream
the same image back in with the core never running, stream out again --
reports:

```
loopback: 0 of 196608 words differ
every region reads back exactly what was written
```

## What is wrong, as far as it is measured

See **MS1-33**. The short version: state is bit-identical for three frames
(measured without parking, which matters -- see MS1-35), then `vram2` differs
in exactly two words, the first being tile code `F034` against `F030`. One
character cell, four apart: a counter showing a different digit.

Three candidate causes were fixed and none changed the result by a single
pixel: the sprite blit FSM's 29 fields, `mcu_data` (the protection answer the
main CPU reads back), and the `iack_d` / `slatch_d` / `prot_we_pulse` edge
detectors. Each was a genuine gap in the image and each fix is kept; none is
the cause. The sound side is excluded by construction -- `latch_to_main` is
unconnected in `ms1bcd_core`, so the YM2151's unrestorable internal phase
cannot reach the video.

The next step is written down in MS1-33: pin the divergence to a single frame
at K=4, and add the sprite plane and the four object/sprite buffers to the
non-invasive probe's comparison list. They are captured and restored, but the
probe does not currently compare them, so a difference there would be
invisible.

## Two findings worth more than the gate

**MS1-34**: a savestate restore written in its own `always` block does nothing
at all, and Verilator does not warn. This happened four times in this milestone
before it was understood. Every restore now lives inside the block that owns
its register.

**MS1-35**: the first divergence probe parked the CPUs to observe them, and
reported divergence after one frame -- all of it stack tops and clock phases
disturbed by the parking itself. Reading the model's arrays directly reports
the same runs bit-identical. A savestate probe must not use the savestate
mechanism to observe, because that mechanism perturbs precisely what a
savestate is most likely to get wrong.
