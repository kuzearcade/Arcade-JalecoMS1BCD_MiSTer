# M2 gate 2 — frames over the attract  (MET)

`docs/PLAN.md` M2 gate (2): "frames pixel-exact over the attract at a fixed
offset for one B game and one C game".

The subject is `rtl/ms1bcd/ms1bcd_core.sv` -- the 68000, the board decode, the
scanline interrupt timer, the protection MCU and the video, paced by a real
384x278 raster -- run from reset against MAME's own captured frames.

## Result

| set | mode | fixed offset | exact | longest contiguous exact run | non-blank in that run |
|---|---|---:|---:|---:|---:|
| avspirit | B | 0 | **150/151** | **145 frames** from frame 55 | 151..1812 |
| 64street | C | 0 | **147/200** | **122 frames** from frame 56 | 2047 |

Both runs are contiguous, not a scattered majority: 145 and 122 consecutive
frames in which every one of 57344 pixels matches MAME.

avspirit's count excludes 49 frames in which MAME renders its
**uninitialised-RAM boot pattern** (49952 non-blank pixels). A simulation that
starts from zeroed memory cannot reproduce those and counting them as failures
would be dishonest in the other direction; they are reported separately by
`tools/frame_compare.py` rather than quietly dropped. 64street has none.

The frames outside the exact run are all of one kind: the RTL frame is black
where MAME has content, because the sim has not yet reached the point in boot
where the game draws. `diff` equals MAME's own non-blank count exactly on
every one of them.

## What this took, and what nearly hid it

Three defects sat between a correct core and a correct frame. The first two
were in the RTL, the third in the harness, and the third was the expensive one.

**1. One interrupt-acknowledge CYCLE retired every pending interrupt**
(MS1-23). `iack` is a level held for the whole acknowledge bus cycle, and the
priority chain clearing on that level walked down and cleared IRQ 4, then 2,
then 1 on successive clocks. Only the highest-priority source was ever
serviced. The game sat in its `STOP` loop forever waiting for a work-RAM byte
that only the protection's IRQ 2 handler writes.

**2. Sprite RAM read from the wrong place.** It is work RAM + 0x8000 *bytes*,
i.e. word 0x4000; the buffer shift was reading word 0x1000.

**3. The harness sampled the video on `clk` instead of the pixel enable.**
`rgb_valid` is a register updated on `ce`, so it stays asserted for all eight
clocks of a pixel. Collecting per clock advanced the write pointer eight times
per pixel, filled each frame from the first eighth of the image -- and capped
at exactly 57344, so **the pixel-count sanity check passed** while every frame
was nonsense. `ce_pix_o` is now an output of the core with a comment saying a
consumer must sample on it.

**4. A DIP MAME had persisted into `cfg/`** (MS1-25) sent the whole
investigation sideways. Forcing the Flip Screen DIP for the M1 flipped-frame
capture left `<port tag=":DSW2" mask="1" value="0"/>` in `cfg/avspirit.cfg`;
MAME reads that back on every later run and `-noreadconfig` does not prevent
it. So the core rendered a flipped screen because the DIP said so, and was
compared against a reference captured before the contamination. Four correct
measurements -- byte-identical VRAM, palette and object RAM; 131 matching
protection transactions; and the same video RTL fed the sim's own state
through `sim/rtl/video_state` giving MAME's frame with zero differing pixels
-- all said the video was fine, and the contaminated constant won anyway for
far too long.

## Reproducing

```sh
cd sim/rtl/ms1_frames && make
MS1_FRAMEDIR=/tmp/rtl_b ./obj_dir/Vms1bcd_core /tmp/fr_avspirit 0 200 FF FF FF FD FF
python3 ../../../tools/frame_compare.py /tmp/rtl_b /tmp/fr_avspirit/frames 200
```

`DSW2` must be `FD`, not `FC`: bit 0 is Flip Screen and `1` means off. Delete
`cfg/<game>.cfg` before capturing reference frames or input-port values.
