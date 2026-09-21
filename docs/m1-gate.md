# M1 gate — video against MAME state

`docs/PLAN.md` M1 requires the video to be **pixel-exact against MAME's own
frame** for a named list of scenes, with non-blank pixel counts reported
beside every match. This is that evidence.

The subject is the RTL -- `rtl/jaleco/ms1_tilemap.sv`, `ms1_sprites.sv`,
`ms1_prio.sv` and `ms1_video.sv` -- driven from a captured MAME RAM dump
through `sim/rtl/video_state`, which is what M1 asks for.

It was built against `tools/ms1_video_model.py`, the Python reading of
`megasys1_v.cpp` and `ms1_tmap.cpp` written first per docs/PLAN.md 4.D item 9.
That model is pixel-exact against MAME in its own right, and having it made
every RTL bug below a five-minute diff against a known-good reference rather
than a hunt against a moving target.

Every scene below was found by scanning all sixteen sets for the register
configuration it needed (`MS1_SCAN=1`), because no single game exercises them
all. The flipped frame does not occur in any attract mode at all and was
forced through the Flip Screen DIP (`MS1_DIP="Flip Screen=0"`).

## Gate evidence — RTL through `sim/rtl/video_state`

```
| gate item                              | capture        |    F | nonblank |   diff |
|----------------------------------------|----------------|-----:|---------:|-------:|
| a 16x16-tile scene                     | avspirit_demo  |   22 |    56201 |      0 |
|                                        | avspirit_demo  |  242 |    56343 |      0 |
|                                        | avspirit_demo  |  302 |    56343 |      0 |
| an 8x8-tile scene                      | edf_pages      |    5 |    57344 |      0 |
|                                        | edf_pages      |   55 |    57344 |      0 |
|                                        | edf_pages      |  105 |    57344 |      0 |
| a non-default page layout (N=2)        | edf_pages      |   13 |    57344 |      0 |
|                                        | edf_pages      |  111 |    57344 |      0 |
|                                        | edf_pages      |  193 |    57344 |      0 |
| a non-default page layout (N=3)        | hayaosi1_pages |    5 |    57344 |      0 |
|                                        | hayaosi1_pages |   55 |    57344 |      0 |
|                                        | hayaosi1_pages |  130 |    57344 |      0 |
| 3 layers + sprites over and under      | bigstrik_split |  157 |    31069 |      0 |
|                                        | bigstrik_split |  200 |    31016 |      0 |
|                                        | bigstrik_split |  240 |    31716 |      0 |
| a sprite-split scene (bit 8)           | bigstrik_split |  180 |    31154 |      0 |
|                                        | bigstrik_split |  220 |    31746 |      0 |
| a flipped frame                        | avspirit_flip  |    5 |    56353 |      0 |
|                                        | avspirit_flip  |   55 |    56343 |      0 |
|                                        | avspirit_flip  |  105 |    56343 |      0 |
| mode C                                 | 64street_demo  |   34 |    23605 |      0 |
|                                        | 64street_demo  |  154 |    21455 |      0 |
|                                        | 64street_demo  |  184 |    22151 |      0 |
| sprites, no split (bit 8 clear)        | avspirit_demo  |  242 |    56343 |      0 |
|                                        | avspirit_demo  |  302 |    56343 |      0 |
| mode D (2 layers, inverted)            | peekaboo_demo  |   34 |    57344 |      0 |
|                                        | peekaboo_demo  |  154 |    57344 |      0 |
|                                        | peekaboo_demo  |  214 |    57344 |      0 |

pass 28, fail 0
```

**Every gate item is 0 differing pixels against MAME's own frame.**

### Coverage was checked, not assumed

The first run of this table passed 26 of 26 while testing almost nothing about
sprites: the bigstrik scenes chosen for the two sprite rows contain **zero
sprite pixels**, and so do all three 64street scenes. The rows were green
because the sprite engine contributed nothing to them.

Every row is now audited for what it actually exercises:

| row | sprite px | layers | split | flip |
|---|---:|---:|:--:|:--:|
| 3 layers + sprites over and under | 32768 | 3 | yes | no |
| sprite split (bit 8) | 32768 | 3 | yes | no |
| sprites, no split | 791-3839 | 3 | no | no |
| flipped frame | 3226-4708 | 3 | no | **yes** |
| mode D | 1372-1635 | 2 | no | no |
| page layout N=3 | 57344 | 3 | no | no |

### The bugs this found

| where | bug | why it hid |
|---|---|---|
| `ms1_tilemap.sv` | `(row/2)/16` written as `row >> 6` instead of `row >> 5` | only bites when a layer scrolls past row 32; layer 0 never did |
| `ms1_sprites.sv` | object and sprite words latched one state late, so every field read as the next field along | every value is still a plausible sprite, just the wrong one |
| `ms1_sprites.sv` | position sign-extended per term instead of `sext((pos+disp) & 0x1ff, 9)` | only differs when the 9-bit sum wraps |
| `ms1_video.sv` | sprite "low priority" polarity inverted | costs 25205 px on a split scene, and exactly 0 anywhere else |
| harness | collected pixels at latency 6, then 3, where the pipeline is 4 and 2 | a one-pixel shift that reads like an addressing bug in whichever block you suspect |

Two of those five were found only after the coverage audit forced the gate onto
scenes that actually contain sprites.
## Whole-capture rates (the Python model)

The model's own rates over every frame of every capture, which bound what the
oracle can express and therefore what the RTL can be tested against:

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
