# M2 gates 3 and 4 — the sound subsystem against MAME  (BOTH MET)

`docs/PLAN.md` M2 gate (3): "YM/OKI write counts within a few percent over the
same span". Gate (4): "audio band correlation >= 0.95 with **FM and each OKI
isolated separately** — Sand Scorpion's SS-10 is still open precisely because
it was judged from a mix".

Span: 2400 frames (42.7 s) from reset, the same attract used by gates 1, 2
and 5.

## Gate 3 — write counts

Not "within a few percent". **Every one of the six figures is exact.**

| set | mode | YM2151 | OKI #1 | OKI #2 |
|---|---|---:|---:|---:|
| avspirit | B | **67204 / 67204** | **450 / 450** | **21 / 21** |
| 64street | C | **71038 / 71038** | **879 / 879** | **0 / 0** |

(core / MAME, counted as bus write cycles to each chip.)

A matching total can hide cancelling errors, so the per-frame series was
compared too, frame by frame against `sim/oracle/traces/snd_*/sound.log`:

| set | frames identical | differing | largest difference |
|---|---:|---:|---:|
| avspirit | **2383 / 2400** | 17 | 1 write |
| 64street | **2398 / 2400** | 2 | 1 write |

Every difference is exactly one write, and every one of them is a write landing
on the far side of a frame boundary: the running total is back in agreement on
the next frame, which is why the 2400-frame totals are exact.

## Gate 4 — band correlation, per source

MAME rendered one source at a time with
`tools/mame-patches/megasys1-sound-isolation.patch` (`MS1_SND_ISO=fm|oki1|oki2`),
the core with `MS1_WAV` from `sim/rtl/ms1_snd`, compared by
`tools/audio_compare.py` over 24 geometric bands.

| set | source | mean band corr | level (MAME-core) | alignment |
|---|---|---:|---:|---|
| avspirit | FM | **0.998** | -1.4 dB | 0.000 s |
| avspirit | OKI #1 | **1.000** | +0.1 dB | 0.000 s |
| avspirit | OKI #2 | **1.000** | -0.1 dB | 0.000 s |
| avspirit | mix | 0.999 | +1.1 dB | 0.000 s |
| 64street | FM | **0.997** | -2.9 dB | 0.000 s |
| 64street | OKI #1 | **0.999** | +0.3 dB | 0.000 s |
| 64street | OKI #2 | see below | — | — |
| 64street | mix | 0.995 | +1.5 dB | 0.000 s |

The gate is 0.95. The alignment search found **zero** offset on every
comparison, with envelope correlation 1.000 over the full 42.7 s — the core
does not drift against MAME across the span, which is the thing the write
counts above already implied.

## What is NOT covered, stated plainly

**64street never writes its second OKI.** Not rarely — never: 0 writes in 2400
frames, and MAME's isolated render of it is exactly 0.0 RMS. The core's is also
exactly 0.0 RMS with a peak sample of 0, so the two agree bit for bit, but a
correlation over two silent signals is undefined and is reported as such rather
than as a pass. That row is agreement, not evidence.

So **OKI #2 is carried by avspirit alone, on 21 writes.** It correlates at
1.000 there and its isolated render is far from silent (RMS 924 against MAME's
1177), so the path is demonstrably exercised end to end — but one game and 21
writes is the whole of the evidence for that chip, and it should not be read as
equal in weight to the FM result, which rests on ~70000 writes in each of two
games.

The FM level sits 1.4 dB (avspirit) and 2.9 dB (64street) below MAME. Both are
inside the gate, which is about correlation, and both are near-flat across the
bands rather than concentrated anywhere. Worth remembering when the mix is
balanced on hardware in M4.

## The one caveat that is not a measurement error

See **MS1-31**. To match MAME, the core returns 0 for OKI status, because
`megasys1_state::machine_reset()` sets `m_ignore_oki_status = 1` for every set
here — a workaround MAME's own comment (megasys1.cpp:679) explains is for its
OKI timing, not the board's behaviour. The sound CPU polls that register and
waits on it, so the setting changes the code path and therefore these numbers.

**These tables say the core matches MAME. They do not say it matches
hardware**, and on this one bit those are different claims. `oki_status_real`
exists for exactly this and is plumbed to the core boundary; what the MiSTer
top level should pass is an open question for the board.

## How the numbers were reached

Three bugs stood between the first run and this table, all recorded in
`docs/known-issues.md`: **MS1-28** (a divider accumulator one bit too narrow —
the whole sound domain ran 3.3x fast), **MS1-29** (jt51 samples `write` on
`cen`, so a one-clock strobe never raised `busy`, while jt6295 needs exactly
the opposite), and **MS1-30** (`screen_flag` bit 4 is a reset line over the
sound 68000, the YM2151 and both OKIs — an input with no trace on the sound
CPU's own bus).

The harness is `sim/rtl/ms1_snd`, which simulates the sound subsystem alone
and replays MAME's own event log into it. That is possible because the
subsystem's entire input is tiny: 15 latch writes and 3 reset transitions in
2400 frames on avspirit, 5 and 5 on 64street. Everything else the sound CPU
does it drives itself from the YM2151's timer, polling with interrupts masked
at level 7 — neither MAME nor the core ever fetches the interrupt vector at
`0x70`. Both event streams carry the absolute 48 MHz clock of MAME's write, so
the replay lands on the same cycle; at frame granularity alone the reset
arrived 651342 clocks late and left a constant 18-write offset.

---

## Re-verified 2026-09-22, against the RTL as it now stands

Everything above was measured before M3 changed `ms1_sound.sv` — the HW_ROMS
handshake and the sound CPU's park monitor both landed after it. The harness
then stopped building, and when made to build it stopped running, and said
neither (MS1-45), so nothing had re-checked these numbers since.

Both gates were re-run with the harness fixed. `avspirit`, 2400 frames:

```
after 2400 frames: ym=67204 oki1=450 oki2=21  ymirq=28233 iack=0
```

Identical to MAME's own trace and to the table above: **67204 / 450 / 21**.

Band correlation, same run:

| source | mean band corr | level (MAME - core) |
|---|---:|---:|
| FM | 0.998 | -1.4 dB |
| OKI #1 | 1.000 | +0.1 dB |
| OKI #2 | 1.000 | -0.1 dB |
| mix | 0.999 | +1.1 dB |

Gate 4 asks for >= 0.95 per source. Both gates still hold.

Invocation, since two of its inputs are not obvious and leaving either out
produces a confident wrong answer:

```
cd sim/rtl/ms1_snd && make
MS1_SRESET=../../oracle/traces/snd_avspirit/sreset.log \
MS1_WAV=/tmp/rtl_avspirit \
  ./obj_dir/Vms1_sound /tmp/gen_avspirit 0 2400 \
     ../../oracle/traces/snd_avspirit/latch.log
bash tools/run_audio_gate.sh avspirit
```

Without the latch log the sound CPU is given no commands and plays silence.
Without `MS1_SRESET` it never sees the main CPU's reset line. Neither omission
is reported as an error.
