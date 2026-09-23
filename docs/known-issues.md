# Known issues and open questions — Arcade-JalecoMS1BCD_MiSTer

Numbered `MS1-n`, in the style of the NMK16 and Sand Scorpion lists: each entry
records what was measured, how, and what is still unknown. An entry is only
closed by a measurement, never by reasoning.

**Five are open**: two from M0 answerable off-board, MS1-31 which needs the
board, and MS1-32 / MS1-33 from M3.

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
| MS1-32 | A tile-fetch lookahead trades fidelity for cache tolerance | **OPEN** — needs prediction-based prefetch, not a bigger lead |
| MS1-33 | A savestate round trip leaves one counter digit behind | **OPEN** — bounded at 25 pixels, cause not yet named |
| MS1-34 | A restore written in its own always block does nothing, silently | closed |
| MS1-35 | A probe that parks the CPU to look at it measures itself | closed |
| MS1-36 | Resetting the sound subsystem changes main-CPU behaviour | closed — the savestate park handshake, not a datapath |
| MS1-37 | Nine arrays do not infer as RAM; the core does not fit | closed — every array now block RAM; registers 996504 -> 11630 |
| MS1-38 | quartus_map catches the MS1-34 driver class that Verilator ignores | closed — run synthesis as a linter from M1, not at M4 |
| MS1-39 | Four OSD features have no core port, so the top level omits them | **OPEN** — M5 work: Pause, High Scores, Cheats, Flip Screen |
| MS1-40 | The .mra's 2 MHz sample-clock bit is decoded but reaches nothing | **OPEN** — needs an `oki_hz` port on ms1_sound.sv |
| MS1-41 | hayaosi1's three-player panel does not fit the pad or the .mra button list | **OPEN** — buttons 4/5 keyboard-only, player 3 unmapped |
| MS1-42 | peekaboo's SYSTEM port is 16 bits and the I/O mux is 8 | **OPEN** — moot until System D's memory map exists |
| MS1-43 | The protection MCU is a multicycle island timed as if it ran at 48 MHz | closed — SDC multicycle 4; -13.703 ns -> +3.901 ns |
| MS1-44 | The mode byte fans out further than any other signal and is timed as data | closed — reset tail + false path; -2.153 ns -> passing |
| MS1-45 | The sound harness stopped building, then stopped running, and said neither | closed — two stale inputs; ym=0 looked like healthy silence |
| MS1-46 | Two .mra names contain a colon, which no FAT filesystem accepts | closed — generator sanitises; tar had half-installed the tree |
| MS1-47 | MiSTer never sends an empty `<switches>` block, so the mode byte never arrives | **OPEN** — needs real `<dip>` entries; mode read 3 and every ROM base fell through to System D |
| MS1-48 | A failed Quartus compile leaves the previous .rbf and reports through a zero exit | closed — build.sh greps the log, not the exit code |
| MS1-49 | The .mra shipped the 68000 image byte-swapped, and --check validated it against itself | closed — MEASURED on hardware; my first diagnosis had it backwards |
| MS1-50 | Both 68000s handed the ROM cache their raw bus address | closed — held while the bus is not selecting ROM; SS-12 and NMK-21 are the same bug |
| MS1-51 | The main 68000 crashes at frame ~309 and the game traps on its watchdog | **OPEN** — narrowed to a 68000 crash in the reference sim; NOT hardware-specific |
| MS1-52 | The MCU's IRF register never cleared an interrupt request | closed — MAME clears the named source; ours was a documented no-op |

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


## MS1-32 — A tile-fetch lookahead trades fidelity for cache tolerance (open)

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

## MS1-39 — Four OSD features have no core port, so the top level omits them (OPEN)

`MS1BCD.sv` was adapted from `Arcade-SandScrp_MiSTer/SandScrp.sv`, which wires
Pause, High Scores, Cheats and Flip Screen into its core. `ms1bcd_core` has no
port for any of them:

| feature | what it needs |
|---|---|
| Pause | a clock-enable gate over both 68000s and the MCU |
| High Scores | a work-RAM back door (`hs_addr`/`hs_din`/`hs_dout`/`hs_write`/`hs_access`) |
| Cheats | the same back door, shared with hiscore |
| Flip Screen | an `osd_flip` input mirroring the video readback coordinates |

They are **absent from the CONF_STR**, not wired to constants. An OSD entry
that does nothing is worse than no entry: it reads as a core that is broken
rather than one that is unfinished.

This is M5 work, and it is not free — see the M10K figure in the bring-up
record. `rtl/third_party/hiscore/hiscore.v` and `rtl/cheats.sv` are both still
in the tree, unreferenced, ready for it.

## MS1-40 — The .mra's 2 MHz sample-clock bit is decoded but reaches nothing (OPEN)

The game-mode byte's bit 4 says the OKIM6295s run at 2 MHz rather than 4, and
`tools/gen_ms1bcd_mra.py` sets it for `hayaosi1`, `peekaboo` and `peekaboou`.
`MS1BCD.sv` decodes it into `oki_2mhz` and stops there: `ms1_sound.sv` divides
48 MHz by 12 unconditionally, which is the 4 MHz case.

The decode is kept rather than dropped because the .mra already carries the
bit and the byte is only comprehensible read whole. Quartus reports
`oki_2mhz` as assigned but never read, which is the intended reminder.

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

## MS1-42 — peekaboo's SYSTEM port is 16 bits and the I/O mux is 8 (OPEN)

`peekaboo` puts its four buttons in the HIGH byte of a 16-bit SYSTEM port
(MAME `0x0100`-`0x2000`), and `ms1_iomcu.sv`'s port mux is eight bits wide.
`MS1BCD.sv` maps the low byte -- the four coin inputs and the two starts --
and the buttons are unreachable.

Its `P1` is not a joystick either but an 8-bit PADDLE, `PORT_MINMAX(0x18,0xE0)`.
That one *is* wired, from `hps_io`'s `paddle_0`, clamped to the same range.

Both are moot until System D has a memory map: `mode == 2` currently falls
into the `~is_c` branch in `ms1_main.sv`, which is System B's map, so
`peekaboo` does not run at all yet (docs/PLAN.md 2.5).

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

## MS1-51 — The main 68000 crashes at frame ~309; the watchdog trap is a symptom (OPEN)

The board boots `avspirit` and then sits on the game's own `ERROR TRAPED /
WATCH DOG TIMER` screen. The next measurement this entry asked for -- IRQ
counts against the reference sim -- has been taken, and it moved the fault a
long way from where it looked.

### What the comparison showed

Per-frame IRQ2 (the MCU answering the 68000's protection handshake):

| | IRQ2 per frame |
|---|---:|
| reference sim | ~15 |
| hardware-path sim | ~14 |
| board | ~1 |

The board figure is an artefact of averaging a cumulative counter across a
stall: IRQ2 is **frozen**, not slow. Two captures 30 s apart both read
`irq2=3634` while `int1e` advanced 3121 -> 3391. The game runs normally for
about 260 frames and then stops.

### It is not the hardware ROM path

Both simulations reproduce it:

| | IRQ2 freezes at | MCU stops executing at |
|---|---|---|
| hardware-path sim | frame ~310, irq2=3635 | frame 364 |
| **reference sim** | **frame 310, irq2=3874** | frame 357 |
| board | (irq2=3634) | — |

The **reference** simulation -- plain arrays, no SDRAM, no caches -- fails the
same way. So every hardware-path suspicion was wrong: the ROM byte order, the
cache sizes, port-3 arbitration, refresh. A trace of port 3 taken after the
freeze shows it perfectly healthy, req/ack alternating, addresses advancing,
with `mcu_rom_ready` HIGH.

M2 gate 2 and M3 ran 70 frames. This is at 310. Nothing had ever looked.

### What actually happens, in order

| frame | `dbg_active` | VRAM writes | |
|---|---|---:|---|
| 308 | 000F | 35,447 | normal, ~10 writes/frame, layer 0 scrolling |
| 309 | 000F | 45,604 | a 10,000-write burst -- a scene transition |
| 310 | **4E7F** | 50,818 | garbage in the layer-enable register |
| 311 | **4E7F** | 55,994 | |
| 312 | 000F | 56,149 | and frozen from here on |

`0x4E7F` is a 68000 opcode pattern, not a layer-enable value: **the main CPU
wrote code into a video control register.** Scrolling stops at the same frame
(`t0x` sticks at 0x00F7) and VRAM writes stop entirely.

So the 68000 goes off the rails during a scene transition at frame 309. Every
later symptom follows from that: it stops servicing the protection handshake,
so IRQ2 stops; the MCU idles in its main loop (0x01B8-0x01CC) for 47 frames
and then takes its own error path -- `DI; HALT` at ROM 0x0227, which the
firmware image really does contain (`02 1C E4 05 1C CA 05 01`, twice) -- and
the 68000's software watchdog, a work-RAM word incremented by the level-4
interrupt, passes its limit and traps.

**The MCU halt is not a core bug.** It halts with `if=0` and INT1 pending, and
MAME's `check_interrupts()` returns early on `!(F & IF)` and only leaves HALT
via `take_interrupt()` -- so MAME would sit there too. The firmware asked to
stop.

### Where to look next

The 68000, at frame 309, in whatever routine runs the transition. The
instrument is already there: `tr_addr`/`tr_data`/`tr_we` in `ms1_main.sv` trace
every bus cycle, and `MS1_TRACE` in the frames harness prints them. Capturing
the last few thousand cycles before the first write of `0x4E7F` to the video
register, and comparing against the same window from MAME's bus trace
(`sim/oracle/ms1_bustrace.lua`), should name the divergence.

A wrong protection response is the obvious candidate -- these games use the
MCU's answers to build pointers, so one bad word becomes a bad jump -- but
that is a hypothesis, and this entry has already cost two of those.



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
