# M2 gate 5 — the protection handshake, command by command  (MET)

`docs/PLAN.md` M2 gate (5): "the protection handshake verified command by
command against MAME's MCU trace, **not merely 'the game boots'**".

## Result

`tools/prot_compare.py` against traces from `sim/oracle/ms1_bustrace.lua`:

| set | mode | commands matching | answers matching | extra polls (RTL / MAME) |
|---|---|---:|---:|---:|
| avspirit | B | **1708/1708** | **1708/1708** | 852 / 845 |
| 64street | C | **563/563** | **563/563** | 0 / 0 |

Both sides of every transaction agree: the command the game chose to send, and
the byte the MCU handed back.

The comparison aligns by COMMAND rather than diffing the raw line sequence,
because the game **polls** -- it writes a command and reads the port until the
answer it wants appears. A sim whose MCU replies a fraction of a frame later
than MAME's emits extra reads of the stale value and is not wrong. The extra
poll counts are reported as a latency measure in their own right, and on
avspirit they are within 1% of MAME's (852 against 845).

## Coverage

A matching count means nothing if every command was the same one (MS1-18), so
what was actually exercised:

| set | commands exercised |
|---|---|
| avspirit | `06` fixed reply x855, `37` SYSTEM x172, `35` P1 x170, `36` P2 x170, `33` DSW1 x170, `34` DSW2 x170, `FF` init x1 |
| 64street | `06` x282, `57` x56, `53` x56, `54` x56, `55` x56, `56` x56, `FA` init x1 |

Every input source, the fixed reply and the initialisation exchange.

### The commands were also made distinguishable

With the real inputs, four of avspirit's five sources read `0xFF` and only
DSW2 differs. A wrong source-to-command mapping would therefore return `0xFF`
anyway and pass. Re-running with deliberately distinct inputs closes that:

```
p1=11 p2=22 dsw1=33 dsw2=44 system=55
   cmd 33 DSW1    expect 33  got 0x33  OK
   cmd 34 DSW2    expect 44  got 0x44  OK
   cmd 35 P1      expect 11  got 0x11  OK
   cmd 36 P2      expect 22  got 0x22  OK
   cmd 37 SYSTEM  expect 55  got 0x55  OK
```

Each command returns its own source and no other. This is a property of the
RTL alone -- MAME cannot easily be given the same inputs -- so it is a
self-consistency check rather than a comparison, and it is the one that makes
the comparison above mean what it appears to mean.

## The oracle had to be re-captured first

The previously captured `prot.log` answered command `0x34` (DSW2) with
`0xFC`. The correct answer is `0xFD`. The trace had been taken while
`cfg/avspirit.cfg` still held the Flip Screen DIP forced for the M1 flipped
frame (MS1-25), and MAME reads that file back on every run regardless of
`-noreadconfig`.

So the reference itself was wrong, and a gate run against it would have
"passed" only if the RTL reproduced the contamination. Both traces were
re-captured with `cfg/` cleared and are now the ones in
`sim/oracle/traces/bus_avspirit` and `bus_64street`. M2 gate 1 was re-checked
against the clean traces and is unchanged at 188,314 and 30,371 accesses --
the DIP does not affect the boot path that far.

## Reproducing

```sh
rm -f cfg/*.cfg                     # MS1-25
cd sim/rtl/ms1_frames && make
MS1_PROTLOG=/tmp/prot_rtl.txt ./obj_dir/Vms1bcd_core /tmp/fr_avspirit 0 220 FF FF FF FD FF
python3 ../../../tools/prot_compare.py /tmp/prot_rtl.txt \
    ../../oracle/traces/bus_avspirit/prot.log
```
