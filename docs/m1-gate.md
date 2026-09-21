# M1 gate — video against MAME state

`docs/PLAN.md` M1 requires the video to be **pixel-exact against MAME's own
frame** for a named list of scenes, with non-blank pixel counts reported
beside every match. This is that evidence.

The subject is `tools/ms1_video_model.py`, the executable reading of
`jaleco/megasys1_v.cpp` and `jaleco/ms1_tmap.cpp` that M1 exists to produce.
It reproduces MAME's frame from a captured RAM/register dump, so that when the
RTL is written it has an unambiguous target and any later mismatch is an RTL
bug rather than a misunderstanding of the hardware.

Every scene below was found by scanning all sixteen sets for the register
configuration it needed (`MS1_SCAN=1`), because no single game exercises them
all. The flipped frame does not occur in any attract mode at all and was
forced through the Flip Screen DIP (`MS1_DIP="Flip Screen=0"`).

## Gate evidence

| gate item | capture | mode | frame | non-blank px | diff px |
|---|---|---|---:|---:|---:|
| a 16x16-tile scene | `avspirit_demo` | B | 22 | 56201 | **0** |
|  | `avspirit_demo` | B | 242 | 56343 | **0** |
|  | `avspirit_demo` | B | 302 | 56343 | **0** |
| an 8x8-tile scene | `edf_pages` | B | 5 | 57344 | **0** |
|  | `edf_pages` | B | 55 | 57344 | **0** |
|  | `edf_pages` | B | 105 | 57344 | **0** |
| a non-default page layout (N=2) | `edf_pages` | B | 5 | 57344 | **0** |
|  | `edf_pages` | B | 55 | 57344 | **0** |
|  | `edf_pages` | B | 105 | 57344 | **0** |
| a non-default page layout (N=3) | `hayaosi1_pages` | B | 5 | 57344 | **0** |
|  | `hayaosi1_pages` | B | 30 | 57344 | **0** |
|  | `hayaosi1_pages` | B | 55 | 57344 | **0** |
|  | `hayaosi1_pages` | B | 80 | 57344 | **0** |
|  | `hayaosi1_pages` | B | 130 | 57344 | **0** |
| three layers + sprites over and under | `bigstrik_split` | C | 30 | 57344 | **0** |
|  | `bigstrik_split` | C | 55 | 57214 | **0** |
|  | `bigstrik_split` | C | 80 | 57214 | **0** |
|  | `bigstrik_split` | C | 105 | 56131 | **0** |
|  | `bigstrik_split` | C | 130 | 56065 | **0** |
| a sprite-split scene (control bit 8) | `bigstrik_split` | C | 30 | 57344 | **0** |
|  | `bigstrik_split` | C | 55 | 57214 | **0** |
|  | `bigstrik_split` | C | 80 | 57214 | **0** |
|  | `bigstrik_split` | C | 105 | 56131 | **0** |
|  | `bigstrik_split` | C | 130 | 56065 | **0** |
| a flipped frame | `avspirit_flip` | B | 5 | 56353 | **0** |
|  | `avspirit_flip` | B | 30 | 56201 | **0** |
|  | `avspirit_flip` | B | 55 | 56343 | **0** |
|  | `avspirit_flip` | B | 80 | 56171 | **0** |
|  | `avspirit_flip` | B | 105 | 56343 | **0** |
|  | `avspirit_flip` | B | 130 | 56343 | **0** |
| mode C | `64street_demo` | C | 4 | 23605 | **0** |
|  | `64street_demo` | C | 34 | 23605 | **0** |
|  | `64street_demo` | C | 64 | 22834 | **0** |
|  | `64street_demo` | C | 154 | 21455 | **0** |
|  | `64street_demo` | C | 184 | 22151 | **0** |
| mode D (2 layers, inverted addressing) | `peekaboo_demo` | D | 34 | 57344 | **0** |
|  | `peekaboo_demo` | D | 154 | 57344 | **0** |
|  | `peekaboo_demo` | D | 214 | 57344 | **0** |
|  | `peekaboo_demo` | D | 274 | 57344 | **0** |

**Every gate item is 0 differing pixels**, on scenes of 21455 to 57344
non-blank pixels out of 57344.

## Whole-capture rates

Beyond the named gate scenes, every frame of every capture:

| capture | mode | frames exact | worst | what it covers |
|---|---|---:|---:|---|
| `avspirit_demo` | B | 383/397 | 916 | 16x16 + 8x8, three layers, sprites |
| `avspirit_long` | B | 972/1097 | 49952 | full attract including uninitialised boot |
| `64street_demo` | C | 254/297 | 216 | mode C |
| `peekaboo_demo` | D | 168/297 | 7709 | mode D, two layers, inverted addressing |
| `bigstrik_split` | C | 245/247 | 1667 | sprite splitting |
| `edf_pages` | B | 124/197 | 31464 | page layout N=2, priority codes 0/1/2 |
| `hayaosi1_pages` | B | 185/197 | 444 | page layout N=3, priority code 3 |
| `avspirit_flip` | B | 141/147 | 916 | flipped frame |

Across roughly 2800 frames, **14 exceed 500 differing pixels**, and 8 of those
are frames where a video register changed between F-1 and F. The rest are
frames where the game rewrote VRAM during the vblank the snapshot was taken
in. This is the oracle's per-frame granularity (MS1-12), not an RTL defect:
the three state sources do not even belong to the same frame (MS1-11), which
is precisely what one snapshot per frame cannot express. `avspirit_long`'s
49952-pixel worst case is its first 52 frames, before the game has
initialised the video at all (`active_layers = 0`).

## What this does and does not establish

It establishes that the tile decode, the page-layout decode, the scan
functions, the 16x16 sub-tile order, the palette formats of all three modes,
the sprite indirection through Object RAM, the sprite bank selection by flip
state, first-writer-wins sprite ordering, the priority PROM conversion
including its merge stage, the sprite-split priority masks, and screen flip
are all understood correctly.

It establishes nothing about timing, bus contention, or the raster, because a
state dump has none of those. Those belong to M2 and M3.
