# M2 gate 1 — main-CPU bus trace against MAME

`docs/PLAN.md` M2 gate (1): "main-CPU bus trace against MAME through boot".

The subject is `rtl/ms1bcd/ms1_main.sv` — fx68k, the board decode, the
scanline interrupt timer and the protection MCU — driven by
`sim/rtl/ms1_bus` against traces captured with `sim/oracle/ms1_bustrace.lua`.

## Result

Every access compared on address, direction and data (data only where MAME's
mask says the whole word was used, since a byte access leaves the other lane
undefined on both sides).

| set | mode | accesses matching exactly |
|---|---|---:|
| avspirit | B | **188,306** |
| 64street | C | **30,363** |

What that span contains, in each case:

| milestone | avspirit | 64street |
|---|---:|---:|
| first protection handshake | 158,029 | 1,398 |
| first layer-enable write | 187,984 | 29,774 |
| **end of exact match** | **188,306** | **30,363** |
| first VRAM write | 210,172 | 46,044 |

So in both modes the trace is exact through reset, ROM and RAM
initialisation, the protection conversation, and up to and just past the point
where the game turns the video layers on — and stops before the game starts
filling VRAM.

## Where it stops, and why

In both cases the first divergence is the same thing: the RTL takes the
MCU-driven **IRQ 2** a few dozen accesses before MAME does. MAME takes the
very same interrupt shortly afterwards (in mode B, 12 accesses later before
the MCU clock was corrected; in mode C, 81). Everything up to that point is
identical, and after it the two run different code — the interrupt handler —
so the traces cannot realign. `tools/bus_compare.py` tries: it finds zero
realignments, which is the expected answer for a control-flow divergence and
not for a decode bug.

IRQ 2 is raised once per protection transaction — MAME's trace fetches the
level-2 autovector exactly 3,695 times for avspirit, which is exactly its
number of protection reads — so its arrival time is set by how long the MCU
takes to answer. That depends on the MCU's cycle budget against MAME's
120 kHz scheduling quantum, and it is the limit of comparing two different
CPU timing models rather than a property of the board.

## Bugs this found

| where | bug | why it hid |
|---|---|---|
| decode | the **global address mask** was not applied before decoding | 64street's reset SP is 0, so its first push is to `0xFFFFFC`, which is nothing unmasked and work RAM at `0x1FFFFC` once masked. Every early write vanished, and the read-back returned 0. |
| harness | the trace masked the address on its way OUT, so the trace looked correct while the memory behind it was not being written | same shape as MS1-20: the instrumentation disagreed with the thing it measured |
| MCU clock | divided to 16 MHz instead of 8 (B) / 12 (C) | the MCU merely answered twice as fast; nothing breaks, the protection IRQ just lands early |
| IACK | DTACK asserted during interrupt acknowledge | would turn an autovectored interrupt into a vectored one with vector 0 |
| trace | the IACK bus cycle has no counterpart in MAME's tap | a real bus cycle on hardware, invisible to a memory tap |

## Reproducing

```sh
cd sim/rtl/ms1_bus && make
./obj_dir/Vms1_main /tmp/maincpu_avspirit.bin /tmp/iomcu_avspirit.bin \
    ../../oracle/traces/bus_avspirit/bus.log 0 FF FF FF FC FF
```

`MS1_CMP` limits how many accesses are compared, `MS1_DUMP` writes the RTL's
own trace, `MS1_NOSTOP` continues past mismatches so `tools/bus_compare.py`
can attempt to realign.
