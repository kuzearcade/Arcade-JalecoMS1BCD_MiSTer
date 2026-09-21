#!/usr/bin/env python3
"""Build a set's region images AND its ioctl_download byte stream.

One code path for both, from tools/ms1_romdata.py and the same layout the
.mra generator uses, so the reference sim's arrays and the hardware sim's
SDRAM image cannot disagree about a single byte -- which is the only way
"frames identical to the reference sim" means anything (docs/PLAN.md M3).

    tools/gen_ms1bcd_ioctl.py avspirit --out-dir /tmp/fr_avspirit \
        --stream sim/rtl/ms1_hw/roms/avspirit_ioctl.bin

The stream is a flat byte copy of each region at its fixed base, padded to
the region size. No reordering happens here: the core's download writes the
byte at an even ioctl address to the SDRAM word's LOW lane, and any consumer
that wants the other convention swaps on its own read path
(ms1bcd_rom_hw.sv).
"""
import argparse, os, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ms1_romdata import ROMDATA
import gen_ms1bcd_mra as G

# Region -> the reference sim's file name for it.
IMG = {'maincpu': 'maincpu.bin', 'audiocpu': 'audiocpu.bin',
       'iomcu': 'iomcu.bin', 'mcu': 'iomcu.bin',
       'scroll1': 'gfx0.bin', 'scroll2': 'gfx1.bin', 'scroll3': 'gfx2.bin',
       'sprites': 'sprites.bin', 'oki1': 'oki1.bin', 'oki2': 'oki2.bin'}


def read_member(zips, name, crc=None):
    """By name, else by CRC.

    A user's zip may predate MAME's current names for the same dump --
    avspirit.zip here holds `spirit05.rom` where megasys1.cpp now declares
    `jaleco_a.spirit_5.5b`. MAME merges split sets by CRC for exactly this
    reason, so a name-only lookup reports a perfectly good romset as broken.
    """
    for z in zips:
        if not os.path.exists(z):
            continue
        with zipfile.ZipFile(z) as zf:
            if name in zf.namelist():
                return zf.read(name)
    if crc:
        want = int(crc, 16)
        for z in zips:
            if not os.path.exists(z):
                continue
            with zipfile.ZipFile(z) as zf:
                for zi in zf.infolist():
                    if zi.CRC == want:
                        return zf.read(zi.filename)
    raise SystemExit(f'{name} (crc {crc}): not found in {zips}')


def build_region(setname, reg, size):
    """The region's bytes, padded to `size`, in the core's own order."""
    zips = G.zip_paths(setname)
    out = bytearray(size)
    avail = G.usable_parts(reg)
    pairs = [p for p in avail if p['form'] == 'LOAD16_BYTE']
    singles = [p for p in avail if p['form'] != 'LOAD16_BYTE']
    pos = 0
    by_off = {}
    for p in pairs:
        by_off.setdefault(p['offset'] & ~1, {})[p['offset'] & 1] = p
    for off in sorted(by_off):
        pr = by_off[off]
        if 0 in pr and 1 in pr:
            # ROM_LOAD16_BYTE: the offset-0 chip supplies EVEN byte positions.
            # That is what puts avspirit's reset vector at SP 0x00080000 when
            # the 68000 reads (image[even] << 8) | image[odd].
            a = read_member(zips, pr[0]['name'], pr[0].get('crc'))
            b = read_member(zips, pr[1]['name'], pr[1].get('crc'))
            n = min(len(a), len(b))
            for i in range(n):
                out[pos + 2 * i]     = a[i]
                out[pos + 2 * i + 1] = b[i]
            pos += 2 * n
        else:
            p = pr.get(0) or pr.get(1)
            d = read_member(zips, p['name'], p.get('crc'))
            out[pos:pos + len(d)] = d
            pos += len(d)
    for p in sorted(singles, key=lambda q: q['offset']):
        d = read_member(zips, p['name'], p.get('crc'))
        out[pos:pos + len(d)] = d
        pos += len(d)
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('setname')
    ap.add_argument('--out-dir', help='write the per-region reference images here')
    ap.add_argument('--stream', help='write the flat ioctl byte stream here')
    ap.add_argument('--prom', help='write the priority PROM (ioctl index 1) here')
    a = ap.parse_args()

    e = ROMDATA[a.setname]
    lay, total = G.layout(e['mode'])
    stream = bytearray(total)
    if a.out_dir:
        os.makedirs(a.out_dir, exist_ok=True)

    print(f'{a.setname}: mode {e["mode"]}, {total} bytes')
    for rn, size, base in lay:
        reg = next((r for r in e['regions'] if r['name'] == rn), None)
        data = build_region(a.setname, reg, size) if reg and G.usable_parts(reg) else bytes(size)
        stream[base:base + size] = data
        nz = sum(1 for b in data if b)
        print(f'  {rn:9s} @ 0x{base:06X} 0x{size:06X}  {nz} non-zero bytes')
        if a.out_dir and rn in IMG:
            open(os.path.join(a.out_dir, IMG[rn]), 'wb').write(data)

    if a.stream:
        os.makedirs(os.path.dirname(os.path.abspath(a.stream)), exist_ok=True)
        open(a.stream, 'wb').write(stream)
        print(f'  -> {a.stream} ({len(stream)} bytes)')

    promreg = next((r for r in e['regions'] if r['name'] == 'proms'), None)
    if promreg and G.usable_parts(promreg):
        pd = build_region(a.setname, promreg, promreg['size'])
        if a.prom:
            open(a.prom, 'wb').write(pd)
        if a.out_dir:
            open(os.path.join(a.out_dir, 'prom.bin'), 'wb').write(pd)
        print(f'  proms     {len(pd)} bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
