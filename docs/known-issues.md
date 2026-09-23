# Known issues and open questions — Arcade-JalecoMS1BCD_MiSTer

Numbered `MS1-n`, in the style of the NMK16 and Sand Scorpion lists: each entry
records what was measured, how, and what is still unknown. An entry is only
closed by a measurement, never by reasoning.

**Four are open**: two from M0 answerable off-board, MS1-31 which needs the
board, and MS1-33 from M3. MS1-32 closed as a misdiagnosis of MS1-57; MS1-60
fixed, with the budget measured but the symptom itself still not demonstrated
pixel for pixel.

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
| MS1-28 | A fractional clock divider whose accumulator is one bit too narrow | closed |
| MS1-29 | jt51 samples `write` on `cen`, so a one-clock strobe never raises `busy` | closed |
| MS1-30 | `screen_flag` bit 4 is a reset line over the whole sound subsystem | closed |
| MS1-31 | Matching MAME's OKI status means matching a hack MAME admits to | **OPEN** — only real hardware can settle it |
| MS1-32 | A tile-fetch lookahead trades fidelity for cache tolerance | closed — misdiagnosed; it is MS1-57's wrap, and the lookahead is faithful once that is fixed |
| MS1-33 | A savestate round trip leaves one counter digit behind | **OPEN** — bounded at 25 pixels, cause not yet named |
| MS1-34 | A restore written in its own always block does nothing, silently | closed |
| MS1-35 | A probe that parks the CPU to look at it measures itself | closed |
| MS1-36 | Resetting the sound subsystem changes main-CPU behaviour | closed — the savestate park handshake, not a datapath |
| MS1-37 | Nine arrays do not infer as RAM; the core does not fit | closed — every array now block RAM; registers 996504 -> 11630 |
| MS1-38 | quartus_map catches the MS1-34 driver class that Verilator ignores | closed — run synthesis as a linter from M1, not at M4 |
| MS1-39 | Four OSD features have no core port, so the top level omits them | closed — all four measured on the board; 69 % ALM, 544/553 M10K, timing met |
| MS1-40 | The .mra's 2 MHz sample-clock bit is decoded but reaches nothing | closed — `oki_2mhz` port on ms1_sound.sv; 48/24 instead of 48/12 |
| MS1-41 | hayaosi1's three-player panel does not fit the pad or the .mra button list | **OPEN** — buttons 4/5 keyboard-only, player 3 unmapped; peekaboo's four are mapped |
| MS1-42 | peekaboo's SYSTEM port is 16 bits and the I/O mux is 8 | closed — `in_sys_hi`; System D reads the whole word at 0F0000 |
| MS1-43 | The protection MCU is a multicycle island timed as if it ran at 48 MHz | closed — SDC multicycle 4; -13.703 ns -> +3.901 ns |
| MS1-44 | The mode byte fans out further than any other signal and is timed as data | closed — reset tail + false path; -2.153 ns -> passing |
| MS1-45 | The sound harness stopped building, then stopped running, and said neither | closed — two stale inputs; ym=0 looked like healthy silence |
| MS1-46 | Two .mra names contain a colon, which no FAT filesystem accepts | closed — generator sanitises; tar had half-installed the tree |
| MS1-47 | MiSTer never sends an empty `<switches>` block, so the mode byte never arrives | closed — real DIP tables extracted from `mame -listxml`; verified booting on the board |
| MS1-48 | A failed Quartus compile leaves the previous .rbf and reports through a zero exit | closed — build.sh greps the log, not the exit code |
| MS1-49 | The .mra shipped the 68000 image byte-swapped, and --check validated it against itself | closed — MEASURED on hardware; my first diagnosis had it backwards |
| MS1-50 | Both 68000s handed the ROM cache their raw bus address | closed — held while the bus is not selecting ROM; SS-12 and NMK-21 are the same bug |
| MS1-51 | System B's second ROM bank was mapped one whole bank too far | closed — `{2'b10,...}` was word +0x40000 where the region wants word +0x20000 |
| MS1-52 | The MCU's IRF register never cleared an interrupt request | closed — MAME clears the named source; ours was a documented no-op |
| MS1-53 | The core ran before the .mra's <switches> arrived, with `mode` at its idle 3 | closed — reset now waits for index 254, not for a fixed tail |
| MS1-54 | The .mra's protection field reaches nothing: the core always runs the real MCU | closed for iosim — hayaosi1 and chimeraba boot; monkelf is MS1-55 |
| MS1-55 | monkelf needs direct input ports, a ROM patch and a PROM rebuild, not a protection model | closed — all four pieces; boots on hardware |
| MS1-56 | System D has no memory map: `mode == 2` falls into System B's | closed — map, 2 layers, 555 palette, own protection, main-CPU OKI |
| MS1-57 | The tile-fetch lookahead wrapped on the visible width, not the whole line | closed — every SDRAM-path line began with 8 pixels from column 128; the reference sim runs LOOKAHEAD 0 and could not see it |
| MS1-58 | The sim Makefiles do not depend on the RTL verilator finds through `-y` | closed — `RTLSRC` wildcard; a fix in ms1_video.sv left the old binary in place and the next run re-measured the bug |
| MS1-60 | The sprite pass overruns blanking by ~15 rows, so the top of the plane is read while it is still being drawn | fixed — clear swept behind the display read; 212970 -> 151372 clk, inside the 165888 budget |
| MS1-59 | Every game shows a five-pixel strip down the left of the screen | closed — the core's pixel lags its raster position by 5; measured 5 px -> 0 px against MAME on the board |

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


---

## MS1-28 — A fractional clock divider whose accumulator is one bit too narrow (closed)

The sound 68000 runs at 7 MHz, which does not divide 48 MHz evenly, so
`ms1_sound.sv` generates its phases with the usual fractional accumulator:

```systemverilog
reg [24:0] cpu_acc;
...
if (cpu_acc >= CLK_SYS[24:0] - (2 * CPU_HZ)) begin
    cpu_acc <= cpu_acc - (CLK_SYS[24:0] - 25'd2 * CPU_HZ[24:0]);
```

The idiom is right and the arithmetic is right. The **width** is not.
`CLK_SYS - 2*CPU_HZ` is 34,000,000, and 25 bits hold at most 33,554,431. The
threshold silently truncated to 445,568, the accumulator cleared it on almost
every clock, and `enPhi1` came out at about 23 MHz instead of 7.

Everything downstream inherited the error: the YM2151's timers ran fast, and
since megasys1.cpp:673 notes that the YM2151 clock is what decides the music
tempo, the sound CPU wrote its registers 3.3x too often. Measured against
MAME over 60 frames, the RTL issued 80 YM bus writes per frame against
MAME's 24.

What made this hard to see is that the divider still *looked* correct in
steady state — the ratio argument (`14e6 * N = P * 48e6`) is sound, so
re-reading the code proved nothing. It was settled by counting the enable
pulses directly:

```
per frame: phi1=413837 ym_cen=206918 ym_cen_p1=103459 (expect 124544 / 62272 / 31136)
```

Widened to 27 bits the same counter reports `124544 / 62272 / 31136` exactly.

The rule this leaves: **a fractional divider's accumulator must be wide enough
for the clock constant itself**, not for the value it usually holds, and the
cheapest possible check is to count the pulses per frame and compare against
`rate * frame_period` before trusting anything built on top.

## MS1-29 — jt51 samples `write` on `cen`, so a one-clock strobe never raises `busy` (closed)

The sound CPU's writes were decoded into a single 48 MHz clock pulse per bus
cycle. The YM2151 registers were programmed correctly by this — jt51's
register block runs on the raw clock (`jt51_mmr.v:131`) — so the timers came
out right and the write counts matched MAME frame for frame.

`busy` did not. It is generated in a different block, gated on `cen`
(`jt51_mmr.v:264`), which in this core is 1.75 MHz — roughly one pulse every
27 clocks of `clk_sys`. A one-clock strobe is invisible to it, so `busy` never
asserted, the status register never returned `0x80`, and the sound driver's
busy-poll loop never waited.

MAME, reading the same register over 60 frames, saw:

```
0000 143306   0001 1144   0080 1740
```

The RTL saw `0x0080` zero times. Tying the strobe to the bus cycle was not
enough either: the 68000's data strobe is only about 10 clocks wide against a
27-clock `cen` period, so it still missed roughly two times in three. Holding
the strobe until one `cen_p1` has actually sampled it brought the RTL to
`0080` x1968 against MAME's x1740.

jt6295 is the opposite case — it edge-detects `wrn` on the full clock
(`jt6295_ctrl.v:44`) — so the OKI strobes stay one cycle wide. **Two vendored
chips in the same module, two different strobe requirements**; neither is
documented in a port comment, and only reading the sampling clock of each
individual block tells you which is which.

## MS1-30 — `screen_flag` bit 4 is a reset line over the whole sound subsystem (closed)

With the clock and the strobe fixed, the RTL matched MAME's YM writes
**tick for tick** — 555 ticks against 555 through frame 51, including the
irregular 13-tick frames at 12, 18 and 48. Then at frame 52 MAME stopped
dead for seven frames and restarted with a full timer re-initialisation,
while the RTL played straight on.

Nothing in the sound CPU's own inputs explains that. The latch was checked
and reads `0000` throughout; no interrupt is ever taken on either side (the
driver runs at SR mask 7 and polls, and neither MAME nor the RTL ever fetches
the vector at `0x70`); the OKIs are untouched in that window.

The cause is on the *main* CPU's side, in a register that reads like a video
one (`megasys1_v.cpp:253`):

```cpp
m_audiocpu->set_input_line(INPUT_LINE_RESET, BIT(m_screen_flag, 4) ? ASSERT_LINE : CLEAR_LINE);
opm->reset_w(!BIT(m_screen_flag, 4));
if (BIT(m_screen_flag, 4) && m_oki[0].found()) m_oki[0]->reset();
```

`screen_flag` bit 4 holds the sound 68000, the YM2151 and both OKIs in reset
together. Games use it between tunes. Captured from MAME it is exactly the
missing event:

```
frame 52 -> 1,  frame 53 -> 0
```

Replaying it at frame granularity reproduced the stop and the restart but left
a constant 18-write offset, because MAME's write lands 651342 clocks into
frame 52 rather than at its boundary. Logged with `manager.machine.time` —
never `scr:vpos()`, which throws inside a memory tap (MS1-20) — and replayed
on the same cycle, the RTL matches MAME on **every one of the first 60
frames**, 1160 writes against 1160.

The lesson is about where to look: three separate measurements confirmed the
sound subsystem was internally correct, and the remaining difference was an
input nobody had thought to model, sitting behind a register named after the
screen.


## MS1-31 — Matching MAME's OKI status means matching a hack MAME admits to (open)

`megasys1_state::machine_reset()` sets `m_ignore_oki_status = 1` for every set
in the driver except hachoo, so `oki_status_r()` returns 0 rather than the
chip's real status. The driver says plainly why (megasys1.cpp:679):

> Note that some games' music is severely slowed down and out of sync
> (avspirit, 64street) by the fact that the game waits for some samples to be
> played entirely (M6295 status register polled) but they take too much time
> ... A temporary fix is to make the status of this chip return 0.

So this is not a property of the hardware. It is MAME compensating for its own
OKI timing, and it changes observable behaviour: the sound CPU polls that
register and waits on it, so with a real status it takes a different path and
writes at a different rate.

That puts M2 gates (3) and (4) in an awkward position. They are defined against
MAME, and to match MAME the core must return 0 — which is what
`ms1_sound.sv` does when `oki_status_real` is low, and what the sim harnesses
set. But a core that ships that way is reproducing a documented emulator
workaround rather than the board.

The port is therefore already there and already plumbed out to the core
boundary, defaulting to MAME's behaviour so the gates measure what they
claim to measure. **What is not yet decided is what the MiSTer top level
should pass**, and that cannot be decided here: it needs the real thing, with
both settings, on the two games the comment names. Until then the gate numbers
below should be read as "matches MAME", not "matches hardware", and the
difference is confined to this one bit.

The related question — whether jt6295's sample timing is close enough that a
real status would work where MAME's does not — is answerable the same way and
at the same time.


## MS1-32 — A tile-fetch lookahead trades fidelity for cache tolerance (closed, misdiagnosed)

> **Superseded by MS1-57.** Everything measured below is real; the cause given
> for it is not. The lookahead does not sample scroll registers at the wrong
> time and does not trade fidelity for anything. It wrapped on `VIS_W`
> instead of on the whole raster line, so the eight fetches feeding each
> line's first eight columns addressed columns 128..135. Re-measured on the
> same set: **98 of 98** differing pixels satisfy `hw[x] == ref[x+128]`. The
> original text is kept below because the measurement in it is the evidence
> that closes it, and because the wrong inference is the instructive part --
> "the extent tracks the parameter one for one, which is the whole diagnosis"
> was true of the extent and not of the cause.

### Original text (2026, cause incorrect)

On the SDRAM path a tile byte comes from a cache, and the raster cannot wait
for a miss. The first attempt gave the fetch a head start by advancing the
video sample point by N pixels and growing the tilemap's latency by the same
amount, so net timing was unchanged. Misses went to zero. Frames did not match
the reference sim.

Every differing pixel was in the first N columns. At N=16 the diffs spanned
x = 0..15; at N=8, exactly x = 0..7. The extent tracks the parameter one for
one, which is the whole diagnosis:

`ms1_tilemap` reads `scroll_x`/`scroll_y`/`ctrl` combinationally at stage 0.
Advancing the sample point means the fetch for a line's first N pixels happens
while the PREVIOUS line is still on screen. avspirit writes scroll registers
during horizontal blanking on specific scanline bands (rows 85-91 and 113-127
in the frame measured), and the two paths then sample those registers on
opposite sides of the write.

So the lookahead is not a tuning knob with a safe value. Any N > 0 has the
same defect, N columns wide. The reference path (N=0) is the faithful one and
is what matches MAME 150/151.

**The fix is not a bigger lead.** `tile_prefetch_byte` has two address streams
for exactly this reason: the PREFETCH stream may be a predicted address, while
the USE stream stays on the true, unshifted sample point. A misprediction then
costs a miss, not a wrong pixel. The error here was driving the prefetch stream
from a time-shifted sample point, which moves the pen path with it. Doing it
properly means giving `ms1_tilemap` a second, prefetch-only address generator
running ahead of the pen pipeline rather than instead of it.

Measured at N=8: zero fetch misses across 3.44 M displayed pixels, 58 of 60
frames identical to the reference, the 2 that differ being 98 pixels each and
all at x < 8.

## MS1-33 — A savestate round trip leaves one counter digit behind (open)

Save the core at a frame boundary, run 8 frames, restore, run the same 8
frames, compare. Frames 0, 1 and 2 are pixel-identical. Frame 3 differs in 497
of 4741 lit pixels, and frames 4-7 in 25 each, always the same 14x7 glyph at
x 153-166, y 201-207.

What is established:

- **The image is not the problem.** A loopback -- park, stream out, stream the
  same image back in without letting the core run, stream out again -- reports
  **0 of 196608 words** different. Every region reads back exactly what was
  written.
- **State is identical for three frames.** A non-invasive probe, reading the
  arrays straight out of the model with no parking, reports game state
  bit-identical at K=1 and K=3.
- **The divergence is one character cell.** At K=5, `vram2` differs in 2 words,
  the first being tile code `F034` against `F030` -- one glyph, four apart. A
  counter is showing a different digit. `wram` differs in 98 words from
  0x07F76, which is stack.

What has been tried and did NOT change the result, byte for byte:

| attempt | effect |
|---|---|
| Capturing the sprite blit FSM (29 fields) | none |
| Capturing `mcu_data`, the protection answer | none |
| Restoring `iack_d`, `slatch_d`, `prot_we_pulse` | none |

Each of those was a real gap and each fix is kept on its own merits; none is
the cause. Note the sound side is ruled out by construction: `latch_to_main`
is unconnected in `ms1bcd_core`, so the YM2151's unrestorable internal phase
has no path to the video.

### 2026-09-21: the plane is exonerated and the shape of the bug changes

The sprite plane and all four object/sprite buffers were added to the
non-invasive probe. They are **bit-identical**, as are palette, object RAM,
vram0 and vram1. So the blit reproduces exactly across a restore, and the
sprite-FSM capture added earlier -- 29 fields, on a hypothesis that was wrong --
is not load-bearing for this bug (it is kept because a save can legitimately
land mid-pass).

Swept K = 1..5, the divergence is **pinned to frame 4** and is **static**: K=4
and K=5 report the same 98 words, the same addresses, the same values. It
happens once and does not compound.

```
wram   98 words  0x07F76..0x07FFF   -- every one has B=0000
    0x07F76  A=3528  B=0000     0x07F80  A=FFFF  B=0000
    0x07F78  A=35D2  B=0000     0x07F82  A=0043  B=0000
vram2   2 words
    0x0027B  A=F034  B=F030     0x0029B  A=F033  B=F030
```

`0x07FFF` is the last word of work RAM, so that range is the top of the stack.
**A has ~276 bytes of stack data there; B has none.** The two VRAM cells are
one tilemap row apart: a two-digit field reading "43" in A against "00" in B.

So B has not mistimed anything -- B has never executed what A executed. And
that reframes the defect. The round trip is save, run A, restore, run B; if the
image were complete B would reproduce A. The difference being static means
there is state that **span A modified and the image does not carry**, so at
restore time it holds span A's final value instead of the save-time value.

This is why six targeted fixes changed nothing by a single pixel: each added
state that was already being restored correctly. The image loopback cannot see
this class of bug at all, because it never lets the core run -- it proves
capture and restore agree, not that the set of captured things is complete.

### Bisected, and cornered inside the CPU

A debug reset mask (`ss_rst_dbg`) was used to make each subsystem enter both
spans from an identical state, with a control mask that pulses the same 80
ticks and resets nothing:

| mask | | result |
|---|---|---|
| 0 | no pulse | diverges |
| 8 | pulse, resets **nothing** | identical to mask 0 -- the pulse is not a confound |
| 1 | + sound reset | changes the pattern (explained by MS1-36, not a datapath) |
| 2 | + MCU reset | identical to mask 0 |
| 4 | + sprite reset | identical to mask 0 |

Neither the MCU nor the sprite engine holds the missing state. Chasing the
remaining candidate -- the CPU's interrupt path -- found and fixed a real
defect that was NOT this one (see below), and then the probe was extended to
compare scalars, which it had never done: eleven arrays and no scalars at all,
so the interrupt latches could have differed while it reported "identical".

With `irq1_h`, `irq2_h`, `irq4_h`, `iack_d`, `int1_dd`, `bufi`, `buf_busy` and
the raster all compared, at K = 1..4:

```
K=1,2,3  none -- game state is identical
K=4      wram 98 words 0x07F76..0x07FFF,  vram2 2 words
         (every scalar still identical)
```

So at the moment work RAM and the text layer diverge, memory is identical,
every interrupt latch is identical and the raster phase is identical. **The
difference can only be inside fx68k** -- its registers, PC or SR, none of
which reach RAM until something pushes them.

That is the boundary of what this probe can see. The park monitor reconstructs
the programmer's model by pushing D0-D7/A0-A6 to the game's stack and
restoring SSP/USP, returning through RTE; anything fx68k holds that is not in
the programmer's model is not carried, and cannot be observed from outside
either.

### fx68k's internals, read directly: it is a SKEW, not missing state

Rather than modify a vendored core on a hypothesis, fx68k's internals were
compared between the two spans through Verilator: all 18 register-file entries
(high and low), `PcL`/`PcH`, the `Irc`/`Ir`/`Ird` prefetch pipeline and
`intPend`, the CPU's own interrupt-pending latch.

```
K=1   USP(lo) A=FFBA B=FF78    PcL A=1584 B=10EA
K=2   USP(lo) A=FFBA B=0000    USP(hi) A=0007 B=0008   PcL A=2B84 B=26F6
K=3   D0(lo)  A=0000 B=0006    USP(lo) A=FFBA B=FF78   PcL A=4184 B=3CEC
K=4   + wram 98 words, vram2 2 words, Irc/Ir/Ird
```

Read carefully, this is not a missing-state signature:

- **Memory is identical at K=1, 2 and 3.** Both runs are doing the same work.
- `PcL` differs at every K, but that is the PC sampled at an arbitrary raster
  instant. Two runs one instruction apart show different PCs and mean nothing
  by it.
- `USP` differs, and A holds `FFBA` **constant** across all three. A user stack
  pointer that never moves means the game never leaves supervisor mode, so USP
  is a dead register here, not a cause.
- The register file, `intPend` and the prefetch all match until frame 4.

So the two runs are executing the same code, displaced in time, until at frame
4 an interrupt lands on the other side of some boundary and the paths genuinely
part. **The image is not missing a register; the resume does not land on the
same cycle.**

That is consistent with everything else this issue has recorded, and it
explains why seven fixes that added or corrected captured state changed the
result by exactly zero pixels: none of them addressed timing.

**Where the skew can come from**, now that state is excluded: the park monitor
takes a variable number of cycles between the `RESUME` write and its `RTE`,
because it exits through a `tst.w`/`beq` polling loop whose alignment depends
on when RESUME is seen. The raster is restored, and the CPU's own clock phase
is restored, but the number of cycles the monitor itself burns on the way out
is not necessarily equal in the two runs.

### Fixed: hold the machine still for the WHOLE window

The hold that existed covered only `ss_active`, the transfer. The park and the
resume either side of it ran free, so the raster advanced while the CPU
executed its monitor. Extended to `ss_freeze | ss_active | ss_resume`:

| | before | after |
|---|---|---|
| frame 3 after restore | 497 px | **25 px** |
| `fx68k PcL` | differed at every K | no longer differs (2 apart at K=1, was ~0x500) |
| `fx68k D0` | differed | no longer differs |

**A savestate park is not a pause and cannot be implemented as one.** The first
attempt held everything and deadlocked: freezing the MCU divider stopped
`mcu_cen_tick`, the TLCS-90 could never reach an instruction boundary,
`ss_mcu_frozen` never asserted, and since `ss_frozen` needs all three CPUs the
park timed out. The park is executed BY the machine being held still. What may
be held is only what the game observes but does not need in order to park:

| | during park | during transfer |
|---|---|---|
| raster | held | held |
| 68000 clock enables | run (they execute the monitors) | held |
| MCU divider | runs (must reach a boundary) | held |
| YM/OKI enables | held | held |

This also means OSD pause and the savestate freeze are **not** the same signal,
and M4 should not try to make them one.

### Retracted: the "USP" finding was a mislabelled register

The previous entry here claimed USP was isolated as the fault and that the
restore was handing back the reset stack pointer. **That was wrong on two
counts and is retracted.**

First, the probe's register names were backwards. `fx68k.sv:1169` reads:

```systemverilog
localparam REG_USP = 15;
localparam REG_SSP = 16;
```

The probe labelled 15 as SSP and 16 as USP, so everything reported as "USP"
was the **supervisor** stack pointer.

Second, and more important: **a stack pointer sampled at an arbitrary raster
instant is no more meaningful than a PC sampled there.** A7 moves constantly
as the game pushes and pops. Two runs an instruction apart show different A7
and it means nothing, exactly as was already said about `PcL` and then
promptly forgotten when a different register showed the same shape.

### What the four-moment trace actually established

`usp_reg` and `ssp_reg` were read directly out of the model at each step:

```
            usp_reg    ssp_reg    cpu reg[16] (=SSP)
pre-park    00000000   00000000   0007FFFC
1 parked    0007FFFC   0007FFBA   0007FFBA    <- monitor wrote it
2 streamed  image 0x1D012/13 = 0007FFFC
  reparked  0007FFFC   0007FF78   0007FF78
3 restored  0007FFFC   0007FFBA   0007FF78    <- image written back
```

**The park register path is correct.** `ssp_reg` follows the monitor's writes
(0007FFBA at the save, 0007FF78 at the re-park) and the image restores it
exactly. `usp_reg` holds 0007FFFC throughout because the game never touches
the user stack, which is the right behaviour, not a failure to update.

So the suspect named in the previous commit is exonerated by its own trace.

A limit of the instrument, noted so it is not misread later: the "4 resumed"
sample is taken after `release()`, which ticks only 128 times. The monitor
needs far longer than that to reload A7, pop 15 registers and RTE, so that row
shows the machine mid-exit and must not be read as a final state.

### Where this leaves it

- The window-wide hold was a real fix: frame 3 went from 497 differing pixels
  to 25, and the PC skew collapsed from ~0x500 to 2.
- Arrays are identical through K=3 and diverge at K=4 (wram 95 words, vram2 2
  words) -- the same 25-pixel glyph.
- The image is proven complete by loopback, the park registers are proven
  correct by direct trace, and MCU and sprite state are excluded by bisection.
- Register-file comparisons at frame boundaries are now known to be useless
  for PC and both stack pointers. Any future probe must compare them only at
  equivalent points in the instruction stream, or not at all.

The residue is 25 pixels on one glyph after a restore, from frame 3 onward,
with no identified cause. That is where it rests.


## MS1-37 — Nine arrays do not infer as RAM; the core does not fit (open)

See `docs/m4-ram-probe.md` for the full report. `quartus_map` on `ms1bcd_core`
fails with Error (276003): the arrays that do not infer as M10K become
flip-flops, roughly 1 Mbit of them on a device with about 83000 registers.

Inferred: `sram`, `obj_b1`, `obj_b2`, `spr_b1`, `spr_b2` -- each with exactly
one read and one write. Not inferred: `wram`, `vr0`, `vr1`, `vr2`, `pal`,
`obj`, `vreg`, `iram`, `ymsh`.

Two causes, both named in docs/PLAN.md 4.C before any of this was written:
asynchronous reads (`always @*` indexing an array) become flip-flops, and two
readers cannot share one array because an M10K's second port is the write.

The fix is registering every array read and duplicating arrays per reader. Both
change the video pipeline's timing, so **M1 and M2 gate 2 must be re-run after
it** -- the re-validation is the real cost, not the edit.

## MS1-38 — quartus_map catches the MS1-34 driver class that Verilator ignores (closed)

MS1-34 records that a savestate restore written in its own `always` block is
silently overwritten by the block owning the register, that this happened four
times in M3, and that "Verilator does not warn ... only structural care is" a
guard.

The second half of that was wrong. `quartus_map` catches the entire class in
seconds and refuses to elaborate on it:

```
Error (10028): Can't resolve multiple constant drivers for net "iram[0][7]"
Error (10029): Constant driver at ms1_iomcu.sv(162)
```

The first M4 synthesis run found eight more instances that M3 had left in the
tree -- `iram`, both sound latches, the sound interrupt latches, `chip_din`,
`chip_a0`, `ym_reg_sel`, `ymdiv` and `okidiv`.

Quartus was installed and working throughout M3. It was not run because
synthesis sat behind a milestone boundary in the plan. **Synthesis is a linter
for this class and should be run opportunistically from M1 onward.** A
`quartus_map` pass costs minutes and would have turned MS1-34 from a recurring
hazard into a single fix.


### MS1-37 closed (2026-09-22)

Every array in the core now infers as block RAM.

| | before | after |
|---|---:|---:|
| Combinational ALUTs | 986368 | **18655** |
| Dedicated logic registers | 996504 | **11630** |
| Block memory bits | 1826561 | **3401238** |
| Uninferred arrays | 9 | **0** |

332 of 557 M10K (60 %), about 14 % of the device's registers. Frames were
re-checked after every step: 70 of 70 identical, 16 with content, every time.

**Three remedies, chosen by how the readers relate.** This is the rule the
whole exercise produced:

| readers | remedy |
|---|---|
| mutually exclusive (CPU + savestate) | one registered read, address muxed |
| concurrent, sharing one address | read-or-write port, new-data read -> one true-dual-port set |
| concurrent, different addresses | duplicate, write both copies on the same clock |

The middle one came from NMK16's NMK-10, which had already hit this and
settled the coding shape with an isolated four-variant synthesis test: a plain
registered read is **old-data** on a same-address write, which Quartus 17 can
only meet with a simple-dual-port set PLUS a second full copy. Coding the port
as read-or-write returning the data being written makes it new-data, and one
set serves both readers -- free, because the 68000 never consumes the read of
a write cycle. That saved about 39 M10K on the three scroll VRAMs.

**Registering on `clk`, not on `ce`, is what made it free.** An address that
only changes on a pixel enable has eight clocks of slack, so the data is valid
one clock later and seven before it is used. The `VRAM_LAT` and `vpipe`
re-timing this work was planned around never had to happen.

**Two wrong turns, both from applying a technique without reading the
consumer.** Pipelining the buffer copies fixed one array and cost four others,
because each has two readers and registering only one made three ports. And
the sprite plane was misfiled as the true-dual-port case: `fb_wr_addr` is
registered from `cur_fb`, so when `fb_we` asserts the read address has already
advanced -- write and read are a pixel apart and cannot share a port. It needed
duplication, at 58 M10K.

**M10K is now the resource to watch, not registers.** 332 of 557 leaves 225 for
the framework, and docs/PLAN.md 4.C.4 records a silent cliff near 539/553 where
Quartus stops inferring the framework's own RAMs with no message at all. The
number to check is the total after `sys/` is added.

---

## MS1-39 — Four OSD features have no core port (closed)

`MS1BCD.sv` was adapted from `Arcade-SandScrp_MiSTer/SandScrp.sv`, which wires
Pause, High Scores, Cheats and Flip Screen into its core. `ms1bcd_core` had no
port for any of them, and they were absent from the CONF_STR rather than tied
to constants -- an OSD entry that does nothing reads as a broken core, not an
unfinished one.

All four are now in. The shape follows SandScrp's, including the status-bit
numbers, so the two cores' menus and docs line up.

### Pause — `O[29]`

A clock-enable gate over both 68000s and the MCU. **Re-timed onto `enPhi2`**
rather than masked with the raw bit:

```systemverilog
reg pause_68k = 1'b0;
always @(posedge clk) if (enPhi2) pause_68k <= pause;
```

`enPhi1`/`enPhi2` must strictly alternate or fx68k wedges mid-cycle; gating on
the raw OSD bit drops whichever half of the pair it lands on. The protection
MCU pauses with the main CPU -- it is in the middle of a handshake with it --
and the savestate engine **masks** pause (`& ~ss_busy`), because both CPUs
have to execute in order to reach the park monitor, so a paused core could
never be saved.

The YM2151 and the OKIs are deliberately NOT gated. Their cens carry envelope
and sample phase, and freezing those mid-note is audible on resume where
letting the note finish is not.

### Flip screen — `O[17]`

One XOR, in `ms1_video.sv`:

```systemverilog
wire flip = screen_flag[0] ^ osd_flip;
```

The block already implements the board's own 180-degree flip by mirroring the
sample point -- and that is not an assumption, the header records MAME
captured twice from the same point, flipped and not, coming out rot180 of each
other with zero differing pixels. The OSD bit composes with it exactly: a game
that flips itself and a monitor mounted upside down cancel. Doing it at the
sample point also means it reaches the analog I/O board and direct video, not
only the HDMI scaler.

### High Scores — `O[39]`, `R[30]` save, `R[31]` reset — and Cheats — `O[38:32]`

Both drive one work-RAM back door in `ms1_main.sv`, and only while they have
the CPUs paused. hiscore wins a collision; it runs on OSD open and cheats on
vblank, so in practice they never want the port at the same moment.

`hs_addr` is the **68000's own byte address**, as `hiscore.dat` and Pugsy's
tables write it. Every mode's work RAM is 64 KB aligned, so `hs_addr[15:1]`
indexes it on all three boards without a per-mode case -- and it lands
correctly on System B's mirror as well, since `0x078F8B` and `0x068F8B` have
the same low 16 bits.

**The back door writes ONE byte**, not a mirrored pair:

```systemverilog
if (~hs_addr[0]) wram[hs_wi][15:8] <= hs_din;
else             wram[hs_wi][7:0]  <= hs_din;
```

The work-RAM quirk that mirrors a byte write into both halves belongs to the
68000's write path (MAME's `ram_w`, "64th Street and Chimera Beast rely on
this"). Applying it here would corrupt the neighbouring byte of every score.
Splitting the write into byte lanes was the one real risk in this change --
`wram` and `wram_s` are 512 Kbit each and MS1-37 was fought over exactly this
inference -- so synthesis was run as a linter first, per MS1-38. Both still
infer as `altsyncram`; the only newly uninferred arrays are hiscore's five
config tables, which are far too small for an M10K and belong in LUTs.

"Reset Scores" needs two hold times from one counter: a short core reset so
the game rebuilds its table, then ~6 s holding the hiscore module down so it
cannot write the old scores back over the fresh ones. "Save Scores" has no
native path in the module -- it only extracts on a RISING edge of
`OSD_STATUS` -- so the request drives that input low for ~100 ms and lets it
go.

### The data, and the trap in regenerating it

The core carries seven fixed cheat slots because the CONF_STR is compiled into
the `.rbf` and shared by all sixteen sets, so a per-game menu of cheat NAMES
is not expressible; each `.mra` supplies its own game's addresses, and slots a
game has no cheat for are hidden through `status_menumask`.

| block | source | coverage |
|---|---|---|
| `<rom index="3">` + `<nvram index="4">` | MAME `hiscore.dat` | 12 of 16 |
| `<rom index="5">` | Pugsy's cheat XML | 14 of 16 |

The four without hiscore entries are `64streetja`, `chimeraba`, `edfb` and
`hayaosi1`; upstream simply has no block for them.

### Measured on the board

Driven headlessly: `/media/fat/config/<setname>.CFG` is the 128-bit OSD status
word, 16 bytes little-endian, read when the `.mra` is loaded, so each bit can
be set from the host and judged by its effect on the picture
(`tools/board_feature_test.py`'s method). `avspirit`, build
`d3cb996e817354b61eefc17d02b56fde`:

| feature | bit | measurement |
|---|---|---|
| Pause | `O[29]` | two shots 8 s apart: **48665** differing pixels off, **0** on |
| Cheats | `O[32]` | title screen reads **"CREDITS 99"** and "PUSH START BUTTON!" where the baseline read `CREDIT 0` |
| Flip screen | `O[17]` | picture turned 180 degrees -- `CREDIT 0` mirrored at the top left, the score row upside down at the bottom, energy bar moved from top to bottom |
| High Scores | `O[39]` | game still runs (57001 differing pixels over 8 s, so no NMK-24 freeze), and the table changes with the dump |

The high-score result is the one worth stating in full, because it is the
whole path and not just the wiring. Same screen, same delay after load, only
the dump differing:

| | 1ST | table |
|---|---|---|
| no `.nvm` | `100000 JAL` | the game's default ladder, 100000 down to 10000 |
| a crafted 83-byte `.nvm` | `0` | every entry zeroed, initials blank |

An 83-byte file written on the host reached the game's work RAM through ioctl
index 4, the hiscore module, the back door and `wram`, and changed what the
game draws -- which is the route a real saved score takes.

**Pause is the weakest of the four**, and deliberately reported as such: the
`.CFG` is read at load, so the core boots paused and the screen stays black,
which shows the CPUs are held but not that a RUNNING picture freezes. The
cheat result covers that gap -- `rtl/cheats.sv` pauses on vblank, writes, and
releases, so "CREDITS 99" on a running attract is mid-run pause, the back door
and the byte-lane write all proven at once.

**`tools/gen_ms1bcd_mra.py` rewrites each `.mra` from scratch, and these
blocks are added by two post-passes it knows nothing about.** Running it alone
deleted them, and the result is still perfectly well-formed XML -- which is
how NMK16 lost 616 lines across 27 files. Worse, both post-passes skip a file
that already has their block, so re-running them does not put anything back.
The base generator now carries the blocks over itself (`carry_over()`), and a
regeneration is idempotent: byte-identical output, verified.

## MS1-40 — The .mra's 2 MHz sample-clock bit is decoded but reaches nothing (closed)

The game-mode byte's bit 4 says the OKIM6295s run at 2 MHz rather than 4, and
`tools/gen_ms1bcd_mra.py` sets it for `hayaosi1`, `peekaboo` and `peekaboou`.
`MS1BCD.sv` decoded it into `oki_2mhz` and stopped there: `ms1_sound.sv`
divided 48 MHz by 12 unconditionally, which is the 4 MHz case.

Closed with System D (MS1-56), because System D needs it: `system_D` derives
its OKI clock as `XTAL(8'000'000)/4`, so a peekaboo running at 4 MHz plays
every sample at double speed. `ms1_sound.sv` now takes an `oki_2mhz` input
and counts to 23 instead of 11; both are exact divisions of clk_sys, so this
is a terminal value and not a second PLL. The counter widened from four bits
to five, which moved the sound savestate's scalar 5 packing (`okidiv` now
occupies bits 4:0, `ymdiv` 6:5, `chip_a0` 7).

Why those three sets run at 2 MHz at all is MS1-8, which MAME does not answer
either ("unknown OSC + divider combo").

## MS1-41 — hayaosi1's three-player panel does not fit the pad or the .mra button list (OPEN)

`hayaosi1` is a quiz cabinet, not a game with a joystick. Its `P1` and `P2`
ports carry no directions at all: they are eight buttons each, interleaved
across three players (buttons 1-5 per player, MAME
`INPUT_PORTS_START(hayaosi1)`), and `SYSTEM` has a START3.

Two things do not stretch that far:

- **The .mra's `<buttons>` list has five names** (Button 1-3, Start, Coin),
  which `tools/gen_ms1bcd_mra.py` writes for every set, so the pad reaches
  buttons 1-3 only. Buttons 4 and 5 are on the keyboard for player 1 (Left
  Shift and Z, MAME's own defaults) and unbound for players 2 and 3.
- **Only `joystick_0` and `joystick_1` are taken**, so player 3 has no pad.
  START3 is on the keyboard's 3 key.

The layout is selected without any new .mra field: `hayaosi1` is the only
System B set with simulated protection, so `mode == B && prot == 1` names it
exactly (`chimeraba` is the other `iosim` set and is System C).

Fixing it properly means a per-set button list in the generator and a third
joystick, which is a .mra change and a CONF_STR change, not a top-level one.

## MS1-42 — peekaboo's SYSTEM port is 16 bits and the I/O mux is 8 (closed)

`peekaboo` puts its six buttons in the HIGH byte of a 16-bit SYSTEM port
(MAME `0x0100`-`0x2000`), and `ms1_iomcu.sv`'s port mux is eight bits wide.
`MS1BCD.sv` mapped the low byte -- the four coin inputs and the two starts --
and the buttons were unreachable.

The premise turned out to be wrong in a useful way: System D does not read
SYSTEM through the I/O MCU at all. `megasys1D_map` has `0x0f0000.portr("SYSTEM")`
as a plain 16-bit port read, so widening the MCU's mux was never the fix. The
core carries a separate `in_sys_hi` byte from the top level down to
`ms1_main.sv`, and mode D's read mux returns `{in_sys_hi, in_system}` for the
whole word. On System B and C the extra byte is tied to zero and unused.

Three things came with it:

- **`P1` and `P2` are 8-bit PADDLES**, `PORT_MINMAX(0x18,0xE0)`, read through
  System D's own protection port (commands 0x51 and 0x52) rather than the MCU
  mux. Both are wired, from `hps_io`'s `paddle_0` and `paddle_1`, clamped to
  the same range. They are ACTIVE HIGH -- an analog value, not a switch -- so
  unlike every other port here they are not inverted.
- **The `<buttons>` list is per-set now** (MS1-41's first half). peekaboo's is
  six names, `Button 1,Button 2,Stage Clear,Option,Start,Coin`, because its
  third and fourth buttons are panel functions with names of their own.
- **That moves Start and Coin up one pad bit**, since MiSTer numbers pad
  buttons by position in the list. `p1_start`/`p1_coin` in `MS1BCD.sv` are
  named wires for exactly that reason: hard-coding `joystick_0[7]` put Start
  on peekaboo's "option" button and Coin on Start.

peekaboo's PORT_SERVICE is DSW bit 2, not a SYSTEM bit, so F2 goes there;
SYSTEM bits 0 and 1 are COIN3 and COIN4, which MAME's comments name "service"
and "test" but which are coin slots.

## MS1-43 — The protection MCU is a multicycle island timed as if it ran at 48 MHz (closed)

The first fit of the real project failed timing at **-13.703 ns** on clk_sys,
TNS -178.678, and every one of the twelve worst paths was the same pair:

```
tlcs90:u_cpu|val2[0]  ->  tlcs90:u_cpu|hl[8]
```

That path is about 34.5 ns, which is indeed hopeless against a 20.8 ns clock
-- except that it never has to meet one. `rtl/tlcs90/tlcs90.sv` holds its
**entire** datapath in a single

```verilog
always @(posedge clk) ... else if (cen) begin ... end
```

so every register in it advances only on `cen`, and `ms1_main.sv` drives that
from `mdiv`: once every 4 clk_sys cycles on System C and every 6 on B and D.
Both endpoints of the failing path are inside that block, so the path has 83.3
ns, not 20.8.

`JalecoMS1BCD.sdc` declares it, using 4 (the faster of the two modes):

```tcl
set tlcs_regs [get_registers {*|tlcs90:u_cpu|*}]
set_multicycle_path -setup 4 -from $tlcs_regs -to $tlcs_regs
set_multicycle_path -hold  3 -from $tlcs_regs -to $tlcs_regs
```

**`-from` matters as much as `-to`.** A path into the CPU from a register that
is *not* cen-gated -- the ROM cache's `din`, for one -- still has only a single
clk_sys period before the cen edge samples it. Writing `-to $tlcs_regs` alone
would relax those too, and would be wrong.

Nothing makes the gap shorter than 4: `mdiv` holds during a savestate park,
which only makes cens rarer, and `mdiv_max` changes only while the core is in
reset for the ROM download.

## MS1-44 — The mode byte fans out further than any other signal and is timed as data (closed)

With MS1-43 constrained, the next-worst paths were all

```
emu|dip_sw[2][1]  ->  tlcs90:u_cpu|val2[*]
```

at **-2.153 ns**. `dip_sw[2][1:0]` is `mode`, and it reaches further than
anything else in this design: the System B/C memory map, the main CPU and MCU
dividers, the layer geometry and the input layout all branch on it.

It is configuration, not data -- but only *just*. Every write to `dip_sw` is
gated on `ioctl_download`, and the old `reset` covered exactly
`ioctl_download`, so the byte could take its final value on the last cycle of
the transfer and the core could leave reset on the next one. A 34 ns fan-out
with one 20.8 ns cycle to settle is a real hazard, not a constraint artefact.

So the fix is in **both** files, and the RTL half comes first:

```verilog
reg [7:0] dl_tail = 8'hFF;
always @(posedge clk_sys) begin
	if (ioctl_download)        dl_tail <= 8'd0;
	else if (dl_tail != 8'hFF) dl_tail <= dl_tail + 8'd1;
end
wire dl_settling = (dl_tail != 8'hFF);
```

255 clk_sys cycles is 5.3 us. Only with that tail in `reset` is

```tcl
set_false_path -from [get_registers {*|dip_sw[*][*]}]
```

a true statement rather than a wish. Changing a DIP in the OSD re-sends ioctl
index 254 and therefore resets the game, which is how the sibling cores behave
too.

## MS1-45 — The sound harness stopped building, then stopped running, and said neither (closed)

Found while building the MiSTer top level, by trying to re-run the sound
simulation to check an unrelated one-line change. Two independent breakages,
stacked, each of which hid the other:

**1. It had not compiled since M3.** `sim/rtl/ms1_snd/Makefile` was missing
`-y $(RTL)/savestate`, and `ms1_sound.sv` gained `ss_m68k_park` in 5cba7f0.
Verilator could not find the module and the build failed. Nobody saw it,
because nothing re-runs this harness automatically.

**2. Once it compiled, it ran and produced nothing.** M3 also gave the sound
module the HW_ROMS handshake:

```verilog
wire srom_stall = as_active & sel_rom & ~rom_ready;
```

`tb_snd.cpp` predates that port and never drove it, so `rom_ready` sat at its
zero default, `srom_stall` was permanently true, DTACK never asserted, and the
sound 68000 never completed its first instruction fetch.

**What it reported while doing this is the point.** Everything a person would
check looked right:

```
latch commands: 15
sreset transitions: 3
after 2400 frames: ym=0 oki1=0 oki2=0  ymirq=0 iack=0
per frame: phi1=124544 ym_cen=62272 ym_cen_p1=31136 (expect 124544 / 62272 / 31136)
```

The latch replay loaded. The sreset trace loaded. Every clock-enable count
matched its expectation exactly — those are the MS1-28 counters, and they are
derived from the divider, not from the CPU, so they are happy whether or not
anything executes. 42.7 seconds of 48 kHz audio was written. The only wrong
number was `ym=0`, against MAME's 67204, and a silent WAV is indistinguishable
from a game that has not started making noise yet.

**This is MS1-18 and MS1-27 again**: a harness that measures its own plumbing
and passes. The lesson is the same one this project keeps relearning — a
zero is a result and must be checked against an expectation, not read as
"nothing has happened yet".

The fix is three assignments in `tb_snd.cpp` and one flag in the `Makefile`.
Both are committed with a comment naming the symptom, so the next person who
sees `ym=0` finds the explanation rather than repeating the bisect.

**And it invalidates a date, not a result.** `docs/m2-gate34.md` records
`avspirit 67204 / 67204` — that measurement was taken *before* M3 touched
`ms1_sound.sv`. It has been re-run since this was fixed; see the note there.


## MS1-50 — Both 68000s handed the ROM cache their raw bus address (closed)

Found on the board, by being pointed at the sibling projects' notes. Sand
Scorpion's SS-12 item 2 and NMK16's NMK-21 are the same bug:

> `rom_cache_n` refetches on any address change, so handing it the raw bus
> address makes every RAM, VRAM or I/O access start a speculative SDRAM read
> whose fill can land between the 68000's DTACK sample and its data latch.

Both of this core's CPUs did exactly that:

```systemverilog
assign rom_addr = b_rom1 ? {2'b10, a[17:1]} : a[19:1];   // ms1_main.sv
assign rom_addr = a[17:1];                                // ms1_sound.sv
```

`a` is the raw bus address, so every work-RAM, VRAM, palette, object and I/O
cycle started a speculative fetch on the program cache. The fix is the one
those projects settled on -- hold the address whenever the bus is not
selecting ROM:

```systemverilog
wire [18:0] rom_addr_live = b_rom1 ? {2'b10, a[17:1]} : a[19:1];
reg  [18:0] rom_addr_held;
always @(posedge clk) if (sel_rom) rom_addr_held <= rom_addr_live;
assign rom_addr = sel_rom ? rom_addr_live : rom_addr_held;
```

**Why no simulation here could see it.** The reference sim indexes a plain
array, so a speculative address costs nothing. The hardware-path sim drives a
`sdram_model` with no refresh, so a fill never lands late. The bug needs a real
controller on real silicon, which is the gap SS-15 already named: *"the
hardware path is verified in simulation" and "the hardware path is verified"
are different claims.* Re-running the reference frame sim with and without the
fix gives byte-identical results, which is the proof that it is a no-op
everywhere except on a board -- `rom_data` is only consumed under `sel_rom`,
and at the moment `sel_rom` rises the live address is muxed through
combinationally, so nothing is delayed.

This was a real bug and is fixed. It was **not**, on its own, enough to make
the board draw: see MS1-51.


## MS1-49 — The .mra shipped the 68000 image byte-swapped (closed, measured on hardware)

**This entry was first written with the conclusion the wrong way round, and
the correction is the point.**

`gen_ms1bcd_mra.py` does two things: it writes the `.mra`, and `build_stream()`
models the byte stream MiSTer will build from it. The two disagreed about
which half of an `<interleave output="16">` pair supplies the even byte, and
`--check` compares the `.mra`'s parts against that same model -- so it reported
OK for all 17 sets while the shipped image was byte-swapped.

**First diagnosis, from reading another project's .mra: wrong.** Sand
Scorpion's working `.mra` puts MAME's offset-0 chip on `map="10"`, so I
concluded `map="10"` supplies the even byte, that the model was inverted, and
that the `.mra` was fine. That core stores its 68000 image with its own
convention, so its map attributes say nothing about this one.

**What settled it was the board.** With the golden-byte audit walking the
sound region through the real cache:

```
snd word0 = 0x0F00   where the core needs 0x000F
```

a clean byte swap, with the offset-1 chip on `map="01"` at the time. So
`map="01"` supplies the EVEN byte, the model was right, and the `.mra` was
emitting the pair the wrong way round. The fix is in `parts_xml`: the
**offset-0** chip goes on `map="01"`.

Afterwards, on the same bitstream, with nothing changed but the `.mra`:

| region | before | after | expected |
|---|---|---|---|
| sound word 0 | 0x0F00 | **0x000F** | 0x000F |
| sound region sum | 0x242D | **0x42CA** | 0x42CA |
| MCU region sum | 0xD4F1 | 0xD4F1 | 0xD4F1 |
| non-black pixels | 0 | **3,154** | — |

and `avspirit` went from a black screen to executing its own boot code and
drawing text. `build_stream()` now also produces a stream byte-identical to
`sim/rtl/ms1_hw/roms/avspirit_ioctl.bin`, which was generated by the separate
`gen_ms1bcd_ioctl.py` and is what the hardware-path simulation was validated
against -- two independent code paths agreeing, which is what docs/PLAN.md 1.5
asks for and what `--check` alone could never establish.

**The lesson is the one this project keeps relearning.** A self-referential
check passes forever; a cross-check against an independently produced artefact
does not. The sibling project's `.mra` looked like evidence and was not --
only the measurement was.

## MS1-51 — System B's second ROM bank was mapped one whole bank too far (closed)

The board booted `avspirit` and stopped on the game's own `ERROR TRAPED /
WATCH DOG TIMER` screen. Everything about that was a symptom; the cause was one
expression in `ms1_main.sv`.

### The chain, shortest first

`assign rom_addr = b_rom1 ? {2'b10, a[17:1]} : a[19:1];`

`rom_addr` is a WORD index. System B's second program bank (CPU
0x080000-0x0BFFFF) continues the same SDRAM region straight after bank 0, at
BYTE +0x40000, which is WORD +0x20000. `{2'b10, a[17:1]}` is word 0x40000 =
byte 0x80000: one whole bank too far, at or past the end of `MAIN_SIZE_B`
(0x80000 bytes), where every fetch reads zero. The comment beside it said
"+0x40000" and meant bytes; the code added that many words.

`avspirit` survives about 309 frames on that, because nothing dereferences the
bank-1 pointer table until a scene transition. Then, at ROM 0x0030C6:

```
2079 0008 0000    MOVEA.L ($080000).L, A0
...
33D8 0007 8F46    MOVE.W  (A0)+, ($78F46).L
```

| | reads at 0x080000 | then indexes | writes to 0x078F46 |
|---|---|---|---|
| MAME | 0008 000C | 0x08008A, 0x082BDC | 0000 |
| core (before) | **0000 0000** | 0x00007E, 0x0011EA | **4E75** (an RTS, from low ROM) |

With a null base it copies low-ROM opcodes into work RAM, and a later routine
copies that work RAM into the video registers -- which is the `0x4E7F` that
appears in the layer-enable register at frame 310. The 68000 then stops
servicing the protection handshake (IRQ2 freezes), the MCU idles 47 frames and
takes its own `DI; HALT` error path at ROM 0x0227, and the game's software
watchdog paints the screen the board showed.

### Why nothing caught it

- **The frame gates run 70 frames.** This needs 309. Re-running the identical
  70-frame comparison before and after the fix gives byte-identical output
  (`5 exact, worst 1812` at offset 50, both) -- the first 70 frames never touch
  bank 1.
- **The golden-byte audit could not see it.** It drives `audit_addr` straight
  into `rom_hw`'s `a_main` mux, bypassing `rom_addr` entirely. It proves the
  download, the SDRAM and the cache; it says nothing about the CPU's own
  address arithmetic. That is why main, sound and MCU all audited exact
  (0xE54D / 0x42CA / 0xD4F1) while the CPU was reading zeros.
- **It is not hardware-specific.** The reference simulation -- plain arrays, no
  SDRAM, no caches -- fails identically, which is what finally ruled out the
  ROM byte order, the cache sizes, port-3 arbitration and refresh.

### Scope

System B only. System C reads its program through `c_rom0`, a single 512 KB
bank using `a[19:1]`, and never takes this path. So `avspirit`, `monkelf`, the
four EDF sets and `hayaosi1` -- 7 of the 17 sets. System D uses the same
`~is_c` path and would have been wrong too, but its memory map is not
implemented (PLAN 2.5).

### Result

450 frames of `avspirit` in the reference sim, against the two points that used
to fail:

| | before | after |
|---|---|---|
| frame 310 | `act=4E7F`, IRQ2 frozen at 3874 | `act=000F`, IRQ2 3874 and climbing |
| frame 357 | `mcuacc` frozen, `halt=1 if=0` | `mcuacc` rising, `halt=0 if=1` |
| frame 450 | (dead) | IRQ2 5938, `mcuacc` 14,117,787 |

Over all 450 frames `dbg_active` is only 0x0000 (53 boot frames) or 0x000F
(397), never 0x4E7F, and no frame has `halt=1`.

**Not yet re-run on hardware**, and the frame-accuracy gate is a separate
measurement that this does not by itself settle.

## MS1-52 — The MCU's IRF register never cleared an interrupt request (closed)

Found while chasing MS1-51. `tlcs90_periph_ref.sv` treated a write to IRF
(0xFFC3, register 0x03) as a no-op, with a comment explaining why that was
acceptable:

> manual IRF clearing only matters for sources not modeled yet
> (INT0/INT1/INT2/serial), so this is a real, narrow gap, not a blanket stub.

That reasoning was sound for the NMK004, where the only live sources are
timers that auto-clear on dispatch. On Mega System 1 the MCU's only sources
**are** INT0 and INT1 -- the 68000's protection write and the display-enable
edge -- so the gap was squarely in the path.

MAME implements it:

```cpp
void tlcs90_device::irf_clear_w(uint8_t data)
{
    if (data >= int(INTSWI) + 2 && data < int(INTMAX) + 2)
        clear_irq(data - 2);
}
```

The written byte is an interrupt index + 2. In MAME's enum INT0 is 3 and our
`irq_pending` bit 0 is INT0, so our bit is `data - 5` across all eleven
maskable sources. The peripheral now decodes the write into a one-hot
`irq_clr` and the CPU applies it as
`irq_pending <= (irq_pending | irq_req) & ~irq_clr`, leaving the dispatch
clear later in program order so it still wins for the bit it takes.

**This did not fix MS1-51** -- the reference sim still freezes at frame 310
with irq2=3874, identically -- and the 70-frame frame comparison is unchanged
before and after. It is kept because it is a real divergence from the
reference model that was documented as a known gap, and MS1 is the first user
to put those two interrupt sources on the critical path.


## MS1-53 — The core ran before the <switches> arrived, with `mode` at its idle 3 (closed)

With MS1-51 fixed, `avspirit` ran to its attract mode in simulation and on the
board -- but only in bitstreams built with `DBG_AUDIT = 1`. With the debug
instruments off, the same RTL drew a 256x224 frame of pure black.

### The bisect

Three builds, one flag at a time, each loaded on the board:

| build | DBG_OVERLAY | DBG_AUDIT | result |
|---|---|---|---|
| A | 1 | 1 | attract runs (high-score table) |
| B | 0 | 0 | black, 6 samples identical |
| C | 0 | 0, 0.35 s reset tail | black, 3 samples identical |
| D | **0** | **1** | attract runs (4599 / 2116 / 11552 bytes, changing) |

D is the one that matters: the overlay is irrelevant, the audit is not. The
audit's only side effect on the core is that it holds it in **reset** for the
~0.56 s it takes to walk the ROM regions.

### The cause

The `.mra` sends `<switches>` as a **separate ioctl session on index 254,
after** the ROM on index 0, and the gap between the two is however long MiSTer
takes to reopen the `.mra` and the zip -- measurably longer than 0.35 s. Until
those three bytes land, `dip_sw[2]` reads its idle `FF`, so `mode` is 3, which
the ROM-base mux resolves to **System D's bases on a System B game**. The core
spent that gap fetching from the wrong addresses, and did not recover when the
switches finally arrived and reset it.

`DBG_AUDIT = 1` hid it by accident, holding the core in reset across the gap.

### The fix, and two wrong guesses before it

Reset now waits for the switches to actually **arrive**, not for a duration:

```systemverilog
always @(posedge clk_sys) begin
    if (ioctl_download) begin
        sw_tmo <= 28'd0;
        if (ioctl_wr && ioctl_index == 16'd254) sw_seen <= 1'b1;
    end else if (~&sw_tmo) sw_tmo <= sw_tmo + 1'd1;
end
wire wait_switches = ~sw_seen & ~&sw_tmo;
```

with a 2.8 s timeout so a `.mra` carrying no `<switches>` block still boots.

Two attempts missed first, both from reasoning instead of bisecting:

1. **A longer fixed tail.** `dl_settling` was widened from 255 cycles to 2^24
   (0.35 s). Still black -- the gap is longer than that, and no fixed number is
   the right answer to "wait until a thing happens".
2. **A stale `config/dips/*.dip`.** MiSTer copies a saved `.dip` over the whole
   switches value including byte 2, which would have explained it. Checked on
   the board: no such file existed.

### Verified on hardware

Both instruments off, `avspirit` through `AVSTEST.mra`: the attract mode runs
and animates -- the ranking table, then the story sequence with its character
portraits and text, four screenshots of changing content. The same build that
was uniformly black before this change.

**This is a top-level bug, not a core one**, and it applies to any `.mra` whose
third `<switches>` byte the core needs before it can run -- which here is all
17 of them. It is also MS1-47's other half: that entry is about MiSTer never
*sending* an empty block, this one about the core not *waiting* for a block
that is sent.


## MS1-47 — MiSTer never sends an empty `<switches>` block (closed)

The generator emitted

```xml
  <switches default="FF,FF,00">
  </switches>
```

for all 17 sets. MiSTer only sends the index-254 session when that element has
`<dip>` children, so the block never arrived, `dip_sw[2]` kept its idle `FF`,
`mode` read 3, and every ROM base fell through the `(B : C : D)` mux to System
D. Adding a single throwaway `<dip>` was enough to prove the mechanism during
bring-up; this closes it properly.

### The DIP tables come from MAME, not from reading the driver

`tools/extract_ms1_dips.py` runs `mame -listxml` per set and writes
`tools/ms1_dipdata.py`. Using MAME's own output rather than parsing
`megasys1.cpp` means `PORT_INCLUDE`, `PORT_MODIFY` and the `COINAGE_8BITS`
macro are already resolved, and each setting's default is marked -- all of
which a hand parser would have to re-derive.

Three things the conversion has to get right, each of which has bitten a
sibling project:

- **`bits` is a RANGE**, `"first,last"`. Writing the individual bit numbers
  makes MiSTer read the field at the wrong width (NMK16 shipped `1C_1C` showing
  as `1C_4C` that way).
- **`ids` are indexed by the field's RAW value, value 0 first**, and must be
  2^width long with no holes. So an active-low `PORT_SERVICE` comes out
  `"On,Off"`, not `"Off,On"`.
- **System D has one 16-bit `DSW` port**, not `DSW1`/`DSW2`. It maps at bit
  offset 0 across both bytes; handled explicitly, and peekaboo went from 0
  switches to 10 once it was.

MAME lists only distinct settings, so a field can have fewer entries than
2^width. Across all 17 sets that happens only on the 4-bit Coin A / Coin B,
where the driver's own commented-out lines (`COINAGE_8BITS`) show values 1-5
are duplicates of `1C_1C`. Those are filled from that fact; anything else is
filled with `Undefined` and **reported**, so a new gap cannot pass silently.
Re-running the extractor reports none.

### It also fixes the defaults, which were simply wrong

The flat `FF,FF` was not MAME's default for most sets:

| set | was | MAME |
|---|---|---|
| avspirit, monkelf, 64street x3 | FF,FF | FF,**FD** |
| chimerab, chimeraba | FF,FF | **BD**,FF |
| cybattlr | FF,FF | FF,**BF** |

### Verified

All 16 shipped `.mra` parse, every one carries `<dip>` entries, and every id
list is exactly 2^width long. The ROM streams are byte-identical to before
(`--check` clean on all 17). On the board, `avspirit` boots and runs its
attract mode through a `.mra` carrying the real generated block -- the same
file the repository ships, with only its `zip=` pointed at the test set,
because this board's own `avspirit.zip` has no MCU in it.

**Not verified:** that the OSD's DIP submenu renders and cycles correctly.
That needs driving the OSD on the board and reading it back.


## MS1-54 — The .mra's protection field reaches nothing (OPEN)

Sweeping every System B set on the board, three screenshots each, 10 s apart,
70 s after load:

| set | protection | result |
|---|---|---|
| avspirit | mcu | attract runs |
| edf | mcu | attract runs |
| edfa | mcu | attract runs |
| edfb | mcu | attract runs |
| edfu | mcu | attract runs |
| **monkelf** | **none** | **black, 3 identical frames** |
| **hayaosi1** | **iosim** | **black, 3 identical frames** |

The split is exactly the protection type: every `mcu` set works, neither of
the others does.

### Why

Both failing sets ship a **zero-filled** MCU region, correctly:

```xml
<!-- iomcu 0x004000 @ 0x0C0000 -->
<!-- mo-91044.mcu: undumped. Omitted; the core uses simulated protection. -->
<part repeat="0x4000">00</part>
```

`monkelf` is a bootleg with the protection removed and `hayaosi1`'s TMP91640
is `NO_DUMP`. The core runs its TLCS-90 on those 16 KB of `0x00` -- which is
NOP -- so the MCU executes nothing, never answers the handshake, and the 68000
waits forever.

The `.mra` already says which kind each set needs: the game-mode byte's bits
6:5 (0 MCU, 1 simulated, 2 none, 3 System D's own), which
`tools/gen_ms1bcd_mra.py` has always emitted and `MS1BCD.sv` decodes into
`prot_sel`. **`ms1bcd_core` has no port for it**, so `prot_sel` goes nowhere
and the MCU always runs. `grep -i "iosim\|prot_sel\|prot_type\|has_mcu"`
over `rtl/` returns nothing.

### This is a scope decision catching up, not a regression

`docs/PLAN.md` 2.2 is explicit: *"The plan takes the exact path for B and C,
because the CPU core already exists."* The behavioural model was consciously
skipped. What the sweep adds is the cost: it leaves 2 of the 7 System B sets
unable to boot, and by the same argument `chimeraba` (System C, `iosim`) will
fail too -- 3 of 16 shipped sets.

### What it needs

The tables are already written down in PLAN 2.2, from the driver:

```
hayaosi1   0x51 0x52 0x53 0x54 0x55   0xFC 0x06
chimeraba  0x56 0x52 0x53 0x55 0x54   0xFA 0x06
```

Seven command values selecting SYSTEM / P1 / P2 / DSW1 / DSW2 plus two fixed
replies. So:

1. a `prot [1:0]` input on `ms1bcd_core`, wired from the top's existing
   `prot_sel`;
2. a table-driven responder for `iosim` that answers the protection port
   directly and raises IRQ2, with the MCU held in reset;
3. whatever `none` means for `monkelf` -- the bootleg's program is patched, so
   this needs checking against MAME rather than assuming the port is unused.

`oki_2mhz` is in the same position: decoded in the top, no core port (MS1-40).


## MS1-54 addendum — the iosim path, and the two things the table alone did not cover

`prot[1:0]` now reaches the core from the `.mra` game-mode byte, the MCU is
held in reset whenever it is not the selected protection, and `prot == 1`
answers the port from MAME's `ip_select_w` table:

| index | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| returns | SYSTEM | P1 | P2 | DSW1 | DSW2 | 0x0d | 0x06 |
| hayaosi1 (B) | 51 | 52 | 53 | 54 | 55 | FC | 06 |
| chimeraba (C) | 56 | 52 | 53 | 55 | 54 | FA | 06 |

hayaosi1 is the only System B set using iosim and chimeraba the only System C
one, so `is_c` picks the table -- no new `.mra` field. An unmatched command
latches nothing **and raises no IRQ**, as MAME's early return does.

That table on its own left hayaosi1 exactly as dead as before. Diffing the
68000 bus against MAME found both missing pieces, and neither is in the table:

**1. IRQ2 comes from the RASTER, at scanline 16.** MAME has two scanline
callbacks for B/C. The MCU one routes that edge to the MCU's INT1; the
**non-MCU** one raises IRQ2 on the main CPU directly:

```c
TIMER_DEVICE_CALLBACK_MEMBER(megasys1BC_scanline)
{
    megasys1bc_handle_scanline_irq(scanline);   // 240 -> IRQ4, 96 -> IRQ1
    if (scanline == 0 + 16)
        m_maincpu->set_input_line(2, HOLD_LINE);
}
```

Without it hayaosi1 sits in `STOP #$2100` at 0x0018EA waiting for IRQ2, takes
the level-4 vector instead, and never reaches the code at 0x001902 that sends
a command -- so no command ever arrives to raise IRQ2 the other way. The
traces were identical for **79** accesses and then MAME fetched vector 0x68
where this core fetched 0x70.

**2. The latch resets to 0x06, not 0.** MAME's own comment is the whole
explanation:

```c
m_ip_latched = 0x0006; /* reset protection - some games expect this initial
                          read without sending anything */
```

hayaosi1 is one of them: its first protection access is a **read**, before any
command, and it compares the result against 6. With the latch at 0 the traces
agreed for **96** accesses and diverged on exactly that read.

### Result

| | bus accesses agreeing with MAME |
|---|---:|
| table only | 79 |
| + raster IRQ2 | 96 |
| + latch resets to 0x06 | **41,587** |

On hardware, with the `.mra` files the repository ships (only `zip=` repointed
at a test set): **hayaosi1** runs its attract -- three contestant panels, a
Japanese quiz question, answer choices, INSERT COIN -- and **chimeraba** runs
its demo with the creature sprite, instruction text and DNA status bar.
`avspirit` and `edf` are unchanged on the board (4599/2116 and 7953/12781,
the same sizes as before), and the reference frame comparison for `avspirit`
is byte-identical before and after.

**Still open:** hayaosi1's frames do not match MAME's reference capture (0 of
120 exact). The bus runs 41,587 accesses in lockstep first, so this is a later
divergence rather than a failure to boot, and MAME flags this machine
`MACHINE_IMPERFECT_GRAPHICS` in the first place (PLAN open question 8).

## MS1-55 — monkelf needs ports, a patch and a PROM rebuild, not a protection model (OPEN)

Grouped with MS1-54 at first as "prot = none". It is not: the bootleg has no
protection device, and MAME gives it a different memory map and two init-time
fixups.

```c
void megasys1_state::megasys1B_monkelf_map(address_map &map)
{
    megasys1B_map(map);
    map(0x044200, 0x044205).w(FUNC(monkelf_scroll0_w));
    map(0x044208, 0x04420d).w(FUNC(monkelf_scroll1_w));
    map(0x0e0002, 0x0e0003).portr("P1");
    map(0x0e0004, 0x0e0005).portr("P2");
    map(0x0e0006, 0x0e0007).portr("DSW1");
    map(0x0e0008, 0x0e0009).portr("DSW2");
    map(0x0e000a, 0x0e000b).portr("SYSTEM");
}

void megasys1_state::init_monkelf()
{
    m_rom_maincpu[0x00744/2] = 0x4e71; // weird check, 0xe000e R is a port-based trap?
    // convert bootleg priority format to standard
    ...
}
```

So it needs, in order of where the work lands:

1. **Direct input reads at 0x0E0002-0x0E000B** -- core work, and a fifth
   decode case rather than a protection model.
2. **A ROM patch**, `0x00744` to `0x4E71`. `.mra` can do this with `<patch>`.
3. **A rebuilt priority PROM** -- the bootleg's format is nibble-packed and
   MAME expands it at init. This can be done in the generator so the `.mra`
   ships the converted table.
4. **Its own scroll register writes** at 0x044200/0x044208.

`prot == 2` currently reads the port back as 0, which is what MAME's iosim
state does with no command table installed, and is enough to keep the core
well-defined -- but it is not enough to run the game.


## MS1-55 addendum — all four pieces, and where each one lives

`prot == 2` identifies monkelf uniquely among shipped sets (`edfbl`, the other
`none`, is excluded), so it keys every fixup and no new `.mra` field is needed.

**1. Direct input ports** (`ms1_main.sv`). The bootleg has no protection
device and reads the five ports at their own addresses, just above the one the
protected boards use:

```
0E0002 P1   0E0004 P2   0E0006 DSW1   0E0008 DSW2   0E000A SYSTEM
```

A sixth decode case, returning `{8'hFF, port}` -- the high byte reads as ones,
as MAME's undeclared port bits do. DTACK needs nothing special: the core
acknowledges any cycle that is not stalled on ROM or an array.

**2. The ROM patch** (`.mra`). MAME's `init_monkelf` does
`m_rom_maincpu[0x00744/2] = 0x4e71`, and the word really there is

```
0744:  4E 72 27 00      STOP #$2700
```

a halt with every interrupt masked -- the "port-based trap" MAME's comment
guesses at. `4E71` is NOP. This is a program-ROM change, so it belongs in the
`.mra`, not the core: `<patch offset="0x744">4E 71</patch>`, which is the
form 39 files of the stock MiSTer arcade collection already use.

**3. The priority PROM** (`ms1bcd_core.sv`). The bootleg's table is
nibble-packed, and MAME expands it at init:

```c
for (int i = 0x1fe; i >= 0; i -= 2)
    ROM[i + 0] = ROM[i + 1] = (ROM[i / 2] >> 4) & 0x0f;
```

so entry A comes from the HIGH nibble of raw byte A>>1, each raw byte serving
two consecutive entries. Done as an **address and data remap** on the core's
PROM port rather than by rewriting the table, which keeps PROM data out of
both the `.mra` and the bitstream (PLAN 2.3).

**4. The scroll fixups** (`ms1_main.sv`). Both X scrolls are adjusted on the
way in, per `monkelf_scroll0_w` / `monkelf_scroll1_w`:

```
layer 0:  data -= ((data & 0x0f) > 0x0d) ? 0x10 : 0
layer 1:  data -= ((data & 0x0f) > 0x0b) ? 0x10 : 0
```

MAME's comment is "code in routine $280 does this. protection?" -- the
bootleg's own compensation for whatever the removed device used to do.

### Verified

Reference sim, 80 frames: `act=000F`, `vramw` 33,607, layer 0 scrolling
frame to frame, and `irq2 = 0` -- correct, since there is no protection device
to raise it. avspirit's 70-frame comparison is byte-identical before and after.

On hardware, all three protection paths and both MCU sets in one sweep:

| set | protection | screenshot sizes |
|---|---|---|
| monkelf | none | 4599 1582 16350 |
| hayaosi1 | iosim | 21917 18971 19079 |
| chimeraba | iosim | 18235 21449 23488 |
| avspirit | mcu | 4599 2116 12349 |
| edf | mcu | 8183 12781 12107 |

monkelf draws the Avenging Spirit attract story sequence with its character
portraits and correct layer ordering, which is the visible check on the PROM
remap: a wrong priority table scrambles which layer wins, and it does not.

**Not verified:** the scroll fixups against MAME frame by frame. The picture
is positioned correctly by eye, but the thresholds (0x0d / 0x0b) have not been
exercised against a reference capture.


## MS1-56 — System D has no memory map: `mode == 2` falls into System B's (closed)

`ms1_main.sv` decoded System B with `~is_c`, so mode D -- and, until MS1-53,
the idle mode 3 as well -- selected System B's map. `peekaboo` and
`peekaboou` fetched their reset vector from a region that is only 0x40000
long on that board's layout and went nowhere.

System D is not a variant of B or C. It is a different board:

- **One 68000 and no sound CPU.** No YM2151 either. The main CPU writes the
  single OKIM6295 itself, at `0F8001`, low byte only.
- **Two scroll layers, not three.** `system_D` instantiates `m_tmap[0]` and
  `m_tmap[1]` only, so layer 2 is *absent* rather than disabled: whatever
  `active_layers` says about it, nothing is drawn. `ms1_video.sv` already had
  `nlayers` for this; the core was passing a hard-coded 3.
- **A different palette format.** `RGBx_555`, where B and C are
  `RRRRGGGGBBBBRGBx`. `ms1_video.sv` already split on `mode == 2'd2`.
- **No `global_mask`.** B masks to 20 bits and C to 21; D's map declares
  neither, so all 24 address bits are decoded.
- **Its own protection**, at `0x100000`, installed by `init_peekaboo` rather
  than declared in the map.
- **One interrupt from the raster, not two.** `system_D` uses
  `set_vblank_int(megasys1D_irq)`, which is one **level 2** per frame at the
  start of vblank. There is no scanline callback, so B and C's level 1 at
  line 96 and level 4 at line 240 do not exist. The protection port raises
  level 4, and that is the whole interrupt map.

### The two things that are easy to get wrong

**The two scroll windows are inverted with respect to their addresses.** The
LOWER one, `0D0000`, is MAME's `m_tmap[1]` (share `"scroll2"`); the HIGHER
one, `0E8000`, is `m_tmap[0]` (share `"scroll1"`). Wiring them in address
order silently swaps the two layers -- which looks like a priority bug, not
an address bug. `sim/oracle/traces/peekaboo/layout.txt`, captured from MAME
long before any of this was written, records it: `layer0 base=0E8000`,
`layer1 base=0D0000`.

**The palette mirror is 0x3000, and that does not include bit 11.**
`map(0x0d8000, 0x0d87ff).mirror(0x3000)` means `0D9000`, `0DA000` and
`0DB000` are the same 2 KB -- and that `0D8800`-`0D8FFF` is *unmapped*, not a
mirror. Decoding the window as a flat `0D8000`-`0DBFFF` range aliases the
upper half of each 4 KB block onto the palette.

### The sample bank

`protection_peekaboo_w` latches the word, and if `(val & 0x90) == 0x90` the
low three bits also pick an OKI sample bank. `megasys1D_oki_map` gives the
chip a 256 KB window: `00000`-`1FFFF` is the head of the ROM and
`20000`-`3FFFF` is the bank. `init_peekaboo` configures **entry 7 first**, to
`ROM+0x20000`, and only then entries 0..6 to `ROM+0x20000 + n*0x20000` -- so
bank 7 is bank 0's block again, NOT `ROM+0x100000`, which is one byte past
the end of a 1 MB sample ROM. Taking bank 7 literally is a silent
off-the-end fetch that shows up only as noise. `ms1_sound.sv` folds it in.

That 1 MB is also why `oki1_rom_addr` widened from 18 bits to 20, through
`ms1bcd_core.sv` and `ms1bcd_rom_hw.sv`; every other set uses at most the low
18 and the top two read zero.

### Where the OKI lives

In `ms1_sound.sv`, with the other one, even though System D has no sound
subsystem to speak of -- so that there is exactly one OKI instance, on one
`cen`, behind one ROM cache. In mode D the sound 68000 and the YM are held in
reset (`cpu_rst`), and `main_oki_we`/`main_oki_wdata` from the main CPU drive
OKI 1 in place of the sound CPU's `0A0000` port. The OKIs stay on `snd_rst`
rather than `cpu_rst`: `screen_flag` bit 4 resets OKI 1 on System D too
(`screen_flag_w` tests `m_oki[0].found()`, not the presence of a sound CPU).
MAME routes System D's single OKI at 1.0, not at B/C's 0.30, so the mixer
gives mode D its own gain -- at B/C's the game is audible and about 10 dB
down.

### Measured

`peekaboo`, 50 frames, against `sim/oracle/traces/peekaboo/frames`, on BOTH
paths -- the reference sim (`sim/rtl/ms1_frames`) and the SDRAM path
(`sim/rtl/ms1_hw`) -- with the same region images, from one generator run:

| frames | reference sim | SDRAM path |
|---|---|---|
| 32-34, 36-38, 40-42, 44-46, 48-49 | **0 differing pixels** | **0 differing pixels** |
| 35, 39, 43, 47 | 530, 222, 411, 662 | 530, 222, 411, 662 |

The two paths agree to the pixel, including on the four frames that do not
match MAME. Those four are one blinking element on a different phase: they
recur every four frames and nothing else in the frame moves.

Frames 25-30 are black in both. Frames 1-24 are MAME's uninitialised-RAM boot
pattern (57344 lit); a simulation that starts from zeroed memory cannot
reproduce them.

Also from the SDRAM run: `ym=0 oki1=15 oki2=0` -- the main CPU is driving the
OKI and nothing is driving the YM, which is the shape System D should have --
and 0 tile-fetch misses on every layer over 2876913 displayed pixels.

Getting the SDRAM path there took MS1-57, which System D found and which was
never System D's.

## MS1-57 — the tile-fetch lookahead wrapped on the visible width, not the line (closed)

**Every visible line on the SDRAM path began with eight pixels lifted from
the middle of itself.** This is not a System D bug; System D is only where it
finally showed.

`ms1_video.sv` runs the tile fetch `LOOKAHEAD` pixels ahead of the displayed
pixel and holds each layer's result the same number of pixel ticks in the
delay line inside `ms1_tilemap.sv`, so the net latency cancels. The fetch runs
on every pixel tick, **blanking included** -- 384 ticks a line, not 256. So
the pixel displayed at column x is the one fetched `LOOKAHEAD` ticks earlier,
and for `x < LOOKAHEAD` that tick fell in the PREVIOUS line's blanking.

The wrap was written against `VIS_W`:

```
wire       vx_wrap = vx_sum >= VIS_W[9:0];          // 256
wire [8:0] vxa = vx_wrap ? (vx_sum - VIS_W[9:0]) : vx_sum[8:0];
```

At `hcount` 376, `vx_sum` is 384 and `vxa` is 384 - 256 = **128**. The eight
fetches that feed columns 0..7 addressed columns 128..135 instead. Wrapping on
the whole line gives 384 - 384 = 0, which is what those ticks are for.

```
wire       vx_wrap = vx_sum >= TOTAL_W[9:0];        // 384
wire [8:0] vxa = vx_wrap ? (vx_sum - TOTAL_W[9:0]) : vx_sum[8:0];
```

### How it hid

The reference sim runs `LOOKAHEAD = 0`, where the delay line is bypassed
entirely (`ms1_tilemap.sv`'s `g_nolead`) and the wrap cannot reach the
display. `sim/rtl/ms1_frames` is the harness every "pixel-exact against MAME"
claim in this project has been made with, and it is the one path where this
code does not run. `sim/rtl/ms1_hw` is the path that renders it, and **its
pixels had never been compared against MAME for any set** -- it was built for
the golden-byte audit and the miss counters, and what frame checking it did
was against the reference sim rather than against the oracle.

It also only shows where columns 0..7 and 128..135 disagree, which on a tiled
background is nowhere.

### It had already been found, and misdiagnosed

**MS1-32 is this bug.** It was opened when the lookahead went in, with the
right measurement -- "every differing pixel was in the first N columns; at
N=16 the diffs spanned x = 0..15, at N=8 exactly x = 0..7" -- and the wrong
cause. It concluded that `ms1_tilemap` sampling `scroll_x`/`scroll_y`/`ctrl`
combinationally at stage 0 made the two paths read those registers on
opposite sides of a mid-line write, and from there that **"the lookahead is
not a tuning knob with a safe value. Any N > 0 has the same defect, N columns
wide"** -- so the fix was a second prefetch-only address generator, and the
issue was left open as a design problem rather than a bug.

The re-measurement that settles it, on the same set and the same harness that
produced the original number:

```
avspirit, SDRAM path vs reference sim, N=8, frame 60
  98 differing pixels, x 0..7, y 85..127
  hw[y][x] == ref[y][x+128] on 98 of 98
```

Every one of them. Not a correlation -- the whole set. The rows 85..127 that
MS1-32 read as "the scanline bands where avspirit writes scroll registers
during horizontal blanking" are simply the rows where that frame's columns
0..7 and 128..135 differ; on the rest of the frame the bug is present and
invisible, exactly as it is on every other set.

The lookahead is a tuning knob with a safe value after all, and the second
address generator MS1-32 called for is not needed.

### How it was found

Not by looking for it. `peekaboo` came up 54 pixels short of MAME on the SDRAM
path and **pixel-exact on the reference sim** -- the same ROM images, from the
same generator, in both. That gap is the whole diagnosis: a difference that
exists in one path and not the other is in the path, not in the game. Reading
off the coordinates -- rows 153-159 and 184-190, columns 0-6, seven wide --
and then testing the one hypothesis those coordinates suggest settled it in a
single comparison:

```
153 hw  x0-7       F77B00 F77B00 F77B00 F77B00 F77B00 F77B00 F77B00 000884
153 ref x128-135   F77B00 F77B00 F77B00 F77B00 F77B00 F77B00 F77B00 FF94AD
```

Seven columns in `peekaboo`, because its column 7 happened to agree; `avspirit`
shows all eight.

Then the first fix appeared not to work: the run produced **exactly the same
54 pixels**, and for a few minutes the obvious reading was that the diagnosis
was wrong. It was not. `make` had not rebuilt -- `rtl/jaleco/ms1_video.sv` was
not a prerequisite of any sim Makefile, because verilator finds it through
`-y`. That is MS1-58, and it is worth stating plainly: **the failed
verification of a correct fix looks exactly like a wrong diagnosis.** Checking
the binary's timestamp against the source's took ten seconds and should have
been the first thing done, not the fourth.

### Verified

| measurement | before | after |
|---|---|---|
| `peekaboo`, SDRAM path vs MAME, steady frames | 54 px each | **0** |
| `peekaboo`, the four blink frames | 584 276 465 716 | 530 222 411 662 -- the reference sim's own numbers |
| `avspirit`, SDRAM path vs reference sim, 70 frames | 58/70 identical, 98 px each on the other 12 | **70/70 identical** |
| `avspirit`, tile-fetch misses over 4014080 displayed pixels | L0 0, L1 0, L2 0 | L0 0, L1 0, L2 **103** (0.00257 %) |

Both paths now agree to the pixel on both sets.

**The fix costs a little cache warming.** The old wrap spent the blanking
period re-fetching the next row's columns 8..135, which was wrong for the
eight pixels that reached the screen and useful for the rest of the line; the
new one fetches columns 256..383 of the current row, which is discarded.
`avspirit` picks up 103 layer-2 misses a run where it had none. They change no
pixel -- the frames are 70/70 identical -- and 0.0026 % is far inside what
docs/PLAN.md 4.B.3 asks of the miss measure, so this is recorded rather than
chased. A blanking sweep that warms 8..135 AND lands the last eight ticks on
0..7 is possible (`vxa = vx_sum - (VIS_W - LOOKAHEAD)` in the middle region);
it is a second special case in the expression that just produced this bug, and
it buys 103 pixels of cache warming.

The lesson is docs/PLAN.md 4.I's, in its sharpest form so far: a gate that
runs only the configuration you do not ship measures the configuration you do
not ship. `LOOKAHEAD` was introduced precisely because the SDRAM path needs
it, and then nothing compared the SDRAM path's pixels against MAME until a
game happened to have content in the eight columns it corrupts.

## MS1-58 — the sim Makefiles do not depend on the RTL verilator finds (closed)

Every `sim/rtl/*/Makefile` named two or three `.sv` files as prerequisites and
let verilator find the rest through `-y`. `make` cannot see a `-y` search
path, so editing `rtl/jaleco/ms1_video.sv` -- or `ms1_tilemap.sv`, or
`ms1_sprites.sv`, or `ms1_prio.sv`, none of which was ever a prerequisite --
relinked nothing and left the previous binary in place.

That is how MS1-57 nearly got closed twice: the fix went in, `make` printed
nothing, the run produced **exactly the same 54 pixels**, and for a few
minutes the obvious conclusion was that the diagnosis was wrong. The binary's
timestamp was twenty minutes older than the source.

This is MS1-48 one layer down, and the same rule applies: **a build that can
silently reuse a stale artifact will eventually be measured as if it were
fresh.** MS1-48 fixed it for Quartus by grepping the log instead of trusting
the exit code. Here the prerequisite list is replaced with a wildcard over
every directory on the `-y` path:

```make
RTLSRC := $(wildcard $(RTL)/*.sv $(RTL)/*.v $(RTL)/ms1bcd/*.sv $(RTL)/ms1bcd/*.vh \
                     $(RTL)/jaleco/*.sv $(RTL)/tlcs90/*.sv $(RTL)/savestate/*.sv)
```

Over-broad on purpose: a needless rebuild costs 40 seconds and a skipped one
costs a wrong measurement.

## MS1-59 — every game shows a five-pixel strip down the left of the screen (closed)

Reported from the board, on every game. The picture is **shifted five columns
to the right**; the five columns it vacates at the left are filled with the
tail of the PREVIOUS line, and the five true columns pushed off the right are
lost.

### The measurement

`peekaboo`'s RANKING screen is static for a long stretch of the attract, so
the same scene can be captured on both sides. MAME was re-captured deep into
the attract (`MS1_SKIP=2600 MS1_FRAMES=600`) to reach it, and the board's
screenshot compared against every captured frame at each shift 0..8:

```
                                   best shift   diff
peekaboo  RANKING (board)              5 px       0      next best 6 px: 7333
peekaboou RANKING (board)              5 px       0      next best 6 px: 7333
```

**Zero differing pixels at a shift of five**, against 23192 unshifted. Not a
correlation; the whole frame.

### The cause

`ms1_video.sv` carries a pixel's validity through `vpipe` -- four stages,
tilemap pen, priority, palette+rgb -- and then registers `rgb_valid` once
more. `visible` is combinational from `hcount`, so:

> `core_rgb` at `hcount_core == H` is the pixel of column **H-5**.

`video_retime.sv` writes `buf_mem[{vcount_w[0], w_x[8:0]}] <= rgb_w` with
`w_x = hcount_w - w_x0`. The top level handed it the LIVE `hcount_core`, so
every pixel was stored five slots to the right of where it belongs, and slots
0..4 took whatever the pipeline was still emitting when `hcount` wrapped --
the previous line's columns 251..255.

### Why nothing caught it

**No simulation in this project uses `hcount` to place a pixel.** Both frame
harnesses do the same thing:

```c
if (top->ce_pix_o && top->rgb_valid && px < cur.size()) cur[px++] = top->rgb;
```

They append valid pixels in order, which is exactly the operation that a
constant hcount-to-rgb offset cannot disturb. Every "pixel-exact against
MAME" result in this project is therefore true and was blind to this by
construction. `video_retime` is the only consumer that uses the raster
position, it lives in the top level, and no simulation instantiates the top
level.

It is the same shape as MS1-57 one layer out: a defect that only exists in
the configuration that ships, measured only in the configuration that does
not.

### The fix

Delay the POSITION to meet the pixel, rather than the other way round, in
`MS1BCD.sv`:

```systemverilog
localparam integer RGB_LAT = 5;
reg [8:0] hc_lat [0:RGB_LAT-1];
reg [8:0] vc_lat [0:RGB_LAT-1];
always @(posedge clk_sys) if (ce_pix_core) begin
	hc_lat[0] <= hcount_core; vc_lat[0] <= vcount_core;
	for (rl = 1; rl < RGB_LAT; rl = rl + 1) begin
		hc_lat[rl] <= hc_lat[rl-1]; vc_lat[rl] <= vc_lat[rl-1];
	end
end
```

Delaying `vcount` as well is what makes the line wrap come out right: while
the pipeline is still emitting line L's last five pixels, `hcount` has already
wrapped into line L+1, and the delayed `vcount` still reads L, so those pixels
land in line L's buffer. The reader is ~246 pixels behind that write, so there
is no race.

`vblank_core` deliberately keeps the live `vcount`: it drives the autofire
frame tick and the savestate engine's vblank wait, neither of which is part of
the picture, and both of which were measured on the live one.

### Verified on the board

The same measurement, on the rebuilt bitstream:

| | best shift | differing pixels |
|---|---|---|
| before | 5 px | 0 (unshifted 23192) |
| **after** | **0 px** | **0** |

The board's framebuffer is bit-identical to MAME's frame of the same scene.
Checked on all three boards: `peekaboo` (D), `avspirit` (B) and `cybattlr`
(C). Cybattler is the clearest read -- its own border line sat at column 5
with four columns of stale black to its left, and now sits at column 0 with
the grid running cleanly behind it:

```
cybattlr, column means 0..9
  before   63  61  59  57  55 | 129  87  87  87  87
  after   129  87  87  87  87 |  87  87  87  87  87
```

### The sibling cores use the same module the same way

`Arcade-SandScrp_MiSTer` and `Arcade-NMK16_MiSTer` both pass a live
`hcount_core`/`vcount_core` into `video_retime`. Whether they are affected
depends on each core's own pixel-pipeline depth, which is different code and
has not been measured. The method that settled it here is cheap and transfers
directly: capture the same static attract screen on the board and in MAME,
then scan shifts 0..8 for the one that gives zero differing pixels.

## MS1-60 — the sprite pass overruns blanking, and the beam reads the plane while it is still being drawn (fixed)

Reported from the board: **enemy sprites disappear on the right of the screen
in Cybattler, but never on the left.** Cybattler is the only ROT90 set and is
played in Orientation "Vert 90", the clockwise case, so the display's right
edge is the NATIVE RASTER'S TOP -- native `y = 0` maps to display `x = W-1`,
native `y = 223` to display `x = 0`. A defect confined to the top of the
native raster can only appear on one side of a rotated screen, which is
exactly the shape of the report.

### The race

`rtl/jaleco/ms1_sprites.sv` keeps **one** sprite plane. `plane_e` and
`plane_d` are two identical copies written by the same `pl_we` on the same
clock -- they exist to give the engine and the display a read port each, not
to hold two frames. The pass clears all 65536 entries and redraws them,
starting at `vblank_rise`, while the video reads that same plane as the beam
scans it.

The display reads plane row `by = my + VIS_Y0`, and with `my = vcount - 16`
that is simply `by = vcount`: **plane row R is read at `vcount == R`**, for R
in 16..239. So the pass has from `vblank_rise` (row 240) to `vcount == 16` to
have finished row 16 -- 54 rows.

```
frame                                   854016 clk   (384 x 278 x 8)
one row                                   3072 clk
vblank_rise -> first displayed plane row  165888 clk  (54 rows)

measured longest pass, sim/rtl/ms1_hw:
  avspirit    211992 clk    overrun 46104 clk = 15.0 rows
  peekaboo    213703 clk    overrun 47815 clk = 15.6 rows
  cybattlr    212970 clk    overrun 47082 clk = 15.3 rows
```

**The overrun is structural, not scene-dependent.** The engine blits all
16x16 pixels of every object entry and only uses `on_screen` to gate the
WRITE, so the cost is fixed whatever is on screen:

```
clear                    65536
256 objects x 512      131072
                       ------
                       196608  + per-sprite overhead ~= 213k
```

That is why the three games agree to within 1.7k clocks, and why `cybattlr`
measured the same on a coined-up run as `avspirit` does in its attract. Every
frame of every game is exposed; what varies is only whether a sprite that
lands in the top ~15 rows happens to be drawn late in the pass order. The
pass does finish inside the frame, so `dbg_late_swaps` stays 0 and nothing
flags it.

### MAME cannot do this

`draw_sprites()` is called from inside `screen_update()`, which renders the
whole sprite bitmap before the frame is presented. There is no beam, so there
is nothing to race. Like MS1-57 and MS1-59 this is a hardware-path artifact
that a frame comparison only catches if it happens to fire on a captured
frame.

### What was and was not reproduced

Honest state: **the mechanism is proven, the symptom is not.** 1800 MAME
frames were captured (`MS1_SKIP` 0 and 1200) and 24 board screenshots matched
against them. Seven aligned cleanly and every one was **pixel-identical to
MAME, top band included**:

```
board t4 -> MAME f1401   0 differing pixels      t5 -> f1523   0
      t6 -> MAME f1577   0                       t7 -> f1571   0
      t8 -> MAME f1565   0                       t10-> f2091   0
      t9 -> MAME f1976  35   (none in the top 16 rows)
```

Those are attract screens. In them no late-ordered sprite lands in the top
band, so the race is armed but silent. Driving real gameplay on the board and
aligning it against MAME is not possible -- play is not reproducible frame for
frame -- so the pixel-level demonstration is still missing, and this entry
stays OPEN until there is one.

### The fix, costed

**Double-buffering the plane is not affordable.** Each copy is 576 Kbit and
the fit is at 544 of 553 M10K.

The lever is the clear: 65536 clk, 21.3 rows, a third of the pass and more
than the whole overrun. Remove it from the pass and the pass is ~147434 clk,
inside the 165888 budget with 6 rows to spare, at no memory cost:

- **Clear behind the beam.** Plane row R is read at `vcount == R`, so it is
  free from `vcount == R+1`. Clearing one row is 256 entries out of the 3072
  clocks in a row, so it fits easily alongside the display read.
- **Tighten `on_screen` from `py in [0,256)` to `py in [16,240)`**, which is
  MAME's cliprect exactly (`min_y` 16, `max_y` 239). Rows 0..15 and 240..255
  are then never written, so they never need clearing and the behind-beam
  sweep covers the whole plane.
- Drop `S_CLEAR`, and with it the `clr` counter from the savestate.

A second, data-dependent saving is available and is what MAME would do: skip
the blit entirely for an object that is wholly off-screen. MAME has exactly
that test written at `megasys1_v.cpp:381` and commented out. It does not
guarantee the budget on its own, so it is a supplement, not the fix.

### Applied

The clear is no longer part of the pass. It is swept a row at a time behind
the display read, 256 clocks out of the 3072 in a raster line:

```
cybattlr sprite pass   212970 -> 151372 clk
budget                          165888 clk (54 rows)
  before   overrun +47082 clk = +15.3 rows
  after    margin  +14516 clk =  +4.7 rows
```

Three things had to travel with it:

- **The row comes from `fb_rd_addr[15:8]`, not from the raster counter.** That
  makes the sweep follow the screen flip for free -- flipped, the display
  walks the rows downwards and so does the sweep -- and it is what makes the
  ordering safe by construction rather than by arithmetic: a row is wiped only
  once the display has finished reading it.
- **`S_CLEAR` became `S_WAIT`.** Removing the clear exposed a dependency it
  had been hiding. `ms1_main` copies the object and sprite double buffers over
  4096 clocks from `vblank_rise`, and the pass starts on the same edge; the
  old clear's 65536 clocks always outlasted the copy, so nothing ever waited
  for it. Without the clear the engine would read straight through the shift
  and take half of one frame's objects and half of the next's. `buf_busy` is
  now plumbed out of `ms1_main` through the core and `ms1_video`, and the pass
  waits on it.
- **`on_screen` tightened to `py in [16,240)`**, which is MAME's cliprect
  exactly. This is required rather than cosmetic: the sweep only covers the
  rows the display reads, so a sprite written outside that band would never be
  wiped again.

`sprite_flag` bit 4 ("do not clear", the P47 trails effect) suppresses the
sweep exactly as it used to suppress `S_CLEAR`. The savestate keeps its
layout: fields 4 and 5 held the clear counter and now hold the sweep's row/x
and run flag, restored inside the block that owns them (MS1-34). The engine
stalls in `S_BB` if the sweep holds the write port so a blit can never be
dropped silently, though the two do not overlap in practice -- the pass runs
through blanking, the sweep only during displayed lines.

**Regression, on both paths and both a B and a D set:**

| | before | after |
|---|---|---|
| `peekaboo`, reference sim vs MAME | 15/20 exact | 15/20 exact, **same frames, same counts** (31 the fade-in, then 530/222/411/662) |
| `avspirit`, SDRAM path vs reference sim | 70/70 identical | **70/70 identical** |
| `avspirit` sprite pass | 211992 clk | **150534 clk** |
| `cybattlr` sprite pass | 212970 clk | **151372 clk** |

Not one pixel moved anywhere, and the ~61k saving is the same on both games,
as it should be for a cost that was always fixed.

**On the board**, the cybattlr attract was recaptured on the fixed bitstream
and matched against the same 1800 MAME frames: the same six frames are
pixel-identical (f1401, f1523, f1565, f1571, f1577, f2091), the same 35-pixel
near-miss at f1976, and the same residuals on the frames that run past the
capture window. Byte for byte the pre-fix result, so nothing regressed where
the core was already right.

The symptom itself still has no pixel-level demonstration, for the reason
given above: gameplay cannot be aligned against MAME frame for frame. What is
established is that the budget is now met with 4.7 rows in hand where it was
missed by 15.3, on both paths and on a System B, C and D set.

## MS1-61 — restoring a state silences the YM2151 for good (fixed)

Reported from the board: **on 64th Street, restoring a state drops all sound
output from then on.** Not "the music restarts wrong" and not "one voice is
missing" -- every FM voice, permanently, until the core is reloaded.

### Two defects, one in the clock and one in the state machine

`rtl/ms1bcd/ms1_sound.sv` does not save the YM2151's internal state. It keeps
a 256-byte **shadow** of every register the sound CPU has written, and on a
load it replays all 256 back into jt51 as select/data pairs, one write per
`ym_cen_p1`. That is the usual savestate compromise: registers restore,
envelope phase does not.

`ym_cen_p1` is `enPhi1 & (ymdiv == 2'd3)`, and `ymdiv` was held by `ss_hold`:

```systemverilog
else if (ss_hold) ymdiv <= ymdiv;      // the defect
else if (enPhi1)  ymdiv <= ymdiv + 2'd1;
```

`ss_hold` is `ss_freeze | ss_active | ss_resume` (`ms1bcd_core.sv:142`), and
`rtl/savestate/savestate.sv` raises `ss_freeze` in `S_FREEZE` (:128) and does
not drop it until `S_RELWAIT` (:246) -- so it is high for the whole of
`S_REPLAY`. **`ymdiv` is therefore frozen at whatever value the image
restored, for the entire replay.** Three of its four values make `ym_cen_p1`
dead, and the replay cannot advance a single register:

| restored `ymdiv` | `ym_cen_p1` during replay | replay |
|---|---|---|
| 0, 1, 2 | never fires | stalls forever |
| 3 | fires on **every** `enPhi1` | finishes, at 4x the intended rate |

The engine waits on `ss_replay_done`, times out, and then reports the load
**OK** (`ok_r <= 1'b1`, savestate.sv:223) -- so nothing on screen says the
sound state never arrived.

That alone would lose the registers. What silences the chip is the second
defect, in the replay FSM: `rp_run` had no clear except "all 256 done".

```systemverilog
if (!ss_replay) begin rp_done <= 1'b0; ss_replay_done <= 1'b0; end   // rp_run not cleared
```

`rp_run` drives jt51's `wr_n` and takes over its `a0` and `din` from the sound
CPU:

```systemverilog
.wr_n(~(ym_wr | rp_run)), .a0(rp_run ? rp_phase : chip_a0),
.din(rp_run ? (rp_phase ? ymsh_q : rp_idx) : chip_din),
```

So a replay that cannot advance latches `rp_run` high **for the rest of the
session**. Every YM write the game makes afterwards is replaced by the stuck
replay's data. That is the reported symptom exactly: not degraded sound, no
sound, from the restore onward.

### The user's own save

`64STREETTEST_1.ss` (393,224 bytes) carries, at the sound scalar word
`0x1D025`:

```
sound scalar5 0x1D025 = 0001 -> okidiv 1  ymdiv 0  chip_a0 0
```

`ymdiv 0` -- one of the three dead phases.

### Why the simulator kept saying it was fine

`sim/rtl/ms1_frames` parked by raising `ss_freeze` at an arbitrary tick, while
the real engine's `S_ARM` waits for a `vblank & ~vb_d` edge first. The two
land the held divider on different phases, and the harness happened to land on
3 -- the one value that works. Three runs in a row reported `ymdiv 3` and
"replay done after 3507 ticks", and on that evidence a correct diagnosis was
retracted. **A phase-dependent bug is invisible to a harness that always
parks on the same phase**, and 3507 ticks was itself the tell: 512 chip writes
at one per `ym_cen_p1` cannot take fewer than about 14000.

The harness now parks on the vblank edge, and takes `MS1_SS_YMDIV=N` to force
the restored phase, which turns a race into a table:

```
                         before            after
  forced ymdiv=0    TIMED OUT (5000001)   done after 14040 ticks
  forced ymdiv=1    TIMED OUT (5000001)   done after 14033 ticks
  forced ymdiv=2    TIMED OUT (5000001)   done after 14026 ticks
  forced ymdiv=3    done after 3507       done after 14019 ticks
```

The last row matters as much as the first three: 3507 ticks was the replay
writing jt51 on every `enPhi1` instead of every fourth, four times faster than
the chip is clocked to accept. Even the phase that "worked" was not replaying
the registers correctly.

### The fix

Two lines, both in `rtl/ms1bcd/ms1_sound.sv`. Let the divider run through the
replay -- `enPhi1` is gated by `ss_active` alone, which savestate.sv has
already dropped by then (:214), so the CPU stays parked either way:

```systemverilog
else if (ss_hold & ~ss_replay) ymdiv <= ymdiv;
```

and make the replay let go of the chip when `ss_replay` drops, finished or
not, so a stall can never outlive the load:

```systemverilog
if (!ss_replay) begin
    rp_run <= 1'b0; rp_idx <= 8'd0; rp_phase <= 1'b0;
    rp_done <= 1'b0; ss_replay_done <= 1'b0;
end
```

`okidiv` is deliberately left frozen: the OKI replay does not depend on it,
and holding it only delays the sample clock by the width of the load.

### Still open

The shadow in that save had **1 of 256 registers non-zero** (`ymsh[0] = 0xFC`).
That is not explained by either defect above -- both are on the restore side,
and the shadow is captured on the write side -- so either the save was taken
before 64th Street's sound CPU had programmed the chip, or the capture path
has its own defect. `chip_a0` and `chip_din` are registered on `acc_edge`,
while `ym_wr_pulse` that consumes them is combinational on the same edge, so
the shadow decides select-vs-data from the *previous* bus write. For strict
select/data pairs that still lands the right byte in the right register, one
write late, but it has not been measured. Tracked separately.


## Hardware coverage after MS1-47 / 49 / 50 / 51 / 53 / 54 / 55 / 56

Every shipped set whose board this core implements now boots on the
DE10-Nano at 192.168.1.138 and draws its attract mode. Three screenshots per
set, 10 s apart, 70 s after load, through the `.mra` files the repository
ships with only `zip=` repointed at a test set repacked from `mame_roms/`
(the board's own collection is a merged set with MAME's older member names,
and no MCU in `avspirit.zip` at all).

**System B, 7 of 7**

| set | protection | screenshots |
|---|---|---|
| avspirit | mcu | 4599 2116 12349 |
| edf | mcu | 8183 12781 12107 |
| edfa | mcu | 8154 12592 12087 |
| edfb | mcu | 4281 13171 10821 |
| edfu | mcu | 7953 12781 12087 |
| monkelf | none | 4599 1582 16350 |
| hayaosi1 | iosim | 21917 18971 19079 |

**System C, 7 of 7**

| set | protection | screenshots |
|---|---|---|
| 64street | mcu | 15640 17537 16700 |
| 64streetj | mcu | 34089 33253 37409 |
| 64streetja | mcu | 34089 33253 38988 |
| bigstrik | mcu | 847 13035 1968 |
| chimerab | mcu | 20259 19792 24503 |
| chimeraba | iosim | 18235 21449 23488 |
| cybattlr | mcu | 10286 9972 41853 |

Spot-checked by eye: 64th Street's attract story with its portraits and
dialogue, Cybattler's mecha over cratered terrain (text rendered sideways,
which is right -- the core outputs the board's native ROT90 raster and the
rotation happens in the framebuffer downstream), and bigstrik on the Jaleco
copyright screen, which is why two of its three samples are nearly black.

**System D, 2 of 2**

| set | protection | screenshots |
|---|---|---|
| peekaboo | peekaboo | 56308 57344 |
| peekaboou | peekaboo | 56308 57344 |

Both boot and animate. The attract cycles: the block-breaker playfield with
"INSERT COIN", the paddle, the score panel (HIGH SCORE / 1UP / 2UP / ADV.
BONUS), then the RANKING screen with six entries over its star background.
The two sets are the same game and draw the same attract, which is why their
counts match.

`peekaboo` is also **pixel-exact against MAME on both simulation paths** --
the reference sim and the SDRAM path agree with each other and with the
oracle on every steady frame (MS1-56). MS1-40 (the 2 MHz sample clock),
MS1-42 (the 16-bit SYSTEM port and the paddles), MS1-57 (the lookahead wrap)
and MS1-58 (the sim Makefiles' dependencies) all closed with it.

**All 16 shipped sets now boot on the board.**

### Regression check on the MS1-57 build

MS1-57 changes what every layer fetches in the first eight columns of every
line, on every board, so the B and C tables above were re-checked on the new
bitstream rather than assumed. Five sets across both modes and all three
protection models -- `avspirit` (mcu), `hayaosi1` (iosim), `monkelf` (none),
`64street` (mcu, System C), `cybattlr` (mcu, System C) -- load and animate,
and their attract screens are the ones they were showing before: avspirit's
city with the girder tower, monkelf's GAME OVER over the same scene,
hayaosi1's quiz panel with its Japanese question text, 64th Street's Allen
dialogue portrait, and Cybattler's rotated specification screen.

### What this does and does not establish

It establishes that each board's ROM layout, protection model, memory map,
raster and video pipeline are right enough to boot and animate. It says
nothing about frame accuracy (only `avspirit` has a reference comparison,
and `hayaosi1`'s does not match -- see MS1-54), nothing about sound on
hardware, and nothing about inputs, savestates or the rest of the M4 gates.

**And the frame accuracy it does claim was measured on the wrong path.**
MS1-57 was eight wrong pixels at the start of every line, live in every one
of the screenshots above and in the bitstream that produced them, and
invisible to every gate because the gates run `sim/rtl/ms1_frames`, which is
the one configuration that does not execute that code. The SDRAM path's
pixels are now compared against the oracle directly, not only against the
reference sim, and that should be a standing gate rather than something done
once for System D.
