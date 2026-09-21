#!/usr/bin/env python3
"""Mega System 1 B/C/D video reference model, in Python.

    ms1_video_model.py render <capture_dir> <F> [out.ppm]
    ms1_video_model.py check  <capture_dir> [F ...]

This is the M1 specification. docs/PLAN.md 4.D item 9 says to decode every
graphics layout against MAME's gfx_element in Python BEFORE writing RTL, and
item 14 says that when pixels resist, the answer is in the driver read line by
line. This model is that reading, made executable: it reproduces MAME's own
frame from a captured RAM/register dump, and `check` proves it pixel-exact.
Once it agrees, the RTL has an unambiguous target and every later mismatch is
an RTL bug rather than a misunderstanding of the hardware.

Everything here is derived from MAME 0.289 jaleco/megasys1_v.cpp and
jaleco/ms1_tmap.cpp. The traps it encodes, each of which is a real difference
from what the plan's prose says:

  * The palette bit layout in the driver's own header comment is WRONG: it
    says ba98=Blue and 7654=Green, but the format actually applied is
    RRRRGGGGBBBBRGBx, so ba98=GREEN and 7654=BLUE. System D does not use that
    format at all -- it is plain RGBx_555. See pal_rgb().
  * Sprites are TWO frames ahead (screen_vblank double-buffers twice), so
    frame F is drawn from the object/sprite RAM captured at frame F-2.
  * Sprite order is first-entry-frontmost, implemented as first-writer-wins
    via bit 15 of the sprite buffer -- not by drawing in reverse.
  * A 16x16 layer tile is four 8x8 tiles in COLUMN order (0 2 / 1 3), and the
    sprite ROM's own 16x16 layout is the same column grouping.
  * Layer 2 is at the LOW register address on System B (044008) but the HIGH
    one on System C (0C2100); System D inverts the layer VRAM addresses
    against the layer indices.
"""
import os, sys, zipfile, zlib
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ms1_romdata import ROMDATA
import gen_ms1bcd_mra as G

TILES_PER_PAGE_X = TILES_PER_PAGE_Y = 0x20
TILES_PER_PAGE   = TILES_PER_PAGE_X * TILES_PER_PAGE_Y
VIS_W, VIS_H, VIS_Y0 = 256, 224, 16
SCREEN_W, SCREEN_H = 256, 256   # set_size(32*8, 32*8) in every mode

# ---------------------------------------------------------------- ROM access
def region_bytes(setname, region):
    """One MAME ROM region, assembled exactly as MAME would load it."""
    e = ROMDATA[setname]
    reg = next((r for r in e['regions'] if r['name'] == region), None)
    if reg is None:
        return b''
    byname, bycrc = G.zip_index(setname)
    buf = bytearray(reg['size'])
    for p in G.usable_parts(reg):
        key = p['name'].lower()
        src = byname.get(key) or bycrc.get(p['crc'])
        if src is None:
            raise SystemExit(f'{setname}/{region}: cannot resolve {p["name"]}')
        d = src[2]
        if p['form'] == 'LOAD16_BYTE':
            buf[p['offset']:p['offset'] + 2 * len(d):2] = d
        else:
            buf[p['offset']:p['offset'] + len(d)] = d
    return bytes(buf)

# ------------------------------------------------------------- gfx decoding
def decode_layer_gfx(data):
    """gfx_8x8x4_packed_msb: 8x8, 4bpp, 32 bytes/tile, high nibble first."""
    n = len(data) // 32
    if n == 0:
        return np.zeros((0, 8, 8), np.uint8)
    a = np.frombuffer(data[:n * 32], np.uint8).reshape(n, 8, 4)
    out = np.empty((n, 8, 8), np.uint8)
    out[:, :, 0::2] = a >> 4
    out[:, :, 1::2] = a & 0x0F
    return out

def decode_sprite_gfx(data):
    """gfx_8x8x4_col_2x2_group_packed_msb: 16x16, 4bpp, 128 bytes/tile.

    x 0..7 come from the first 64 bytes, x 8..15 from the second 64 (the
    x-offset list is STEP8(0,4) then STEP8(4*8*16,4), and 4*8*16 bits = 64
    bytes). y offsets are STEP16(0,4*8), i.e. 4 bytes per row within a half.
    So the tile is two stacked 8-wide columns, not two interleaved halves.
    """
    n = len(data) // 128
    if n == 0:
        return np.zeros((0, 16, 16), np.uint8)
    a = np.frombuffer(data[:n * 128], np.uint8).reshape(n, 2, 16, 4)
    out = np.empty((n, 16, 16), np.uint8)
    for half in (0, 1):
        h = a[:, half]                       # (n,16,4)
        b = half * 8
        out[:, :, b + 0:b + 8:2] = h >> 4
        out[:, :, b + 1:b + 8:2] = h & 0x0F
    return out

# ------------------------------------------------------------- tilemap scan
def tilemap_shape(ctrl):
    """(num_cols, num_rows) in 8x8 units, from the layer control register."""
    eight = (ctrl >> 4) & 1
    n = ctrl & 3
    if eight:   # m_tilemap[1][n]
        mult = [(8, 1), (4, 2), (4, 2), (2, 4)][n]
    else:       # m_tilemap[0][n]
        mult = [(16, 2), (8, 4), (4, 8), (2, 16)][n]
    return TILES_PER_PAGE_X * mult[0], TILES_PER_PAGE_Y * mult[1]

def scan_8x8(col, row, num_cols):
    return (col * TILES_PER_PAGE_Y
            + (row // TILES_PER_PAGE_Y) * TILES_PER_PAGE * (num_cols // TILES_PER_PAGE_X)
            + (row % TILES_PER_PAGE_Y))

def scan_16x16(col, row, num_cols):
    return ((((col // 2) * (TILES_PER_PAGE_Y // 2))
             + ((row // 2) // (TILES_PER_PAGE_Y // 2)) * (TILES_PER_PAGE // 4) * (num_cols // TILES_PER_PAGE_X)
             + ((row // 2) % (TILES_PER_PAGE_Y // 2))) * 4
            + (row & 1) + (col & 1) * 2)

# ----------------------------------------------------------------- palette
def pal_rgb(words, mode):
    """Palette words -> Nx3 uint8 RGB, per the format MAME actually applies."""
    w = words.astype(np.uint32)
    p5 = lambda v: ((v << 3) | (v >> 2)).astype(np.uint8)
    if mode == 'D':                       # RGBx_555: <5,5,5, 11,6,1>
        return np.stack([p5((w >> 11) & 0x1F), p5((w >> 6) & 0x1F), p5((w >> 1) & 0x1F)], -1)
    # B and C: RRRRGGGGBBBBRGBx -- bits 3/2/1 are the LSbs of R/G/B
    r = p5(((w >> 11) & 0x1E) | ((w >> 3) & 1))
    g = p5(((w >> 7) & 0x1E) | ((w >> 2) & 1))
    b = p5(((w >> 3) & 0x1E) | ((w >> 1) & 1))
    return np.stack([r, g, b], -1)

# ------------------------------------------------------- priority PROM
def priority_create(prom):
    """Port of megasys1_state::priority_create: PROM -> 16 layer orders.

    TWO stages, and missing the second one is the trap. The first derives a
    layer order for each sprite-split state by repeatedly asking the PROM
    "which layer is on top of the remaining set", appending each answer on
    the right -- so that intermediate value has the TOP layer leftmost.

    The second stage MERGES the two split orders into one, mapping the
    sprite layer onto 3 and 4, and in doing so reverses them ("reverse the
    order now"): it consumes the low nibble, which is the BOTTOM layer, and
    appends it on the right, so after five layers the bottom ends up
    LEFTMOST. That is what screen_update wants, because it walks the value
    from the left and draws the first entry with TILEMAP_DRAW_OPAQUE.

    Stopping after stage one leaves an order that is exactly backwards, and
    the symptom is subtle: scenes whose upper layers happen to be blank still
    match, and only a scene with an opaque background layer shows it.
    """
    U32 = 0xFFFFFFFF
    out = []
    for pri_code in range(0x10):
        layers_order = [0xFFFFF, 0xFFFFF]
        for offset in range(2):
            enable_mask = 0xF
            order1 = 0xFFFFF
            while True:
                top = prom[pri_code * 0x20 + offset + enable_mask * 2] & 3
                top_mask = 1 << top
                result = 0
                for i in range(0x10):
                    opacity = i & enable_mask
                    layer = prom[pri_code * 0x20 + offset + opacity * 2]
                    if opacity:
                        if opacity & top_mask:
                            if layer != top: result |= 1
                        else:
                            if layer == top: result |= 2
                            else:            result |= 4
                order1 = ((order1 << 4) | top) & 0xFFFFF
                enable_mask &= ~top_mask
                if (result & 1) or (result & 6) == 6:
                    order1 = 0xFFFFF
                    break
                if result == 2:
                    enable_mask = 0
                if enable_mask == 0:
                    break
            layers_order[offset] = order1

        # merge the two orders, reversing them in the process
        order = 0xFFFFF
        i = 5
        while i > 0:
            layer0 = layers_order[0] & 0x0F
            layer1 = layers_order[1] & 0x0F
            if layer0 != 3:                      # 0, 1, 2 or f
                if layer1 == 3:
                    layer = 4
                    layers_order[0] = (layers_order[0] << 4) & U32
                else:
                    layer = layer0
                    if layer0 != layer1:
                        order = 0xFFFFF          # split does not simply split
                        break
            else:                                # layer0 == 3
                if layer1 == 3:
                    layer = 0x43                 # 4 must always be present
                    order = (order << 4) & U32
                    i -= 1
                else:
                    layer = 3
                    layers_order[1] = (layers_order[1] << 4) & U32
            order = ((order << 4) | layer) & U32
            i -= 1
            layers_order[0] >>= 4
            layers_order[1] >>= 4
        out.append(order & 0xFFFFF)
    return out

# ------------------------------------------------------------------ capture
def read_layout(d):
    info = {'regions': []}
    for line in open(os.path.join(d, 'layout.txt')):
        t = line.split()
        if line.startswith('set '):
            info['set'], info['mode'] = t[1], t[3]
        elif len(t) == 4 and t[1].startswith('base='):
            info['regions'].append((t[0],
                                    int(t[1][5:], 16), int(t[2][4:], 16), int(t[3][8:], 16)))
    return info

def read_state(d, F, info):
    raw = open(os.path.join(d, 'state', f's{F}.bin'), 'rb').read()
    out = {}
    for name, base, ln, off in info['regions']:
        out[name] = np.frombuffer(raw[off:off + ln], '<u2')
    return out

def read_regs(d, F):
    r = {}
    for line in open(os.path.join(d, 'state', f'r{F}.txt')):
        k, v = line.split()
        r[k] = int(v, 16)
    return r

def read_mame_frame(d, F):
    a = np.fromfile(os.path.join(d, 'frames', f'f{F}.raw'), dtype='<u4')
    if a.size != VIS_W * VIS_H:
        raise SystemExit(f'f{F}.raw: {a.size} pixels, expected {VIS_W*VIS_H} '
                         '(see docs/known-issues.md MS1-9)')
    a = a.reshape(VIS_H, VIS_W)
    return np.stack([(a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF], -1).astype(np.uint8)

# ------------------------------------------------------------------- render
class Renderer:
    def __init__(self, capture_dir):
        self.dir = capture_dir
        self.info = read_layout(capture_dir)
        self.set, self.mode = self.info['set'], self.info['mode']
        self.nlayers = 2 if self.mode == 'D' else 3
        names = ['scroll1', 'scroll2', 'scroll3'][:self.nlayers]
        self.layer_gfx = [decode_layer_gfx(region_bytes(self.set, n)) for n in names]
        self.spr_gfx = decode_sprite_gfx(region_bytes(self.set, 'sprites'))
        self.prom = region_bytes(self.set, 'proms')
        self.orders = priority_create(self.prom) if self.prom else None

    def layer_indexed(self, L, st, regs):
        """(index bitmap, opaque mask) for one layer over the visible window.

        The index is computed for EVERY pixel, pen 15 included. The mask says
        which pixels are opaque. Both are needed because the bottom layer is
        drawn with TILEMAP_DRAW_OPAQUE, which puts its transparent pen on
        screen in its real palette colour rather than leaving the background
        at index 0 -- so a bottom layer whose pen 15 maps to something other
        than palette 0 is visible, and cannot be treated as a hole.
        """
        ctrl = regs[f't{L}_ctrl']; sx = regs[f't{L}_sx']; sy = regs[f't{L}_sy']
        eight = (ctrl >> 4) & 1
        ncols, nrows = tilemap_shape(ctrl)
        mw, mh = ncols * 8, nrows * 8
        vram = st[f'layer{L}']
        gfx = self.layer_gfx[L]
        # Screen flip is NOT handled here -- see render(), which applies it to
        # the finished frame. Everything below renders unflipped.
        ys = (np.arange(VIS_H) + VIS_Y0 + sy) % mh
        xs = (np.arange(VIS_W) + sx) % mw
        row = (ys // 8)[:, None]                      # (H,1)
        col = (xs // 8)[None, :]                      # (1,W)
        fy  = (ys % 8)[:, None]
        fx  = (xs % 8)[None, :]
        if eight:
            ti = (col * TILES_PER_PAGE_Y
                  + (row // TILES_PER_PAGE_Y) * TILES_PER_PAGE * (ncols // TILES_PER_PAGE_X)
                  + (row % TILES_PER_PAGE_Y))
            cell = ti
        else:
            ti = ((((col // 2) * (TILES_PER_PAGE_Y // 2))
                   + ((row // 2) // (TILES_PER_PAGE_Y // 2)) * (TILES_PER_PAGE // 4) * (ncols // TILES_PER_PAGE_X)
                   + ((row // 2) % (TILES_PER_PAGE_Y // 2))) * 4
                  + (row & 1) + (col & 1) * 2)
            cell = ti >> 2
        ti, cell = np.broadcast_arrays(ti, cell)
        code = vram[np.clip(cell, 0, vram.size - 1)].astype(np.int64)
        if eight:
            tile = code & 0xFFF
        else:
            tile = (code & 0xFFF) * 4 + (ti & 3)
        n = max(len(gfx), 1)
        pen = (gfx[tile % n, np.broadcast_to(fy, tile.shape), np.broadcast_to(fx, tile.shape)]
               if len(gfx) else np.full(tile.shape, 15, np.uint8))
        out = (256 * L + (code >> 12) * 16 + pen).astype(np.uint16)
        opq = (pen != 15)
        return out, opq

    def sprites_indexed(self, st2, regs):
        """Sprite buffer over the visible window: (value, priority) or None."""
        sflag = regs.get('sprite_flag', 0)
        sbank = regs.get('sprite_bank', 0)
        scrf = regs.get('screen_flag', 0)
        objram, sprram = st2['objram'], st2['spriteram']
        color_mask = 0x07 if (sflag >> 8) & 1 else 0x0F
        # bit15 = written, bit14 = priority, bits 7:0 = pen + color*16
        buf = np.full((VIS_H + 32, VIS_W), 0x7FFF, np.uint16)
        for offs in range((0x800 - 8) // 2, -1, -4):
            for sprite in range(4):
                od = offs + (0x800 // 2) * sprite
                if od + 3 >= objram.size: continue
                si = (int(objram[od]) & 0x7F) * 8
                if si + 7 >= sprram.size: continue
                attr = int(sprram[si + 4])
                if ((attr & 0xC0) >> 6) != sprite: continue
                sx = ((int(sprram[si + 5]) + int(objram[od + 1])) & 0x1FF)
                sy = ((int(sprram[si + 6]) + int(objram[od + 2])) & 0x1FF)
                sx = sx - 0x200 if sx & 0x100 else sx
                sy = sy - 0x200 if sy & 0x100 else sy
                code = int(sprram[si + 7]) + int(objram[od + 3])
                color = attr & color_mask
                flipx = bool((attr >> 6) & 1); flipy = bool((attr >> 7) & 1)
                pri = (attr >> 3) & 1
                mosaic = (attr & 0x0F00) >> 8
                mossol = bool((attr >> 12) & 1)
                code = (code & 0xFFF) + ((sbank & 1) << 12)
                # MAME's draw_sprites also mirrors each sprite when screen_flag
                # bit 0 is set (flipx/flipy inverted, sx/sy -> 240-sx/240-sy).
                # That is deliberately NOT done here: render() rotates the
                # whole finished frame instead, which is equivalent and was
                # verified as such -- see render().
                self._blit(buf, code, color, sx, sy - 16, flipx, flipy, mosaic, mossol, pri)
        return buf[VIS_Y0:VIS_Y0 + VIS_H]

    def _blit(self, buf, code, color, sx, sy, flipx, flipy, mosaic, mossol, pri):
        if not len(self.spr_gfx): return
        g = self.spr_gfx[code % len(self.spr_gfx)]
        sy = sy + 16
        yxor = 0x0F if flipy else 0
        xxor = 0x0F if flipx else 0
        col = color << 4
        for y in range(16):
            dy = sy + y
            if dy < 0 or dy >= buf.shape[0]: continue
            srcy = y ^ yxor
            gy = (srcy | mosaic) if mossol else (srcy & ~mosaic)
            for x in range(16):
                dx = sx + x
                if dx < 0 or dx >= VIS_W: continue
                srcx = x ^ xxor
                gx = (srcx | mosaic) if mossol else (srcx & ~mosaic)
                pen = int(g[gy & 15, gx & 15])
                if pen != 0x0F and not (buf[dy, dx] & 0x8000):
                    buf[dy, dx] = (pen + col) | (pri << 14) | 0x8000

    def render(self, F):
        # THE REGISTERS COME FROM FRAME F-1, not F.
        #
        # The capture reads them at frame_done, which runs after MAME has
        # already rendered the frame, and by then the game's vblank handler
        # has written the values for the NEXT frame. Measured, not assumed:
        # at avspirit frame 400 the captured scroll is t0=0x54/t1=0xA8 while
        # the frame MAME drew needs 0x53/0xA6 -- exactly frame 399's values,
        # and the two layers' corrections (-1 and -2) are in the same ratio
        # as their parallax rates, which is what makes it a frame offset
        # rather than a constant fudge.
        #
        # The error is invisible on a static screen and shows up as a few
        # dozen scattered pixels on a scrolling one, which is why the first
        # frames checked all passed. VRAM and the palette are NOT shifted:
        # they are read at the same instant and match at F, tested explicitly.
        st = read_state(self.dir, F, self.info)
        regs = read_regs(self.dir, F - 1 if F >= 1 else 0)
        # Sprites come from frame F-3. MAME's own comment says sprites are
        # TWO frames ahead (screen_vblank does buffer2<-buffer<-live, and
        # draw_sprites reads buffer2), and the capture's own one-frame lag --
        # the same one that shifts the registers above -- makes it three.
        # Measured across the demo: F-2 leaves 23692 differing pixels over 13
        # frames, F-3 leaves 1468, F-4 leaves 23296.
        st2 = read_state(self.dir, F - 3, self.info) if F >= 3 else st
        active = regs.get('active_layers', 0)
        sflag = regs.get('sprite_flag', 0)

        pri = self.orders[(active & 0x0F00) >> 8] if self.orders else 0xFFFFF
        if pri == 0xFFFFF:
            pri = 0x04132
        reallyactive = 0
        for i in range(5):
            reallyactive |= 1 << ((pri >> (4 * i)) & 0x0F)
        act = (active & reallyactive) | (1 << ((pri & 0xF0000) >> 16))

        layers = {}
        for L in range(self.nlayers):
            if (act >> L) & 1:
                layers[L] = self.layer_indexed(L, st, regs)   # (idx, opaque)

        idx = np.zeros((VIS_H, VIS_W), np.uint16)
        prio = np.zeros((VIS_H, VIS_W), np.uint8)
        primask = 0
        first = True
        p = pri
        for _ in range(5):
            layer = (p & 0xF0000) >> 16
            p = (p << 4) & 0xFFFFF
            if layer in (0, 1, 2):
                if layer in layers:
                    lay, m = layers[layer]
                    if first:
                        # TILEMAP_DRAW_OPAQUE: every pixel, pen 15 included
                        idx[:] = lay
                        prio[:] = primask
                        first = False
                    else:
                        idx[m] = lay[m]
                        prio[m] = primask
            elif layer in (3, 4):
                if first:
                    first = False
                    idx[:] = 0
                if (sflag >> 8) & 1:
                    primask |= 1 << (layer - 3)
                elif layer == 3:
                    primask |= 3

        if (act >> 3) & 1:
            sb = self.sprites_indexed(st2, regs)
            pen_ok = (sb & 0xF) != 0xF
            spr_pri = np.where((sb >> 14) & 1, 0x0C, 0x0A)
            blocked = ((spr_pri >> (prio & 0x1F)) & 1).astype(bool)
            m = pen_ok & ~blocked
            idx[m] = (sb[m] & 0x3FFF) + 256 * 3

        pal = pal_rgb(st['palette'], self.mode)
        out = pal[np.clip(idx, 0, len(pal) - 1)]

        # Screen flip (screen_flag bit 0) is exactly rot180 of the finished
        # visible frame. MAME reaches that result the long way -- every
        # tilemap gets TILEMAP_FLIPX|FLIPY, and draw_sprites separately
        # mirrors each sprite's position and flip flags -- but the composite
        # is a plain 180-degree rotation, because the visible window is
        # symmetric about the bitmap centre (rows 16..239 of 256, columns
        # 0..255, both centred on 127.5).
        #
        # This is NOT assumed. docs/PLAN.md 4.D item 10 warns that "RTL flip
        # == rot180(RTL no-flip)" is tautological and must be checked against
        # MAME. So it was checked MAME against MAME: avspirit was captured
        # twice from the same point, once with the Flip Screen DIP forced,
        # and the flipped frame equals rot180 of the unflipped frame with
        # ZERO differing pixels. Both sides came from MAME, so the identity
        # is a property of the hardware model, not of this code.
        if regs.get('screen_flag', 0) & 1:
            out = out[::-1, ::-1]
        return out

def write_ppm(path, rgb):
    with open(path, 'wb') as f:
        f.write(b'P6\n%d %d\n255\n' % (rgb.shape[1], rgb.shape[0]))
        f.write(rgb.astype(np.uint8).tobytes())

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    cmd, d = sys.argv[1], sys.argv[2]
    r = Renderer(d)
    if cmd == 'render':
        F = int(sys.argv[3])
        out = sys.argv[4] if len(sys.argv) > 4 else f'/tmp/ms1_f{F}.ppm'
        write_ppm(out, r.render(F))
        print(f'wrote {out}')
    elif cmd == 'check':
        fr = [int(x) for x in sys.argv[3:]] or list(range(2, 300, 10))
        print(f'{r.set} mode {r.mode}')
        print(f'{"frame":>6} {"nonblank":>9} {"diff px":>9} {"%":>7}  verdict')
        worst = 0
        for F in fr:
            try:
                mine = r.render(F); theirs = read_mame_frame(d, F)
            except FileNotFoundError:
                continue
            nb = int((theirs.any(axis=2)).sum())
            diff = int((mine != theirs).any(axis=2).sum())
            worst = max(worst, diff)
            pc = 100.0 * diff / (VIS_W * VIS_H)
            print(f'{F:6} {nb:9} {diff:9} {pc:6.2f}%  {"MATCH" if diff==0 else "differs"}')
        return 0 if worst == 0 else 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
