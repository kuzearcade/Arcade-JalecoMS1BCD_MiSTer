# Known issues and open questions — Arcade-JalecoMS1BCD_MiSTer

Numbered `MS1-n`, in the style of the NMK16 and Sand Scorpion lists: each entry
records what was measured, how, and what is still unknown. An entry is only
closed by a measurement, never by reasoning.

**Two are open**, both recorded during M0 and both answerable off-board.

| | | |
|---|---|---|
| MS1-1 | `edfbl` is not a System B board and is excluded | closed |
| MS1-2 | Two sets ship a dumped TMP91640 that MAME never runs | closed |
| MS1-3 | The ROM extractor silently dropped every `BAD_DUMP` part | closed |
| MS1-4 | `chimerab`'s MCU and priority PROM are both substitutions | **OPEN** — declared and shipped; correctness unproven until M2 |
| MS1-5 | Every MCU dump the driver names is present and verified | closed |
| MS1-6 | System D's protection is not the B/C command table | closed |
| MS1-7 | The local romsets predate MAME 0.289's filename changes | closed |
| MS1-8 | `hayaosi1` runs its samples at 2 MHz for unknown reasons | **OPEN** — MAME says "unknown OSC + divider combo" |
| MS1-9 | `screen:pixels()` returns three values, not one | closed |
| MS1-10 | A Lua write tap is removed when it is garbage-collected | closed |
| MS1-11 | The oracle's registers and sprites lag its VRAM by a frame | closed |
| MS1-12 | A per-frame snapshot cannot reproduce every frame | **OPEN** — bounded and understood; not an RTL defect |
| MS1-13 | Screen flip is rot180 of the finished frame | closed |
| MS1-14 | MAME hangs in SDL device init with no video or sound | closed |
| MS1-15 | Sprite "low priority" is the attribute bit SET, not clear | closed |
| MS1-16 | MAME's sprite order contradicts its own comment | **OPEN** — unobservable in any captured scene |
| MS1-17 | The sprite trails effect is not modelled | **OPEN** — no captured scene uses it |
| MS1-18 | A green gate can mean the feature was never exercised | closed |
| MS1-19 | The protection MCU is paced by the video frame, not a timer | closed |
| MS1-20 | A debug probe showed the read bus on writes | closed |
| MS1-21 | The global address mask is part of the decode | closed |
| MS1-22 | Bus traces can only agree until an interrupt lands apart | **OPEN** — a limit of the method, bounded and understood |
| MS1-23 | One interrupt-acknowledge CYCLE must retire one interrupt | closed |
| MS1-24 | The protection MCU needs ~48 frames of boot before it answers | closed |
| MS1-25 | MAME persists a forced DIP into cfg/ and re-reads it forever | closed |
| MS1-26 | A relative -rompath reads as a broken romset | closed |
| MS1-27 | A held `valid` sampled per clock passes its own sanity check | closed |

---

## MS1-1 — `edfbl` is not a System B board and is excluded (closed)

`edfbl` has a PIC in place of the TMP91640, no sound CPU at all, and a banked
OKI. MAME flags the whole machine `MACHINE_NO_SOUND`, and its priority PROM is
not confirmed to match. Shipping it would mean shipping a silent game whose
protection is unknown.

It is therefore in `EXCLUDED` in `tools/gen_ms1bcd_mra.py`, with the reason
carried in the table so `--check` prints it rather than leaving a silent gap.
Sixteen of the seventeen sets in the driver are in scope; this is the one that
is not. Closed by decision, not by measurement, and recorded here so that the
decision is visible rather than implicit.

## MS1-2 — Two sets ship a dumped TMP91640 that MAME never runs (closed)

`hayaosi1` declares a `ROM_REGION(0x4000, "iomcu")`, and so does `peekaboo`.
Neither machine configuration runs one:

- `hayaosi1` uses `system_B_hayaosi1`, whose MCU is `NO_DUMP` — the region is
  declared but the file does not exist. MAME substitutes the seven-value
  `ip_select` command table.
- `peekaboo` uses `system_D`, which instantiates **no MCU device at all**
  (checked against the machine config in `megasys1.cpp`), even though a real,
  correctly-CRC'd dump of `mo-92033.mcu.ic120` exists upstream.

The first version of the generator inferred protection from *the presence of an
MCU ROM region*, which made both sets come out as `mcu` and put the wrong byte
in their `.mra`: `hayaosi1` emitted `0x10` where it should emit `0x30`.

The fix is that protection is now derived from the MAME machine configuration
recorded in the ROM table (`PROT_BY_CFG` in `tools/gen_ms1bcd_mra.py`), keyed
exhaustively so an unrecognised config raises rather than defaulting to a
plausible-looking wrong value. **Region presence is not evidence that a device
is live**; the machine config is the only authority.

The derivation is independently corroborated: the only two sets that come out
as `iosim` — `hayaosi1` and `chimeraba` — are exactly the two whose MCU is
`NO_DUMP`. A simulated protection path and an undumped MCU are the same fact
seen from two directions, and they agree.

## MS1-3 — The ROM extractor silently dropped every `BAD_DUMP` part (closed)

`tools/extract_ms1_roms.py` matched ROM lines with a regex that required
`CRC(` to follow the length immediately. MAME may place a dump flag in
between:

```
ROM_LOAD( "pr-91044", 0x0000, 0x0200, BAD_DUMP CRC(c69423d6) SHA1(...) )
```

No match, no part, no error. The region stayed in the table with an empty part
list, so `chimerab` and `chimeraba` generated `.mra` files **with no priority
PROM at all** — the core would have received a zeroed PROM and mis-prioritised
every layer in both games, with nothing anywhere reporting a problem.

This is the same class of defect as the NMK16 lesson in the plan's 4.A: a
generator that produces confidently wrong output is worse than one that fails.
The parser now captures the flag as a field, and the generator distinguishes:

- `BAD_DUMP` — a real file MAME deliberately substitutes. It is the best data
  that exists, so it ships, with an XML comment declaring it.
- `NO_DUMP` — no file exists. It must never reach the `.mra` or the byte
  stream; the region is padded and the simulated protection path takes over.

The audit that catches a recurrence is the `promparts` count: every in-scope
set must carry exactly one index-1 PROM part. Sixteen of sixteen do.

## MS1-4 — `chimerab`'s MCU and priority PROM are both substitutions (OPEN)

Both of `chimerab`'s protection-critical parts are `BAD_DUMP` in MAME:

| part | substitution | MAME's note |
|---|---|---|
| `mo-91028.mcu` | Cybattler's MCU program | *"using Cybattler program, label not confirmed"* |
| `pr-91044` | 64street/hayaosi1's PROM | *"guess, but 99% sure … based on analysis of game and previous handcrafted data"* |

Both are declared in the generated `.mra` (plan section 2.3 requires the
substitution be visible in the file, not only in a comment in the generator),
and both ship, because they are the best data that exists and are what MAME
itself runs.

**Open** because "MAME runs this and it looks right" is not the same as
verified. `chimerab` is a prototype; if its priority resolution or protection
diverges at M2, a substituted part is the first place to look, and this entry
is the record that the substitution was known in advance rather than
discovered as a surprise.

## MS1-5 — Every MCU dump the driver names is present and verified (closed)

All sixteen in-scope sets resolve every part of their index-0 stream and their
index-1 PROM against the local romsets, with zero unresolved parts.

Five distinct TMP91640 dumps exist across the driver, and every one is present
and CRC-verified:

| dump | size | CRC32 | used by |
|---|---|---|---|
| `avspirit-mcu.11l` | 0x4000 | `d9b2eb1a` | avspirit |
| `edf-mcu.11l` | 0x4000 | `1503026d` | edf, edfa, edfb, edfu |
| `mo-91009.mcu.ic14` | 0x4000 | `c6f509ac` | 64street ×3 |
| `mo-91021.mcu` | 0x4000 | `dbda258a` | bigstrik |
| `mo-91028.mcu` | 0x4000 | `a72e04a7` | cybattlr, and chimerab as a substitution (MS1-4) |
| `mo-92033.mcu.ic120` | 0x4000 | `9dfba11b` | peekaboo, peekaboou — present, though `system_D` never runs it (MS1-2) |

The three sets that carry **no** MCU file are the three that should not:
`hayaosi1` and `chimeraba`, whose MCUs are `NO_DUMP` and which therefore use
simulated protection (MS1-2), and `monkelf`, a bootleg with no MCU at all.

Two files resolve by CRC rather than by name, because the local zips predate
MAME 0.289's renames (MS1-7): `avspirit-mcu.11l` is stored as `avspirit.mcu`
and `mo-92033.mcu.ic120` as `mo-92033.mcu`. Both are byte-identical to MAME's
dump by SHA1, not merely by CRC.

## MS1-6 — System D's protection is not the B/C command table (closed)

Mode D was very nearly encoded as `iosim`, which would have been wrong.
`peekaboo`'s protection is a bespoke pair of handlers installed over
`0x100000`–`0x100001` (`protection_peekaboo_r` / `protection_peekaboo_w` in
`megasys1.cpp`), unrelated to the seven-value `ip_select` table that B and C
use. It gets its own protection code (`3`, byte value `0x60`) in the game-mode
byte, so the core never has to infer it from the mode bits.

Mode-byte encoding as it now stands, for the record:

```
bits 1:0  mode        0 = B, 1 = C, 2 = D
bit  4    sample clock  set = 2 MHz, clear = 4 MHz
bits 6:5  protection  0 = MCU, 1 = simulated, 2 = none, 3 = System D's own
```

Sixteen emitted values: `0x00` ×5 (B/MCU), `0x01` ×6 (C/MCU), `0x21`
(chimeraba, C/simulated), `0x30` (hayaosi1, B/2 MHz/simulated), `0x40`
(monkelf, B/none), `0x72` ×2 (peekaboo, D/2 MHz/own).

## MS1-7 — The local romsets predate MAME 0.289's filename changes (closed)

Under `--strict-names`, five of `peekaboo`'s seven parts and eight of
`avspirit`'s eleven fail to resolve; with name matching relaxed to CRC, every
one resolves and every byte is identical. The local zips are
simply older than the renames in the current driver — `avspirit-mcu.11l` is
present as `avspirit.mcu`, byte-for-byte (SHA1 `6e0ec065a46b…`, matching MAME).

The `.mra` files carry the **current** names, which is correct: users are
expected to have current romsets, and the MRA is a description of the set as
MAME defines it today. `--strict-names` is retained as a diagnostic so that a
name mismatch can always be told apart from a genuinely missing file. That
distinction earned its keep during M0: a file reported as missing turned out
to be present under its older name, and the two cases are indistinguishable
without it.

## MS1-8 — `hayaosi1` runs its samples at 2 MHz for unknown reasons (OPEN)

Every other B and C set clocks both OKI chips at 4 MHz. MAME overrides
`hayaosi1` to 2 MHz with the comment that this is the *"correct speed, but
unknown OSC + divider combo"*. Mode D also runs at 2 MHz.

Carried into the game-mode byte as bit 4 rather than being derived from the
mode, because it is a per-set fact and not a per-mode one. Both rates are exact
integer divisions of the 48 MHz `clk_sys` (÷12 and ÷24), so this is a mux and
not a second PLL.

**Open** only in the sense that the reason is unknown upstream too. The
observable consequence — sample pitch in `hayaosi1` — is checkable against the
MAME oracle at M2, and that is what will close it.

## MS1-9 — `screen:pixels()` returns three values, not one (closed)

The first oracle capture wrote every frame as

```lua
f:write(scr:pixels())
```

which looks right and is wrong. In MAME 0.289 `screen:pixels()` returns
**three** values — the packed pixels, the width and the height — and Lua's
`io.write` writes all of its arguments. Every frame came out six bytes long,
with the ASCII string `256224` appended:

```
00037ff6: 00ff 0000 00ff 0000 00ff 3235 3632 3234   ..........256224
                                   ^^^^^^^^^^^^^ "256224"
```

229382 bytes instead of 229376. Six bytes on a 224 KB file is the kind of
error that survives a glance at a rendered PNG, and every downstream
pixel-exactness comparison would have been run against a frame buffer whose
length did not match its own geometry.

It was caught by asserting the file size against `256*224*4` rather than by
looking at an image — the same discipline as the `.mra` `promparts` count in
MS1-3. Both bugs are the same shape: output that looks plausible and is
silently malformed, caught only because something counted it.

The fix is to bind the first return value before writing it:

```lua
local px = scr:pixels()
f:write(px)
```

Sand Scorpion's `tools/ss_frames.py` would have caught this too — it raises
if a raw frame is not exactly `W*H` pixels. That assert is worth keeping in
this project's consumer for the same reason.

## MS1-10 — A Lua write tap is removed when it is garbage-collected (closed)

Several Mega System 1 video registers are **write-only** — `active_layers`,
`screen_flag` and System C's `sprite_bank` are all mapped with `.w(...)` and
nothing else. They cannot be read back through the CPU's program space, and
reading the register window wholesale would fire every real read handler in
range, perturbing the machine being measured.

So the capture taps writes instead:

```lua
mem:install_write_tap(win_lo, win_hi, 'ms1regs', function(offset, data, mask)
  ...
end)
```

Every register read back as `0000` at frame 149 of a game that was visibly
drawing. The tap was never firing. `install_write_tap` returns a
`memory_passthrough_handler`, and **the tap lives only as long as that handle
does** — discarding the return value lets Lua collect it and the tap is
silently uninstalled. Assigning it to a variable that outlives the callback
fixes it:

```lua
TAP = mem:install_write_tap(...)
```

with `active_layers=000F` and `t2_ctrl=0011` appearing immediately.

The failure mode is the dangerous one: not an error, but a plausible constant.
Zeroed registers would have been read as "the game has not configured the
video yet", and every layer-enable and tile-size decision in the reference
model would have been made from fiction. It was caught by asking the question
that MS1-3 and MS1-9 were also caught by — *does this output actually change
when it should?* — rather than by reading it once and believing it.

## MS1-11 — The oracle's registers and sprites lag its VRAM by a frame (closed)

The capture reads everything at `frame_done`, which runs after MAME has
rendered the frame. By then the game's vblank handler has already written the
values for the *next* frame. The three sources do not share one offset, and
each was measured rather than assumed:

| source | frame to use | how it was established |
|---|---|---|
| VRAM, palette | **F** | F−1 raises the error from 1650 px to 107197 px over 57 frames |
| video registers | **F−1** | see below |
| object + sprite RAM | **F−3** | F−2 leaves 23692 px over 13 frames, F−3 leaves 1468, F−4 leaves 23296 |

The register offset is the interesting one. At avspirit frame 400 the captured
scroll is `t0=0x54, t1=0xA8`, and the frame MAME actually drew needs
`0x53, 0xA6` — exactly frame 399's values. What proves it is a frame offset
rather than a constant fudge is that the two corrections, −1 and −2, are in
the same ratio as the two layers' parallax rates. A fixed pixel offset would
have been equal on both layers.

The sprite offset is MAME's documented "sprites are TWO frames ahead"
(`screen_vblank` does `buffer2 <- buffer <- live`, and `draw_sprites` reads
`buffer2`) plus this same one-frame capture lag.

None of this is a property of the hardware. It is a property of reading state
from an emulator at one instant per frame, and it exists only in the oracle.
The RTL rasterises continuously, as the board does, and has no equivalent.

## MS1-12 — A per-frame snapshot cannot reproduce every frame (OPEN)

With the offsets of MS1-11 applied, the model is pixel-exact on most frames
but not all:

Across roughly 2800 frames of eight captures, only **14 exceed 500 differing
pixels**, and 8 of those are frames where a video register changed between F-1
and F. Per-capture rates are in `docs/m1-gate.md`.

The residuals are not random. Every one inspected is a small, localised band
of *layer* pixels — a blinking "PUSH START", a score digit, a character of
animating text — with no sprite pixel involved, at a frame where the game
changed that VRAM during the vblank in which the snapshot was taken. Mode D's
lower rate reflects that peekaboo's screen is full (57344 non-blank every
frame, so there is always text animating), not that mode D is worse
understood: 270 of its 297 frames are within 50 pixels, and only three exceed
200.

This is the oracle's granularity, not an RTL defect, and it cannot be fixed by
choosing a different frame offset — the three sources already disagree about
which frame they belong to (MS1-11), which is exactly what a single snapshot
per frame cannot express.

**Open** because it bounds what the M1 gate can claim from this method. When a
frame must be proven exactly, the answer is to compare against a frame where
nothing is animating, or to capture at the IRQ instant as Sand Scorpion's
`SS_TAPS=1` dump does (`docs/PLAN.md` 4.D item 11 is the same lesson: prove
two frames are the same scene before diffing them).

All three configurations that were unexercised when this entry was written
have since been captured and pass with zero differing pixels: sprite splitting
(`bigstrik`), page layouts N=2 and N=3 (`edf`, `hayaosi1`), and a flipped
frame (`avspirit` with the DIP forced). See `docs/m1-gate.md`.

## MS1-13 — Screen flip is rot180 of the finished frame (closed)

MAME reaches screen flip the long way. `screen_update` gives every tilemap
`TILEMAP_FLIPX|TILEMAP_FLIPY`, which `tilemap.cpp` implements in two places at
once — `mappings_update` mirrors the logical/memory tile indices, and
`tile_update` XORs the global flip into each tile's own flip flags — while
`draw_sprites` separately mirrors each sprite, inverting `flipx`/`flipy` and
mapping `sx, sy` to `240-sx, 240-sy`.

The composite of all that is a plain 180-degree rotation of the visible frame,
because the visible window is symmetric about the bitmap centre: rows 16..239
of a 256-row bitmap and columns 0..255 are both centred on 127.5.

Sand Scorpion's lesson (`docs/PLAN.md` 4.D item 10) warns that "RTL flip ==
rot180(RTL no-flip)" is tautological and has to be checked against MAME. So it
was checked **MAME against MAME**: `avspirit` was captured twice from the same
starting point, once with the Flip Screen DIP forced, and

    flipped frame  ==  rot180(unflipped frame)      0 differing pixels

Both sides came from MAME, so the identity is a property of the hardware model
rather than of this code. The first attempt did it the long way instead —
mirroring source coordinates per layer with a scroll adjustment derived from
`effective_rowscroll` — and was 61-69% wrong, because the scroll term is not
what that derivation assumed.

No attract mode in any of the sixteen sets ever sets `screen_flag` bit 0, so
without the DIP this could not have been tested at all.

## MS1-14 — MAME hangs in SDL device init with no video or sound (closed)

Part way through the M1 captures every MAME invocation began hanging: the
process started, consumed **zero CPU**, produced no output, never ran the
autoboot script, and ignored `SIGTERM`. Games that had run correctly minutes
earlier hung the same way, so it was not the game or the script.

`-video none -sound none` does not stop MAME's SDL OSD from opening real
video and audio devices, and once that wedged, every later run inherited it.

The fix is to tell SDL not to touch the hardware at all:

```sh
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
```

With that, the same command runs at 1553% speed. Every oracle capture must set
it; `/tmp/gate_run.sh` does, and so should anything that drives MAME here.

Two smaller traps found alongside it, both of which waste time in the same
way — a job that looks like it is working and is not:

* **MAME must not have a pipe on stdout.** Piping into `grep` or `head` hid
  every error message, including the ones that would have identified this.
  Redirect to a file and read the file.
* `pkill -f mame` matches the shell's own command line and kills the session.
  Kill by PID from `pgrep -x mame` instead.

## MS1-15 — Sprite "low priority" is the attribute bit SET, not clear (closed)

The priority PROM's address bit 0 is "low priority sprite AND sprite
splitting". Which sprites are the *low* group was not obvious: the sprite
attribute's bit 3 is documented only as "priority", and MAME's
`mix_sprite_bitmap` turns it into a mask of `0x0c` when set and `0x0a` when
clear, which does not name either group.

Measured on bigstrik's split scenes, where half the screen is sprite pixels:
the low group is the one whose attribute bit 3 is **SET**. The other polarity
costs 25205 of 57344 pixels there, and **exactly zero** on every scene that
has no sprites or no splitting -- which is every other scene captured.

## MS1-16 — MAME's sprite order contradicts its own comment (OPEN)

`megasys1_v.cpp` says "sprite order is from first in Sprite Data RAM
(frontmost) to last", and that line is what `docs/PLAN.md` 4.D item 8 carries
in as "sprite order here is first-entry-frontmost, the opposite of PANDORA".

The code does the opposite. `draw_sprites` walks Object RAM **descending**
(`offs` from 0x3fc down to 0) and `draw_single_sprite` is **first-writer-wins**
(it tests bit 15 and skips a pixel that is already set). Drawing the last
entry first and refusing to overwrite makes the **last** entry frontmost.

The RTL mirrors the code, because the code is what produced the oracle frames.
**Open** because no captured scene distinguishes the two: reversing the walk in
the Python model changes nothing on any frame checked, so nothing here has
overlapping sprites from different entries. A scene that does would settle it.

## MS1-17 — The sprite trails effect is not modelled (OPEN)

`sprite_flag` bit 4 means "do not clear the sprite framebuffer", and MAME
then does a *partial* clear by pen value (`partial_clear_sprite_bitmap`),
commenting that the P47 trails effect is "not quite right tho" and that it
does not know what the low four bits select.

`ms1_sprites.sv` honours the bit to the extent of skipping the clear, but does
not implement the partial clear. **Open** because no captured frame of any of
the sixteen sets sets bit 4, so there is nothing to verify against; the upstream
behaviour is admittedly uncertain anyway.

## MS1-18 — A green gate can mean the feature was never exercised (closed)

The first complete run of the M1 gate through the RTL passed 26 of 26. Two of
those rows claimed to test sprite splitting and "sprites both over and under
the layers". The scenes chosen for them contain **zero sprite pixels** -- and
so do all three scenes chosen for mode C. They passed because the sprite engine
contributed nothing to them.

Choosing scenes that actually contain sprites dropped the same gate to 23 of 28
and exposed two real bugs immediately (the sprite field off-by-one and the
priority polarity of MS1-15), one of which is wrong on 44% of the pixels of
every split scene.

The lesson is not "check sprite counts". It is that **a gate is only as strong
as the coverage of the scenes it runs on**, and coverage has to be measured
rather than inferred from the scene's name. `tools/run_video_state_gate.sh` is
now accompanied by a coverage audit -- sprite pixels, active layers, split and
flip per row -- printed in `docs/m1-gate.md` beside the results, so a row that
stops exercising its feature is visible rather than quietly green.

This is the same failure shape as MS1-3 (a generator that produced .mra files
with no PROM) and MS1-9 (frames six bytes too long): output that looks correct
because nothing counted what it contained.

## MS1-19 — The protection MCU is paced by the video frame, not a timer (closed)

The TMP91640 boots, initialises its registers, disables the watchdog, and then
parks in a tight loop at 0x0266 polling one byte of its internal RAM. Nothing
in the MCU releases it. Its own INTEL write (0x10) enables exactly one source,
and the vector it eventually takes is 0x0058, which is `0x10 + irq*8` for
irq 9 = **INT1**.

INT1 is not a timer and not the host handshake. From `megasys1.cpp`:

```
if (scanline == 0 + 16)    // end of vblank
    m_iomcu->set_input_line(INPUT_LINE_IRQ1, ASSERT_LINE);
if (scanline == 224 + 16)  // start of vblank
    m_iomcu->set_input_line(INPUT_LINE_IRQ1, CLEAR_LINE);
```

It is the **display-enable signal**. The MCU's whole command loop runs off the
video frame, so a standalone MCU harness with no video timing is not a slow
MCU, it is a dead one — which is exactly how this presented.

Two consequences that carry into the core:

* INT1 is a LEVEL in MAME but the TLCS-90 core latches `irq_req` and does not
  clear on take, so a held level re-pends forever. The wrapper takes the edge.
* The edge detector must follow INT1 through reset. Releasing reset with the
  beam already inside the visible area otherwise manufactures a rising edge
  that never happened, and the MCU takes an interrupt thousands of cycles
  early.

## MS1-20 — A debug probe showed the read bus on writes (closed)

The MCU wrapper's trace probe was `assign dbg_din = din`, and `din` is the
READ bus. Every write in the trace therefore printed whatever the read mux
happened to be presenting, which was 0.

The trace then said the MCU wrote `00` to the watchdog register where MAME
wrote `01`, and to every other register besides. Half an hour went into
suspecting `LD r,n` in a CPU core that has eight passing ISA self-tests,
before a synthetic two-instruction ROM showed the same `00` for an
instruction with **no register operand at all** — which no plausible CPU bug
explains, and which pointed straight at the probe.

`assign dbg_din = mem_wr ? dout : din;` and the traces matched immediately.

The lesson is the one MS1-3, MS1-9 and MS1-18 all taught in other forms:
**instrumentation is code, and wrong instrumentation costs more than no
instrumentation**, because it sends you looking in the right place for the
wrong reason. When a trace accuses something that is already well tested,
suspect the trace.

## MS1-21 — The global address mask is part of the decode (closed)

Every Mega System 1 memory map opens with `map.global_mask(...)`: `0xfffff` on
System B, `0x1fffff` on System C. That is not decoration. The board ignores the
high address lines, and it matters from the very first instruction:

64street's reset stack pointer is **0**, so the 68000's first push goes to
`0xFFFFFC`. Unmasked that is nothing at all; masked to 21 bits it is `0x1FFFFC`,
which is work RAM. Decoding the raw 24-bit address silently dropped every early
write, and the read-back a few accesses later returned 0 where MAME returned 6.

The reason this took a while is the second half: the harness applied the mask
on the way *into the trace*, so the trace showed `w 1FFFFC` — exactly what MAME
showed — while the RAM behind it was never written. The instrumentation and the
thing it instrumented disagreed, and the instrumentation was the one that
looked right. Same shape as MS1-20.

## MS1-22 — Bus traces can only agree until an interrupt lands apart (OPEN)

`rtl/ms1bcd/ms1_main.sv` reproduces MAME's main-CPU bus trace exactly for
188,306 accesses on avspirit and 30,363 on 64street — through reset, ROM and
RAM initialisation, the protection conversation and past the first
layer-enable write (`docs/m2-gate1.md` has the milestone table).

Both stop the same way: the RTL takes the MCU-driven IRQ 2 a few dozen
accesses before MAME. MAME takes the *same* interrupt shortly after. After
that the two are inside an interrupt handler at different points and the
traces cannot realign — `tools/bus_compare.py` finds zero realignments, which
is what a control-flow divergence looks like and is not what a decode bug
looks like.

IRQ 2 is raised once per protection transaction (MAME fetches the level-2
autovector exactly 3,695 times for avspirit, matching its 3,695 protection
reads), so its arrival is set by how long the MCU takes to answer. Correcting
the MCU clock from 16 MHz to the proper 8/12 MHz moved the divergence later
but did not remove it: what remains is a cycle-exact RTL sim against MAME's
120 kHz scheduling quantum.

**Open** because it bounds what this comparison can prove, not because
anything is known to be wrong. A longer agreement would need MAME's own
timing model rather than a better board model, which is the wrong thing to
chase. The frame-level gates (M2 gate 2) are the right instrument beyond this
point, because they compare what the board produces rather than when it
produces it.

## MS1-23 — One interrupt-acknowledge CYCLE must retire one interrupt (closed)

The interrupt timer holds each level until the CPU acknowledges it, which is
what MAME's `HOLD_LINE` means. The acknowledge was detected as a LEVEL:

```systemverilog
wire iack = ~ASn & (FC0 & FC1 & FC2);
...
if (iack) begin
    if      (irq4_h) irq4_h <= 1'b0;
    else if (irq2_h) irq2_h <= 1'b0;
    else if (irq1_h) irq1_h <= 1'b0;
end
```

`iack` stays asserted for the whole acknowledge bus cycle, so that chain walks
down the priority ladder on successive clocks and retires **every** pending
interrupt in one acknowledge. Only the highest-priority source is ever
serviced; the rest are raised and silently discarded.

The symptom was not "interrupts are broken". It was that avspirit took IRQ 4
every frame, as expected, while IRQ 1 and the protection's IRQ 2 were counted
as raised and never seen by the CPU — and the game sat in its `STOP` loop at
0x1006 polling a work-RAM byte that only the IRQ 2 handler ever writes.

Fixed by acknowledging on the rising edge of `iack`.

## MS1-24 — The protection MCU needs ~48 frames of boot before it answers (closed)

Hours could go into "the MCU is not responding" here, so it is worth writing
down: it is supposed not to respond, for quite a long time.

avspirit's main CPU writes its first protection command at bus access 158,029
and then `STOP`s. MAME's MCU does not read its input-latch space for the first
time until **MCU access 1,420,713** — it spends everything before that on its
own initialisation. In this core that is about 48 frames of simulated board
time before the first IRQ 2 reaches the 68000, and roughly 100 before the game
turns its layers on.

Two consequences:

* A frame-level comparison that runs 40 or 60 frames sees a black screen and
  concludes the video is broken. It is not; the game has not drawn yet.
* Any "is the MCU alive?" check has to be a counter over a long run, not an
  inspection of the first few thousand cycles.

The numbers to expect on avspirit, measured: about 30,000 main-CPU accesses per
frame once running, 1 INT1 edge per frame, and IRQ 2 roughly ten times per
frame once the protection conversation is in flow.

## MS1-25 — MAME persists a forced DIP into cfg/ and re-reads it forever (closed)

Forcing the Flip Screen DIP for the M1 flipped-frame capture (MS1-13) left
this behind in `cfg/avspirit.cfg`:

```xml
<port tag=":DSW2" type="DIPSWITCH" mask="1" defvalue="1" value="0" />
```

MAME writes per-game settings on exit and reads them back on every later run.
**`-noreadconfig` does not prevent this** -- it governs `mame.ini`, not
`cfg/<game>.cfg`. So one deliberately-forced DIP silently changed every
avspirit run afterwards, including the input-port capture whose values were
then fed to the RTL sim.

The consequence was a full day's worth of wrong conclusion. The core rendered
a **flipped** screen because the DIP said so, was compared against
`avspirit_long` -- captured *before* the contamination, therefore unflipped --
and the mismatch looked like a video bug. Every other signal said the video
was fine: the sim's VRAM, palette and object RAM were byte-identical to
MAME's, the protection handshake matched for 131 transactions, and the same
video RTL fed the sim's own state through `sim/rtl/video_state` produced
MAME's frame with zero differing pixels. Four correct measurements against one
contaminated constant, and the constant won for far too long.

The tell was there to be read: uncontaminated 64street reports `DSW2 = 0x00FD`
(bit 0 set) while avspirit reported `0x00FC` (bit 0 clear). Two games of the
same family disagreeing on the default of the same DIP bit is not a thing that
happens.

**Rules that follow.** Delete `cfg/<game>.cfg` before any measurement run, or
keep forced-DIP runs in a separate `-cfg_directory`. Never take an input-port
capture without checking for a saved override first. And treat a captured
"constant" as evidence with a provenance, not as ground truth: it has a
timestamp and a history like everything else.

## MS1-26 — A relative -rompath reads as a broken romset (closed)

Every MAME command in this project passes `-rompath mame_roms`, which resolves
against the **current working directory**. Run from the project root it works;
run from anywhere else MAME prints

```
jaleco_a.spirit_5.5b NOT FOUND (tried in avspirit)
```

for every file, which reads exactly like a missing or corrupt romset and is
neither -- the zips are present and intact.

`tools/run_oracle_captures.sh` now derives an absolute `ROMS` from its own
location. Any new script should do the same rather than assuming a cwd.

## MS1-27 — A held `valid` sampled per clock passes its own sanity check (closed)

`ms1_video` emits one pixel per `ce`, and `ce` is one clock in eight. Its
`rgb_valid` is a REGISTER updated on `ce`, so it stays asserted across all
eight clocks of a pixel. The frame harness collected per clock:

```cpp
if (top->rgb_valid && px < cur.size()) cur[px++] = top->rgb;
```

which advanced the write pointer eight times per pixel and filled each frame
from the first eighth of the image.

The reason this survived so long is the shape of the failure. The collector
stops at `cur.size()`, so the per-frame pixel count came out at **exactly
57344** -- the right answer -- and the check written specifically to catch this
class of bug reported success every frame. Meanwhile a probe inside the core
counting emitted non-black pixels showed **1812 per frame**, exactly MAME's
figure, which is what finally made it clear the video was right and the
measurement was wrong.

Gated on the pixel enable, the same run went from 5 exact frames to 117, and
to 150 of 151 once the DIP of MS1-25 was also corrected.

The core now exposes `ce_pix_o` with a comment stating that a consumer must
sample `rgb`/`rgb_valid` on it. The wider lesson is the one MS1-20 and MS1-21
taught in other forms: **a sanity check that can pass while the thing it
guards is broken is worse than no check**, because it is evidence pointing the
wrong way.
