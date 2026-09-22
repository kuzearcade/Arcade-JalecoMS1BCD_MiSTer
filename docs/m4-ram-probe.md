# M4 — the RAM-inference probe  (GATE NOT MET)

`docs/PLAN.md` M4 opens: "`quartus_map` first as a RAM-inference probe (every
array a real M10K, no duplicate copies), then fit and timing."

`quartus/ram_probe.qsf` is that probe: `ms1bcd_core` as the top entity with no
MiSTer framework around it, so the report is about the core's own arrays and
nothing else. Quartus Prime 17.0.0 Lite, device 5CSEBA6U23I7.

## Result

Synthesis **fails**:

```
Error (276003): Cannot convert all sets of registers into RAM megafunctions
when creating nodes. The resulting number of registers remaining in design
exceeds the number of registers in the device
```

| | arrays |
|---|---|
| inferred as M10K | `sram`, `obj_b1`, `obj_b2`, `spr_b1`, `spr_b2` |
| **not inferred** | `wram`, `vr0`, `vr1`, `vr2`, `pal`, `obj`, `vreg`, `iram`, `ymsh` |

Roughly 1 Mbit of storage became flip-flops on a device with about 83000 of
them, which is what the error is reporting.

The five that inferred have **exactly one read and one write** each. The nine
that did not each break one or both of the two rules the plan already names.

**4.C.1 -- an asynchronous read of any array becomes flip-flops.** These are
combinational reads inside `always @*`:

```systemverilog
v0_rd_data  = vr0[v0_rd_addr];        // ms1_main.sv:333
pal_rd_data = pal[pal_rd_addr];       // ms1_main.sv:336
din = iram[addr[8:0] - 9'h1C0];       // ms1_iomcu.sv:179
rdat = wram[wram_i];                  // the CPU read mux
```

**4.C.2 -- two readers cannot share one array.** An M10K has two ports and one
of them is the write:

| array | readers |
|---|---|
| `wram` | CPU read mux, savestate readback |
| `vr0`/`vr1`/`vr2` | video read port, CPU read mux, savestate readback |
| `pal` | video read port, CPU read mux, savestate readback |
| `obj` | CPU read mux, savestate readback, the buffer copy |

## What this costs, honestly

This is not a small fix, and the design anticipated it in the wrong direction.
`ms1_main.sv` carries this comment on the video read ports:

> COMBINATIONAL on purpose: ms1_tilemap and ms1_sprites register their ADDRESS
> and expect the data in the following cycle ... Making these registered
> instead would insert a second cycle of latency and quietly shift every fetch
> by one.

That is correct about the consequence and wrong about the conclusion: on
hardware they cannot stay combinational. So M4 requires

1. **registering every array read**, and re-timing each consumer for the extra
   cycle -- the tilemap fetch, the sprite fetch, the palette lookup and the
   CPU read path;
2. **duplicating arrays per reader** (4.C.3), writing every copy on the same
   clock, so each copy has one read and one write.

Both changes alter the video pipeline, so **M1 and M2 gate 2 must be re-run
afterwards** -- pixel-exactness against MAME is the only thing that can show
the re-timing was done correctly. That is the real cost here: not the edit, the
re-validation.

## Found on the way in

Three defects that Verilator accepts silently and Quartus rejects:

| | |
|---|---|
| `{18'd0, fy0, 2'd0}[20:0]` | a part-select applied to a concatenation; Quartus 17's parser refuses it |
| `u_video.o0`, `u_video.o2` | a hierarchical reference INTO a submodule for debug counters; unresolvable in synthesis |
| `iram`, `latch_to_main`, `latch_from_main`, sound IRQ latches, `chip_din`, `chip_a0`, `ym_reg_sel`, `ymdiv`, `okidiv` | multiple drivers -- savestate restores written in their own `always` blocks |

That last row is **MS1-34 again**, instances four through twelve. MS1-34 records
that Verilator does not warn and that only structural care catches it. That was
wrong: `quartus_map` catches the entire class in seconds and refuses to
elaborate.

```
Error (10028): Can't resolve multiple constant drivers for net "iram[0][7]"
Error (10029): Constant driver at ms1_iomcu.sv(162)
```

The tool that would have caught all of it existed throughout M3. It was not run
because synthesis sat behind a milestone boundary. **Synthesis is a linter and
should be run opportunistically from M1 onward, not saved for M4.**


---

## 2026-09-22: partial progress, and one change reverted

Inferred now: `sram`, `vreg`, `obj_b1`, `obj_b2`, `spr_b1`, `spr_b2`, and
`wram` (which no longer appears in the uninferred list). Error (276003) still
stands, so the gate is still not met.

### What worked

**`vreg` -- stop making it a RAM.** It had 26 constant-index reads across the
two board modes, which nothing can serve. The 14 live video registers are now
shadowed into flip-flops on write (224 FFs), leaving the array one reader. The
shadow follows BOTH writers, the CPU and the savestate restore; following only
the CPU would have made a loaded state show the previous scroll.

**`wram` -- registered read plus duplication.** A single registered read port
serves the CPU and the savestate, which never run together. Quartus then still
refused it, naming a reader that had been missed: the sprite-RAM buffer copy,
since sprite RAM lives at work-RAM word 0x4000 and the copy runs during vblank
while the CPU is executing. Two copies, written on the same clock, fixed it.

**DTACK held one clock** for the now-registered read. The 68000 runs at 8 MHz
from 48, so a bus cycle is about 24 `clk_sys` and one clock does not lengthen
it. Verified, not assumed: 70 of 70 frames identical, 16 with content.

### What did not, and was reverted

The four buffer copies read one array and write another in the same cycle,
which counts as an asynchronous read. Pipelining them -- each source registered
on one clock, written on the next -- fixed `wram_s` and **cost inference on
`obj_b1`, `obj_b2`, `spr_b1` and `spr_b2`**, because registering `obj_b1` and
`spr_b1` there gave each of them a second reader. Inferred arrays went from six
to two. Reverted; one uninferred array is cheaper than four.

Raising `MAX_NUMBER_OF_REGISTERS_FROM_UNINFERRED_RAMS` did not help either. The
binding constraint is the device's register count, not the assignment.

### The lesson, which changes how the rest should be done

**Fixing one array can cost another its inference.** RAM inference is a global
allocation problem, not a list of independent defects, and it was being worked
as the latter: change one thing, re-synthesise, react to whichever message
moved. That works for isolated bugs and fails here.

Read sites per array, counted from the source:

| array | read sites | disposition |
|---|---|---|
| `wram`, `wram_s` | 2 each | done -- duplicated per reader |
| `vreg` | 0 (shadowed) | done |
| `vr0`, `vr1`, `vr2` | 4 each | video + CPU + savestate: duplicate, and re-time the tilemap |
| `pal`, `obj` | 4 each | duplicate, and re-time |
| `obj_b1/b2`, `spr_b1/b2` | 4 each | interdependent: the copy chain both reads and writes them |
| `iram` | 7 | MCU's combinational read; the MCU's `cen` is 1-in-6 so a registered read has room |
| `plane`, `ymsh`, `sram` | 3-4 | registered read |

The remaining work should enumerate every reader of every array, decide the
whole allocation (duplicate / register / restructure) **before** editing, and
only then change the RTL -- with the frame comparison re-run after each step,
since the video ones alter pipeline timing and M1 and M2 gate 2 are the only
things that can show the re-timing is right.


---

## 2026-09-22 (later): twelve arrays inferred, six to go

Synthesis now reports **Successful**, which is NOT the same as fitting. Error
(276003) no longer fires, but the resource summary says:

```
Dedicated logic registers   996504      (device has about 83000)
Combinational ALUTs         986368
Block memory bits          1826561
```

Inferred as `altsyncram` (12): `wram`, `wram_s`, `pal_v`, `pal_c`, `obj_v`,
`obj_c`, `obj_b1`, `obj_b2`, `spr_b1`, `spr_b2`, `sram`, `vreg`.

**Still flip-flops (6)**: `vr0`, `vr1`, `vr2`, `plane`, `iram`, `ymsh`. Their
bits come to 393216 + 589824 + 4096 + 2048 = 989184, which matches the reported
register count almost exactly. The fitter would still fail.

### The pattern that works, applied five times

One registered read per copy, address muxed between readers that are mutually
exclusive; duplicate only where readers are genuinely concurrent. Registering
on `clk` rather than on `ce` is what makes it free: an address that only
changes on a pixel enable has eight clocks of slack, so the data is valid one
clock later and seven clocks before it is used. **No re-timing was needed
anywhere**, and the `VRAM_LAT` / `vpipe` work this plan budgeted for did not
have to happen.

Frames were re-checked after every single step: 70 of 70 identical, 16 with
content, every time.

### Why the buffer chain failed the first time

Each of `obj_b1`, `obj_b2`, `spr_b1`, `spr_b2` has two readers -- the copy
sweep and the savestate readback. The first attempt registered the copy read
and left the savestate read alone, making three ports, which is why four arrays
LOST inference. Replacing both with one muxed registered read fixed all four,
and `wram_s` with them.

### Remaining

| array | bits | readers |
|---|---:|---|
| `vr0`, `vr1`, `vr2` | 128K each | tilemap (comb), CPU (comb), savestate |
| `plane` | 576K | sprite engine read-modify-write (comb), display readback, savestate |
| `iram` | 4K | MCU (comb), savestate |
| `ymsh` | 2K | replay mux (comb), savestate |

`vr0`-`vr2` are the straightforward ones: the same split as `pal`, which is
already proven. `plane` is the interesting one -- the sprite engine does a
read-modify-write on it for first-writer-wins, so its read and write are in the
same cycle at the same address, and it also has a display readback.
