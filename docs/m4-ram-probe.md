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
