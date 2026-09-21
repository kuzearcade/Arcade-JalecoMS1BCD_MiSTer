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
