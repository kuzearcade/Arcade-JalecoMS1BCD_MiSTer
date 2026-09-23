#!/usr/bin/env python3
"""Generate the .mra files, the hardware ioctl stream and the sim ROM images
for Arcade-JalecoMS1BCD from ONE table.

    tools/gen_ms1bcd_mra.py                 write releases/*.mra
    tools/gen_ms1bcd_mra.py --check         off-board load model, writes nothing
    tools/gen_ms1bcd_mra.py --ioctl <set>   the index-0 byte stream for the hw sim
    tools/gen_ms1bcd_mra.py --layout        print the SDRAM layout the core must match

The ROM part lists come from tools/ms1_romdata.py, which tools/extract_ms1_roms.py
generates mechanically from MAME's driver -- see docs/PLAN.md 1.5 and section 4.A.

SDRAM layout: regions are laid out at FIXED per-mode bases, each padded to that
mode's largest instance of the region, and the .mra emits the pad as a `fill`
part. NMK16 instead packs every set contiguously and carries per-set base
constants in the core; with three modes and seventeen sets that would be
seventeen base tables. Fixed bases cost a little SDRAM (nothing, at 32 MB) and
buy one base table per mode, which the core can select from the game-mode byte.

The priority PROM is NOT in this stream. It goes out as <rom index="1"> into a
write port on ms1_prio.sv, because it is read per pixel and belongs in block
RAM, and because keeping it a separate index makes "is any PROM data compiled
into the bitstream?" a question with an obvious answer (docs/PLAN.md 2.3).
"""
import argparse, os, re, sys, zipfile, zlib
from xml.sax.saxutils import escape as _xml_escape


# --- XML well-formedness (docs/PLAN.md 4.A item 11) -------------------------
# MiSTer's own .mra reader is lenient; the downloader database's parser is not,
# and a file it cannot parse silently loses EVERY content-derived tag -- the
# per-core tag, the setname term, the alternatives marker. Ten NMK16 files and
# three Sand Scorpion files shipped that way before anyone noticed. The first
# version of THIS generator reproduced the same defect on its first run (a `--`
# in the header comment on line 2 of every file), which is why the escaping is
# here and not left to care.

def x(v):
    """Element text or attribute value: & < > must be entities."""
    return _xml_escape(str(v))


def xc(t):
    """XML comment body: the spec forbids `--` anywhere inside a comment and
    forbids a comment ending in `-`."""
    t = str(t).replace('--', '\u2014')
    return t + ' ' if t.endswith('-') else t

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ms1_romdata import ROMDATA

ROOT = os.path.join(HERE, '..')
ROMS = os.path.join(ROOT, 'mame_roms')
RELEASES = os.path.join(ROOT, 'releases')

# ---------------------------------------------------------------- scope
# edfbl is deliberately NOT built. It is not a System B board: a 6 MHz 68000,
# no sound CPU at all, a PIC in place of the TMP91640, one OKI with banked
# samples and a PROM that is not confirmed to match. MAME itself marks it
# MACHINE_NO_SOUND. Shipping it would mean shipping a silent game with
# unknown protection; see docs/known-issues.md MS1-2.
EXCLUDED = {'edfbl': 'not a System B board (PIC, no sound CPU, banked OKI); MAME flags it NO_SOUND'}

# Per-set attributes that are not in the ROM table.
#   oki_hz: both sample chips. 4 MHz on B/C, except hayaosi1 which MAME
#           overrides to 2 MHz ("correct speed, but unknown OSC + divider
#           combo"). 2 MHz on D. Every value is an exact division of the
#           48 MHz clk_sys (/12 and /24), so this is a mux, not a PLL.
#   prot:   derived from the MAME machine configuration recorded in the ROM
#           table, never from the presence of an MCU ROM region.  hayaosi1
#           and peekaboo both ship a dumped TMP91640 that MAME does not run,
#           so region presence is not evidence that the MCU is live.
#           'mcu'      the TMP91640 runs its dumped ROM
#           'iosim'    the seven-value command table below
#           'none'     the bootleg wires the ports straight in
#           'peekaboo' System D's own handler at 0x100000
#                      (protection_peekaboo_r/w); system_D instantiates no
#                      MCU device at all, and its scheme is unrelated to the
#                      B/C command table.
OKI_4MHZ, OKI_2MHZ = 4_000_000, 2_000_000
IOSIM_SEQ = {
    # from megasys1.h and the ip_select_w comment block: the command values
    # that select SYSTEM, P1, P2, DSW1, DSW2, then two fixed replies
    'hayaosi1':  (0x51, 0x52, 0x53, 0x54, 0x55, 0xFC, 0x06),
    'chimeraba': (0x56, 0x52, 0x53, 0x55, 0x54, 0xFA, 0x06),
    # historical values for the sets MAME has since moved to the real MCU;
    # kept because they are the fallback when a user's romset has no MCU dump
    'avspirit':  (0x37, 0x35, 0x36, 0x33, 0x34, None, 0x06),
    '64street':  (0x57, 0x53, 0x54, 0x55, 0x56, None, 0x06),
    'bigstrik':  (0x58, 0x54, 0x55, 0x56, 0x57, None, 0x06),
    'cybattlr':  (0x56, 0x52, 0x53, 0x54, 0x55, None, 0x06),
    'edf':       (0x20, 0x21, 0x22, 0x23, 0x24, None, 0x06),
}
# The MAME machine configuration is the only authority on which protection is
# actually live.  Keyed exhaustively so an unrecognised config fails loudly
# rather than defaulting to a plausible-looking wrong byte.
PROT_BY_CFG = {
    'system_B_iomcu':    'mcu',
    'system_C_iomcu':    'mcu',
    'system_B_hayaosi1': 'iosim',     # has an iomcu region; MAME does not run it
    'system_C_iosim':    'iosim',
    'system_B_monkelf':  'none',      # bootleg, ports wired straight in
    'system_D':          'peekaboo',  # has an mcu region; system_D has no MCU device
    'system_Bbl':        'none',      # edfbl, excluded above
}
EXTRA = {}
for _s, _e in ROMDATA.items():
    _cfg = _e['cfg']
    if _cfg not in PROT_BY_CFG:
        raise SystemExit(f'{_s}: unknown machine config {_cfg!r}; add it to PROT_BY_CFG')
    EXTRA[_s] = dict(
        oki_hz = OKI_2MHZ if (_s == 'hayaosi1' or _e['mode'] == 'D') else OKI_4MHZ,
        prot   = PROT_BY_CFG[_cfg],
    )

# ------------------------------------------------- SDRAM layout per mode
# Region order is the core's own; it is NOT MAME's declaration order.
REGION_ORDER = {
    'B': ['maincpu', 'audiocpu', 'iomcu', 'scroll1', 'scroll2', 'scroll3', 'sprites', 'oki1', 'oki2'],
    'C': ['maincpu', 'audiocpu', 'iomcu', 'scroll1', 'scroll2', 'scroll3', 'sprites', 'oki1', 'oki2'],
    'D': ['maincpu', 'mcu',      'scroll1', 'scroll2', 'sprites', 'oki1'],
}

def mode_sets(mode):
    return [s for s, e in ROMDATA.items() if e['mode'] == mode and s not in EXCLUDED]

def region_size(setname, region):
    for r in ROMDATA[setname]['regions']:
        if r['name'] == region:
            return r['size']
    return 0

def layout(mode):
    """[(region, size, base)] at fixed per-mode bases."""
    sets = mode_sets(mode)
    out, base = [], 0
    for rn in REGION_ORDER[mode]:
        size = max((region_size(s, rn) for s in sets), default=0)
        out.append((rn, size, base))
        base += size
    return out, base

# ---------------------------------------------------------------- zips
def zip_paths(setname):
    e = ROMDATA[setname]
    names = [setname] + ([e['parent']] if e['parent'] else [])
    return [os.path.join(ROMS, n + '.zip') for n in names]

def zip_index(setname):
    """basename -> (zipfile, member); and crc -> member, for diagnosis."""
    byname, bycrc = {}, {}
    for p in zip_paths(setname):
        if not os.path.exists(p):
            continue
        z = zipfile.ZipFile(p)
        for n in z.namelist():
            d = z.read(n)
            byname.setdefault(os.path.basename(n).lower(), (z, n, d))
            bycrc.setdefault(format(zlib.crc32(d) & 0xffffffff, '08x'), (z, n, d))
    return byname, bycrc

# ---------------------------------------------------------------- .mra
def mra_zip_attr(setname):
    e = ROMDATA[setname]
    return setname + '.zip' + (('|' + e['parent'] + '.zip') if e['parent'] else '')

def usable_parts(reg):
    """The parts that exist as files in a romset.

    A NO_DUMP entry has no file and no CRC, so it must never reach the .mra or
    the byte stream: the region is padded instead and the core falls back to
    the simulated protection that PROT_BY_CFG already selects for exactly
    those sets.  A BAD_DUMP entry is a real file that MAME deliberately
    substitutes (chimerab borrows Cybattler's MCU and 64street's PROM); it is
    the best data that exists, so it ships, declared in the .mra.
    """
    return [q for q in reg['parts'] if q.get('crc')]

def dump_note(reg):
    """An XML comment declaring any substituted or undumped part."""
    out = []
    for q in reg['parts']:
        f = q.get('flag', 'OK')
        if f == 'BAD_DUMP':
            out.append(f'    <!-- {xc(q["name"])}: MAME BAD_DUMP, a documented '
                       f'substitution; shipped as the best available data. -->\n')
        elif f == 'NO_DUMP':
            out.append(f'    <!-- {xc(q["name"])}: undumped. Omitted; the core '
                       f'uses simulated protection. -->\n')
    return ''.join(out)

def parts_xml(setname):
    """Region parts in the core's order, each region padded to its fixed size."""
    e = ROMDATA[setname]
    lay, _ = layout(e['mode'])
    out = []
    for rn, size, base in lay:
        reg = next((r for r in e['regions'] if r['name'] == rn), None)
        out.append(f'    <!-- {xc(rn)} 0x{size:06X} @ 0x{base:06X} -->\n')
        if reg is None:
            out.append(f'    <part repeat="0x{size:X}">00</part>\n')
            continue
        out.append(dump_note(reg))
        avail = usable_parts(reg)
        if not avail:
            out.append(f'    <part repeat="0x{size:X}">00</part>\n')
            continue
        used = 0
        pairs, singles = [], []
        for p in avail:
            (pairs if p['form'] == 'LOAD16_BYTE' else singles).append(p)
        if pairs:
            # ROM_LOAD16_BYTE: even offset = high byte on the 68000, and
            # map="01" is the EVEN byte of the output word (measured on the
            # board -- see build_stream), so the OFFSET-0 file goes on map="01".
            by_off = {}
            for p in pairs:
                by_off.setdefault(p['offset'] & ~1, {})[p['offset'] & 1] = p
            for off in sorted(by_off):
                pr = by_off[off]
                if 0 in pr and 1 in pr:
                    out.append('    <interleave output="16">\n')
                    out.append(f'      <part crc="{pr[0]["crc"]}" name="{x(pr[0]["name"])}" map="01"/>\n')
                    out.append(f'      <part crc="{pr[1]["crc"]}" name="{x(pr[1]["name"])}" map="10"/>\n')
                    out.append('    </interleave>\n')
                    used += pr[0]['length'] + pr[1]['length']
                else:
                    p = pr.get(0) or pr.get(1)
                    out.append(f'    <part crc="{p["crc"]}" name="{x(p["name"])}"/>\n')
                    used += p['length']
        for p in sorted(singles, key=lambda q: q['offset']):
            out.append(f'    <part crc="{p["crc"]}" name="{x(p["name"])}"/>\n')
            used += p['length']
        if used < size:
            out.append(f'    <part repeat="0x{size - used:X}">00</part>\n')
        elif used > size:
            raise SystemExit(f'{setname}/{rn}: parts total 0x{used:X} exceed the region 0x{size:X}')
    return ''.join(out)

def prom_xml(setname):
    reg = next((r for r in ROMDATA[setname]['regions'] if r['name'] == 'proms'), None)
    if not reg or not usable_parts(reg):
        return ('\n  <!-- No priority PROM in this set\'s dump. -->\n')
    body = dump_note(reg) + ''.join(
        f'    <part crc="{p["crc"]}" name="{x(p["name"])}"/>\n' for p in usable_parts(reg))
    return ('\n  <!-- Priority PROM (512 B). Its own index so it reaches a write\n'
            '       port on ms1_prio.sv rather than SDRAM, and so that "is any PROM\n'
            '       data in the bitstream?" stays an easy question. -->\n'
            f'  <rom index="1" zip="{mra_zip_attr(setname)}" md5="none">\n{body}  </rom>\n')

MODE_ID = {'B': 0x00, 'C': 0x01, 'D': 0x02}
PROT_ID = {'mcu': 0x00, 'iosim': 0x20, 'none': 0x40, 'peekaboo': 0x60}

from ms1_dipdata import DIPDATA

# Per-set ROM patches, as MAME applies them in its init_ functions. Offsets
# are BYTES into the index-0 stream, which starts with maincpu at 0.
#
# monkelf: MAME's init_monkelf does
#     m_rom_maincpu[0x00744/2] = 0x4e71;  // weird check, 0xe000e R is a
#                                         // port-based trap?
# and the word there really is 4E72 2700 -- STOP #$2700, a halt with every
# interrupt masked. The bootleg's program reaches it when a check fails;
# NOP steps past. MS1-55.
PATCHES = {
    'monkelf': [(0x000744, '4E 71')],
}

def patches_xml(setname):
    out = []
    for off, data in PATCHES.get(setname, []):
        out.append(f'    <patch offset="0x{off:X}">{data}</patch>\n')
    return ''.join(out)

# MAME spells coinage out ("1 Coin/2 Credits"); the OSD is narrow, and the
# sibling NMK16 .mra files use the compact form, so display it that way. Only
# the LABEL changes -- bit positions and order come from MAME.
_COIN = re.compile(r'^(\d+) Coins?/(\d+) Credits?$')

def dip_id(name):
    if name == 'Free Play':
        return 'Free_Play'
    m = _COIN.match(name)
    return f'{m.group(1)}C_{m.group(2)}C' if m else name

def switches_xml(setname, cfg):
    """The <switches> block: MAME's own defaults, and one <dip> per switch.

    MiSTer needs at least one <dip> here. With an EMPTY <switches> element it
    never sends the block at all, so the third byte -- the game-mode byte this
    core cannot run without -- never reaches the core and `mode` reads its idle
    3 (MS1-47). The DIP submenu is also a feature in its own right; it had
    never been populated.

    `bits` is a RANGE, "first,last". Writing out the individual bit numbers
    instead makes MiSTer read the field at the wrong width.
    """
    e = DIPDATA[setname]
    out = [f'  <switches default="{e["dsw1"]:02X},{e["dsw2"]:02X},{cfg:02X}">\n']
    for d in e['dips']:
        lo, hi = d['bits']
        bits = f'{lo}' if lo == hi else f'{lo},{hi}'
        ids = ','.join(x(dip_id(i)) for i in d['ids'])
        out.append(f'    <dip bits="{bits}" name="{x(d["name"])}" ids="{ids}"/>\n')
    out.append('  </switches>\n')
    return ''.join(out)

def mra(setname):
    e, ex = ROMDATA[setname], EXTRA[setname]
    lay, total = layout(e['mode'])
    cfg = MODE_ID[e['mode']] | (0x10 if ex['oki_hz'] == OKI_2MHZ else 0) \
                             | PROT_ID[ex['prot']]
    return f"""<!--
  {xc(e['desc'])} \u2014 Jaleco {e['year']}, MAME jaleco/megasys1.cpp ({setname}).
  Mega System 1 type {e['mode']}. Generated by tools/gen_ms1bcd_mra.py from
  tools/ms1_romdata.py, which is extracted from the driver; do not hand-edit.

  SDRAM image: fixed per-mode bases, each region padded to the mode's largest
  instance so the core needs one base table per mode rather than one per set.
  Total 0x{total:06X} bytes.

  <switches> byte 2 is not a DIP: it is the game-mode byte, read at RUN TIME
  only (never during the ROM stream \u2014 index 254 arrives last). Bits 1:0 mode
  B/C/D, bit 4 sample clock 2 MHz, bits 6:5 protection (0 MCU, 1 simulated,
  2 none, 3 System D's own).
-->
<misterromdescription>
  <name>{x(e['desc'])}</name>
  <mratimestamp>202609200000</mratimestamp>
  <mameversion>0289</mameversion>
  <setname>{setname}</setname>
  <year>{e['year']}</year>
  <manufacturer>{x(e['manufacturer'])}</manufacturer>
  <category>Arcade</category>
  <rbf>JalecoMS1BCD</rbf>
{'  <rotation>vertical (cw)</rotation>' + chr(10) if e['rot'] == 90 else ''}
{switches_xml(setname, cfg)}
{buttons_xml(setname)}

  <rom index="0" zip="{mra_zip_attr(setname)}" md5="none">
{parts_xml(setname)}{patches_xml(setname)}  </rom>
{prom_xml(setname)}</misterromdescription>
"""

# MiSTer's <buttons> list is what the OSD offers to remap, so a button with
# no entry here cannot be bound to a pad at all. Three names covers the
# generic layout; peekaboo's panel adds a fourth ("option"), and its third is
# the "stage clear" button rather than a normal attack.  hayaosi1 wants five
# and gets three -- its buttons 4 and 5 are on the keyboard. MS1-41.
BUTTONS = {
    'peekaboo':  'Button 1,Button 2,Stage Clear,Option,Start,Coin',
    'peekaboou': 'Button 1,Button 2,Stage Clear,Option,Start,Coin',
}
BUTTON_DEFAULTS = {
    'peekaboo':  'Y,B,A,X,Start,R',
    'peekaboou': 'Y,B,A,X,Start,R',
}

def buttons_xml(setname):
    names = BUTTONS.get(setname, 'Button 1,Button 2,Button 3,Start,Coin')
    dflt  = BUTTON_DEFAULTS.get(setname, 'Y,B,A,Start,R')
    return f'  <buttons names="{names}" default="{dflt}"/>'

# The blocks tools/gen_hiscore_mra.py and tools/gen_cheats_mra.py add, which
# this generator must preserve rather than overwrite. Matched on the comment
# each writes, through to the end of its element.
CARRY_RE = re.compile(
    r'\n  <!-- (?:High scores|Cheats).*?</rom>\n(?:  <nvram index="4"[^/]*/>\n)?',
    re.S)


def carry_over(path):
    """The hiscore/cheat sections of an existing .mra, verbatim, or ''."""
    if not os.path.exists(path):
        return ''
    try:
        old = open(path, encoding='utf-8').read()
    except OSError:
        return ''
    return ''.join(CARRY_RE.findall(old))

def alt_dir_name(desc):
    """The `_alternatives/_<Parent>` directory name for a parent's description.

    The PARENTHETICAL IS DROPPED, so `_alternatives/_E.D.F.- Earth Defense
    Force` holds every E.D.F. clone rather than the folder being named after
    one particular set. The directory groups a family; carrying "(set 1)" or
    "(World)" into its name says the group belongs to that one member, which
    reads wrong the moment you open it and find the others.

    This is the convention the sibling cores already use -- NMK16 files
    `Air Attack (set 1).mra` under `_Air Attack`, and
    `Guardian Storm (horizontal, not encrypted).mra` under `_Guardian Storm`.
    This generator was the odd one out until it was fixed.

    The .mra FILE names keep their parentheses: those name one set each and
    have to stay distinct.
    """
    return fat_safe(desc.split(' (', 1)[0].rstrip())

# ---------------------------------------------------------------- check
def build_stream(setname, byname, bycrc, strict_names):
    """The index-0 byte stream exactly as the core will receive it."""
    e = ROMDATA[setname]
    lay, total = layout(e['mode'])
    buf = bytearray()
    problems = []
    for rn, size, base in lay:
        assert len(buf) == base, f'{setname}/{rn}: stream at 0x{len(buf):X}, base 0x{base:X}'
        reg = next((r for r in e['regions'] if r['name'] == rn), None)
        if reg is None:
            buf += b'\0' * size
            continue
        start = len(buf)
        avail = usable_parts(reg)
        pairs = [p for p in avail if p['form'] == 'LOAD16_BYTE']
        singles = [p for p in avail if p['form'] != 'LOAD16_BYTE']
        def fetch(p):
            key = p['name'].lower()
            if key in byname:
                return byname[key][2]
            if not strict_names and p['crc'] in bycrc:
                return bycrc[p['crc']][2]
            problems.append((rn, p['name'], p['crc']))
            return b'\0' * p['length']
        by_off = {}
        for p in pairs:
            by_off.setdefault(p['offset'] & ~1, {})[p['offset'] & 1] = p
        for off in sorted(by_off):
            pr = by_off[off]
            if 0 in pr and 1 in pr:
                hi, lo = fetch(pr[0]), fetch(pr[1])
                inter = bytearray()
                for i in range(min(len(hi), len(lo))):
                    # MEASURED on hardware 2026-09-22, not inferred: the
                    # map="01" part supplies the EVEN byte of the output word.
                    # The board's golden-byte audit read the sound region's
                    # word 0 back as 0x0F00 where the core needs 0x000F -- a
                    # clean byte swap -- with the map="01" part being the
                    # offset-1 chip at the time.
                    #
                    # An earlier reading of Sand Scorpion's .mra suggested the
                    # opposite. That core stores its 68000 image with its own
                    # convention, so its map attributes say nothing about this
                    # one; the audit does.
                    #
                    # parts_xml below therefore puts the OFFSET-0 chip (the
                    # 68000's high byte) on map="01", so `hi` IS the even byte.
                    inter += bytes((hi[i], lo[i]))
                buf += inter
            else:
                buf += fetch(pr.get(0) or pr.get(1))
        for p in sorted(singles, key=lambda q: q['offset']):
            buf += fetch(p)
        used = len(buf) - start
        if used < size:
            buf += b'\0' * (size - used)
    assert len(buf) == total
    return bytes(buf), problems

def cmd_check(strict_names):
    print(f'{"set":12} {"mode":4} {"stream":>9}  parts  status')
    ok = True
    for setname in sorted(ROMDATA):
        if setname in EXCLUDED:
            print(f'{setname:12} --   {"":>9}  ----   EXCLUDED: {EXCLUDED[setname]}')
            continue
        byname, bycrc = zip_index(setname)
        if not byname:
            print(f'{setname:12} {ROMDATA[setname]["mode"]:4} {"":>9}  ----   NO ZIP')
            ok = False
            continue
        stream, problems = build_stream(setname, byname, bycrc, strict_names)
        n = sum(len(r['parts']) for r in ROMDATA[setname]['regions'] if r['name'] != 'proms')
        status = 'OK' if not problems else f'{len(problems)} part(s) unresolved'
        if problems:
            ok = False
        print(f'{setname:12} {ROMDATA[setname]["mode"]:4} 0x{len(stream):07X} {n:5}   {status}')
        for rn, nm, crc in problems:
            print(f'{"":12} {"":4} {"":9}         {rn}/{nm} crc {crc}')
    return ok

def cmd_layout():
    for mode in 'BCD':
        lay, total = layout(mode)
        sets = mode_sets(mode)
        print(f'mode {mode}: {len(sets)} sets, image 0x{total:06X} ({total/1024/1024:.2f} MB)')
        for rn, size, base in lay:
            print(f'    localparam [23:0] BASE_{mode}_{rn.upper():9} = 24\'h{base:06X};   // 0x{size:06X}')
        print()

# A MiSTer SD card is FAT32 or exFAT, and these characters cannot appear in a
# name on either. The .mra's own <name> element keeps the real description --
# this is only what the FILE is called.
#
# Two of these sets need it: "64th. Street: A Detective Story" and "E.D.F.:
# Earth Defense Force". Without it, tar on the board fails with "Cannot mkdir:
# Invalid argument" partway through unpacking and leaves the release tree half
# installed (found on hardware 2026-09-22, MS1-46).
#
# The colon becomes "-" rather than " -", which is what the arcade collection
# already on the test board does: MAME's "Puzzle & Action: Sando-R" is stored
# there as "Puzzle & Action- Sando-R".
FAT_FORBIDDEN = {':': '-', '/': '-', '\\': '-', '?': '', '*': '',
                 '<': '', '>': '', '|': '-', '"': "'"}

def fat_safe(desc):
    out = ''.join(FAT_FORBIDDEN.get(c, c) for c in desc)
    # FAT also refuses a trailing dot or space.
    return out.rstrip('. ')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--layout', action='store_true')
    ap.add_argument('--ioctl', metavar='SET')
    ap.add_argument('--strict-names', action='store_true',
                    help='resolve parts by file name only (what a real .mra does); '
                         'without it, fall back to CRC so older romsets still simulate')
    a = ap.parse_args()
    if a.layout:
        cmd_layout(); return
    if a.check:
        sys.exit(0 if cmd_check(a.strict_names) else 1)
    if a.ioctl:
        byname, bycrc = zip_index(a.ioctl)
        stream, problems = build_stream(a.ioctl, byname, bycrc, a.strict_names)
        out = os.path.join(ROOT, 'sim', 'rtl', 'ms1bcd', 'roms', a.ioctl + '_ioctl.bin')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, 'wb').write(stream)
        print(f'wrote {out}: 0x{len(stream):X} bytes, {len(problems)} unresolved')
        return
    os.makedirs(RELEASES, exist_ok=True)
    alt = os.path.join(RELEASES, '_alternatives')
    for setname in sorted(ROMDATA):
        if setname in EXCLUDED:
            continue
        e = ROMDATA[setname]
        fn = fat_safe(e['desc']) + '.mra'
        if e['parent']:
            parent_desc = ROMDATA[e['parent']]['desc']
            d = os.path.join(alt, '_' + alt_dir_name(parent_desc))
        else:
            d = RELEASES
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, fn)
        # CARRY OVER THE BLOCKS THIS GENERATOR DOES NOT OWN. The high-score
        # (index 3 + nvram 4) and cheat (index 5) sections are added by
        # tools/gen_hiscore_mra.py and tools/gen_cheats_mra.py as a post-pass,
        # from data this table knows nothing about. Rewriting the file from
        # scratch silently deletes them, and the .mra still looks perfectly
        # well-formed afterwards -- NMK16 lost 616 lines across 27 files that
        # way. Both post-passes skip a file that already has their block, so
        # re-running them is not enough to put these back. MS1-39.
        keep = carry_over(path)
        open(path, 'w', encoding='utf-8').write(
            mra(setname).replace('</misterromdescription>',
                                 keep + '</misterromdescription>'))
        print('wrote', os.path.relpath(path, ROOT),
              '(+ carried hiscore/cheat blocks)' if keep else '')

if __name__ == '__main__':
    main()
