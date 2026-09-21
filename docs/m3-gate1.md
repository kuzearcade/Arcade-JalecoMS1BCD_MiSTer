# M3 gate 1 — golden-byte audits  (MET)

`docs/PLAN.md` M3 gate: "golden-byte audits with 0 wrong for every region".

The subject is `rtl/ms1bcd/ms1bcd_rom_hw.sv` driving the real `rtl/sdram.sv`
against `sim/models/sdram_model.sv`, filled by a real `ioctl_download` byte
stream in loader order. Every byte is then read back **through the cache the
core itself uses**, not through a second path built to be auditable.

## Result

| set | mode | bytes/words checked | wrong |
|---|---|---:|---:|
| avspirit | B | 2638336 | **0** |
| 64street | C | 3097088 | **0** |
| peekaboo | D | 2769408 | **0** |

Per region, all three modes: `maincpu`, `audiocpu`, `iomcu`/`mcu`, `scroll1`,
`scroll2`, `scroll3`, `sprites`, `oki1`, `oki2` and the priority PROM. Mode D
has no sound CPU, no third scroll layer and no second OKI; those are reported
as absent rather than as passes.

Reproduce:

```
tools/gen_ms1bcd_ioctl.py avspirit --out-dir /tmp/gen_avspirit \
    --stream sim/rtl/ms1_hw/roms/avspirit_ioctl.bin \
    --prom sim/rtl/ms1_hw/roms/avspirit_prom.bin
cd sim/rtl/ms1_hw && make
TB_STREAM=roms/avspirit_ioctl.bin TB_PROM=roms/avspirit_prom.bin \
    TB_IMGDIR=/tmp/gen_avspirit TB_STEP=1 ./obj_dir/Vms1_hw_top
```

## What it caught immediately

The first run failed on exactly one word: `maincpu` address 0, reading `0x0000`
where the image has `0x0008`. It was not a testbench artifact.

The caches were running during the download. The core's address inputs sit at
their reset value for the whole transfer, so `rom_addr` is 0 throughout — and
the main cache did what a cache does: fetched word 0, cached the zeros that
were there **before** the stream wrote it, and kept them. On the board that is
a 68000 leaving reset on a zeroed vector, with a perfectly correct SDRAM
behind it.

Every cache now holds reset for the whole transfer. This is exactly why SS-15
insists the **loader's** reset be a separate, power-on-only signal: everything
else in this module may be reset freely while the ROM streams; the loader may
not, because its request register is cleared by its reset and `ioctl_wait` is
suppressed with it, so the loader streams every byte at full speed and reports
success while nothing lands.

The wider point is the one the gate exists for. A sampled audit of 666
addresses found this; a frame diff would have shown a black screen and said
nothing about which of a dozen candidate causes it was.

## Byte order, decided per consumer

`docs/PLAN.md` 4.A.5 says byte order is a per-consumer decision, and the two
conventions here genuinely disagree:

- the download writes the byte at an **even** ioctl address into the SDRAM
  word's **low** lane, which is what every byte cache in the tree assumes
  (`rom_cache_n_byte.sv:50`, `oki_rom_cache.sv:82`) and therefore what the
  tile, sprite, OKI and MCU fetches need;
- the two 68000s want the opposite. The reference sim builds their words as
  `(image[even] << 8) | image[odd]`, and that is the right convention because
  it is what puts avspirit's reset vector at SP `0x00080000`, PC `0x000006B2`.

So the swap lives on those two read paths and nowhere else. Doing it in the
download instead would have produced a perfect-looking program ROM and
silently mangled every graphics and sample byte.

## One table, enforced rather than asserted

`tools/gen_rom_map.py` generates `rtl/ms1bcd/ms1bcd_rom_map.vh` from
`tools/ms1_romdata.py` -- the same table `tools/gen_ms1bcd_mra.py` derives the
.mra layout from -- and `--check` fails if the header is stale.
`tools/gen_ms1bcd_ioctl.py` emits the per-region reference images and the
ioctl stream from one code path; its images are **byte-identical** to the ones
the reference sim has been passing M1 and M2 against, which is what makes
"frames identical to the reference sim" a meaningful claim rather than a
comparison of two different ROM sets.

It also matches zip members by CRC. `avspirit.zip` here predates MAME's
current names (`spirit05.rom` against `jaleco_a.spirit_5.5b`), and a name-only
lookup calls a perfectly good romset broken -- which is worth knowing before
M4, because the generated `.mra` files name the dumps MAME's way.
