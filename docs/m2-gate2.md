# M2 gate 2 — frames over the attract  (NOT MET)

`docs/PLAN.md` M2 gate (2): "frames pixel-exact over the attract at a fixed
offset for one B game and one C game".

**This gate is not met.** What follows is where it actually stands, because
the parts that are finished are worth more than the headline.

## What works

`rtl/ms1bcd/ms1bcd_core.sv` wires `ms1_main` (68000, decode, interrupt timer,
protection MCU) to `ms1_video` with a real 384x278 raster, and the whole thing
runs avspirit from reset through boot into the attract mode. Four independent
checks say the pieces are right:

1. **The video state is byte-identical to MAME's.** Dumping the sim's own
   layer VRAM, palette and object RAM at frame 150 and comparing with MAME's
   capture at its frame 150:

   | region | RTL non-zero | MAME non-zero | identical |
   |---|---:|---:|:--:|
   | layer 0 VRAM | 0 | 0 | yes |
   | layer 1 VRAM | 0 | 0 | yes |
   | layer 2 VRAM | 7344 | 7344 | **yes** |
   | palette | 201 | 201 | **yes** |
   | object RAM | 2040 | 2040 | **yes** |
   | sprite RAM | 288 | 286 | no |

2. **The protection handshake matches MAME exactly for 131 transactions** --
   the identification sequence (06->06, FF->F2, 06->69, 06->06) and the input
   commands 0x37/0x35/0x36/0x34/0x33 with their answers, including DSW2
   returning 0xFC and DSW1 0xFF. The 132nd differs only by an extra poll: the
   game reads a stale 0xFF once before the MCU's answer lands, then re-reads
   and gets the right value. That is a latency difference, not a wrong value.

3. **The video RTL renders the sim's own state correctly.** Feeding the dump
   from (1) through `sim/rtl/video_state` -- the M1 harness, which is
   pixel-exact against MAME -- gives MAME's frame with **0 differing pixels**.

4. The scroll register tracks MAME frame for frame (`t0_sx` 0x0000/0x001E/
   0x003C against MAME's 0x0001/0x001F/0x003D at frames 60/90/120), so the
   game logic is running in step.

## What does not

The integrated core's frames do not match. The difference traces to
`screen_flag` bit 0 -- screen flip -- being **1** in the sim's register file
and **0** in MAME's captured register shadow at the same frame. A flipped
frame is a 180-degree rotation (MS1-13), which is exactly the symptom: content
present, in the wrong place, about the right amount of it.

The unresolved part is that MAME's own two oracles disagree about this
register:

* `sim/oracle/ms1_bustrace.lua` records the game writing `0x0001` to
  `0x044300` **245 times** over 1.5M accesses (and `0x0000` 5 times, `0x0010`
  once). The RTL writes the same three values in the same order -- 5x 0000,
  1x 0010, then 0001 repeatedly -- so the CPU is doing what MAME's CPU does.
* `sim/oracle/ms1_capture.lua`, which shadows writes to the same address over
  the same window, reports `screen_flag = 0000` at every frame from 0 to 1100.

Both taps are on address `0x044300` in the same address space of the same
game. They cannot both be right, and until that is settled there is no
trustworthy reference for what the flip bit should be, so there is no point
comparing frames against it.

**Next step**, and the only sensible one: reconcile the two oracles before
touching the RTL again. The likely candidates are that the two captures do not
start counting at the same moment (the bus trace taps from the first access,
the frame capture from the first `frame_done`), or that the register-window
tap in `ms1_capture.lua` is being shadowed by something else at the same
index. Both are checkable in minutes with a single MAME run that logs both.

## Bugs fixed on the way here

| where | bug |
|---|---|
| `ms1_main.sv` | one interrupt-acknowledge CYCLE retired every pending interrupt instead of one (MS1-23) -- IRQ 1 and the protection's IRQ 2 were raised and discarded, and the game sat in its `STOP` loop forever |
| `ms1_main.sv` | sprite RAM read from work-RAM word 0x1000 instead of 0x4000 (it is work RAM + 0x8000 BYTES) |
| `ms1_sprites.sv` | the display readback was clocked on `clk` rather than the pixel `ce`; invisible when `ce` is tied high, as in `video_state`, and wrong as soon as it is not |

## Also learned

MS1-24: the protection MCU needs about **48 frames** of board time before it
answers anything, and the game does not turn its layers on until about frame
100. A frame comparison that runs 40 or 60 frames sees a black screen and
concludes the video is broken. It is not; the game has not drawn yet. Two
separate hours went into that here.
