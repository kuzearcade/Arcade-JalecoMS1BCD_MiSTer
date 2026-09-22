# M4 — allocation plan for the video arrays

MS1-37's remaining work. Written before any RTL changes, because the last
attempt was made one array at a time and went backwards: pipelining the buffer
copies fixed one array and cost four others their inference. RAM inference is a
global allocation problem and has to be decided as one.

Device: Cyclone V 5CSEBA6U23I7, **557 M10K blocks** (5570 Kbit). An M10K has
two ports and one of them is the write, so **one read + one write per copy**.

## The five arrays, and every site that touches them

All five have the same shape: two writes in one mutually-exclusive block, and
three reads.

| array | write (CPU) | write (savestate) | read A | read B | read C |
|---|---|---|---|---|---|
| `vr0` | 298 | 285 | 363 tilemap (comb) | 480 CPU (comb) | 330 savestate (reg) |
| `vr1` | 299 | 286 | 364 tilemap | 481 CPU | 331 savestate |
| `vr2` | 300 | 287 | 365 tilemap | 482 CPU | 332 savestate |
| `pal` | 296 | 288 | 366 palette (comb) | 478 CPU (comb) | 333 savestate (reg) |
| `obj` | 297 | 290 | 401 buffer copy | 479 CPU (comb) | 335 savestate (reg) |

**Concurrency.** The savestate read happens only while `ss_active`, and the
core is parked then, so read C is mutually exclusive with A and B. Reads A and
B are **genuinely concurrent**: the video runs every pixel and the CPU runs
continuously.

So each array needs **exactly two copies**, not three:

- **copy V** -- the real-time consumer (tilemap / palette / buffer copy), one
  registered read;
- **copy C** -- the CPU read and the savestate read, muxed on `ss_active`, one
  registered read.

Both copies take the same write on the same clock, exactly as `wram` and
`wram_s` already do.

## Block budget

| | copies | bits each | blocks |
|---|---:|---:|---:|
| `wram` | 2 | 512 Kbit | 104 |
| `vr0`, `vr1`, `vr2` | 2 each | 128 Kbit | 78 |
| `pal` | 2 | 16 Kbit | 4 |
| `obj` | 2 | 64 Kbit | 14 |
| `obj_b1/b2`, `spr_b1/b2` | 1 each | 64 Kbit | 28 |
| `sram` | 1 | 512 Kbit | 52 |
| sprite `plane` | 1 | 576 Kbit | 58 |
| `vreg`, `iram`, `ymsh` | 1 each | small | 3 |
| **core total** | | | **~341 of 557** |

That leaves ~216 blocks for the MiSTer framework. Worth watching against
docs/PLAN.md 4.C.4: Quartus 17 has a silent cliff near 539/553 blocks where it
stops inferring the framework's own RAMs **with no message at all**. The count
to check is the total after `sys/` is added, not this one.

## The re-timing, which is the actual work

Registering copy V's read moves its data one cycle later. Each consumer has to
absorb that:

**1. `vr0`/`vr1`/`vr2` -> `ms1_tilemap`.** Stage 0 registers `vram_addr`;
stage 1 consumes `vram_data`. With a registered read the data lands a cycle
late. Add a `VRAM_LAT` parameter that delays the stage-0 outputs (`fx0`, `fy0`,
`sub0`, `eight0`, `v0`) by one, so stage 1 sees address and data together.
This is the same shape as the existing `FETCH_LEAD`, which is already proven.

**2. `pal` -> `ms1_video`.** The palette lookup feeds the final RGB. The
`vpipe` validity chain grows by one stage, and `rgb_valid` with it.

**3. `obj` -> the buffer copy.** The copy reads `obj` and writes `obj_b1` in
the same cycle, which is what reads as an asynchronous read. With `obj` copy V
serving only the copy, it has one read and one write, so it may infer as-is --
**this must be checked before assuming a pipeline is needed**, because adding
one there is exactly what cost four arrays last time.

## Order of work, and what proves each step

Smallest re-timing risk first, frame comparison after every step:

1. `pal` -- two blocks, one pipeline stage. Re-run frames.
2. `obj` -- check whether copy V infers without a pipeline. Re-run frames.
3. `vr0`/`vr1`/`vr2` -- the real work, one layer at a time so a regression is
   attributable. Re-run frames after each.
4. Re-run **M1 gate** (`video_state`) and **M2 gate 2** (frames against MAME,
   both B and C). Pixel-exactness against MAME is the only thing that can show
   the re-timing is right; the internal frame comparison only shows it is
   self-consistent.

## Two traps already paid for

- **A fix for one array can cost another its inference.** Check the full
  inferred list after every step, not just the array being worked on.
- **A restore or a copy in an `always` block of its own is a second driver.**
  It must live in the block that owns the array. MS1-34, which has now
  appeared five times.
