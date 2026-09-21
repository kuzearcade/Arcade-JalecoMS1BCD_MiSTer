#!/usr/bin/env python3
"""Export one captured frame as flat binaries for the video_state harness.

    dump_video_state.py <capture_dir> <F> <out_dir>

The RTL harness needs the same state the Python model uses, but as files it
can read without a zip reader or the MAME ROM table. The frame offsets of
docs/known-issues.md MS1-11 are applied HERE, once, so the harness never has
to know about them:

    VRAM and palette   frame F
    video registers    frame F-1
    object/sprite RAM  frame F-3

Writes: l0.vram l1.vram l2.vram (u16 LE), objram.bin spriteram.bin
palette.bin (u16 LE), prom.bin, gfx0.bin gfx1.bin gfx2.bin sprites.bin,
regs.txt, expected.raw (MAME's own frame, 256x224 xRGB).
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ms1_video_model as M

def main():
    if len(sys.argv) != 4:
        print(__doc__); return 1
    cap, F, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(out, exist_ok=True)
    r = M.Renderer(cap)
    st  = M.read_state(cap, F, r.info)
    regs = M.read_regs(cap, F - 1 if F >= 1 else 0)
    st2 = M.read_state(cap, F - 3, r.info) if F >= 3 else st

    for i in range(3):
        key = f'layer{i}'
        v = st[key] if key in st else np.zeros(8192, '<u2')
        np.asarray(v, '<u2').tofile(os.path.join(out, f'l{i}.vram'))
    np.asarray(st2['objram'],    '<u2').tofile(os.path.join(out, 'objram.bin'))
    np.asarray(st2['spriteram'], '<u2').tofile(os.path.join(out, 'spriteram.bin'))
    np.asarray(st['palette'],    '<u2').tofile(os.path.join(out, 'palette.bin'))

    names = ['scroll1', 'scroll2', 'scroll3']
    for i, n in enumerate(names):
        d = M.region_bytes(r.set, n) if i < r.nlayers else b''
        open(os.path.join(out, f'gfx{i}.bin'), 'wb').write(d)
    open(os.path.join(out, 'sprites.bin'), 'wb').write(M.region_bytes(r.set, 'sprites'))
    open(os.path.join(out, 'prom.bin'), 'wb').write(r.prom)

    mode_id = {'B': 0, 'C': 1, 'D': 2}[r.mode]
    with open(os.path.join(out, 'regs.txt'), 'w') as f:
        f.write(f'set {r.set}\nmode {mode_id}\nnlayers {r.nlayers}\nframe {F}\n')
        for k in ('active_layers', 'sprite_flag', 'sprite_bank', 'screen_flag',
                  't0_sx', 't0_sy', 't0_ctrl', 't1_sx', 't1_sy', 't1_ctrl',
                  't2_sx', 't2_sy', 't2_ctrl'):
            f.write(f'{k} {regs.get(k, 0):04X}\n')

    a = np.fromfile(os.path.join(cap, 'frames', f'f{F}.raw'), dtype='<u4')
    a.tofile(os.path.join(out, 'expected.raw'))
    print(f'{r.set} mode {r.mode} frame {F} -> {out}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
