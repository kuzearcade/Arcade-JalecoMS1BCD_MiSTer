#!/usr/bin/env python3
"""Compare an RTL main-CPU bus trace with MAME's, resynchronising over
interrupt insertions.

    bus_compare.py <mame bus.log> <rtl dump> [max]

A raw prefix comparison stops at the first access where the two disagree, and
for two different 68000 timing models that is always an interrupt landing one
instruction apart -- after which every later access is "wrong" even though
nothing is. This tool instead tries to REALIGN after a mismatch by skipping a
short run on either side, and reports:

  * the exact prefix match (what a naive comparison would report)
  * how many realignments were needed, and how big each skip was
  * the total accesses that agree once realigned

An interrupt taken early shows up as a small skip on the RTL side (the stack
frame and vector fetch) and the traces agreeing again immediately afterwards.
A real decode or CPU bug does not realign at all.
"""
import sys

def load_mame(p, limit):
    out = []
    for ln in open(p):
        q = ln.split()
        if len(q) != 6:
            continue
        out.append((q[0], int(q[3], 16), int(q[4], 16), int(q[5], 16)))
        if len(out) >= limit:
            break
    return out

def load_rtl(p, limit):
    out = []
    for ln in open(p):
        q = ln.split()
        if len(q) != 4:
            continue
        out.append((q[0], int(q[2], 16), int(q[3], 16), 0xFFFF))
        if len(out) >= limit:
            break
    return out

def same(a, b):
    if a[0] != b[0] or a[1] != b[1]:
        return False
    if b[3] == 0xFFFF and a[2] != b[2]:      # compare data on word accesses
        return False
    return True

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 2000000
    mame = load_mame(sys.argv[1], limit)
    rtl  = load_rtl(sys.argv[2], limit)
    n = min(len(mame), len(rtl))

    i = j = 0
    first_bad = None
    agree = 0
    resyncs = []
    MAXSKIP = 24
    while i < len(rtl) and j < len(mame):
        if same(rtl[i], mame[j]):
            agree += 1; i += 1; j += 1; continue
        if first_bad is None:
            first_bad = agree
        # try to realign: skip up to MAXSKIP on one side, then the other
        best = None
        for s in range(1, MAXSKIP):
            if i + s < len(rtl) and same(rtl[i + s], mame[j]):
                best = ('rtl', s); break
            if j + s < len(mame) and same(rtl[i], mame[j + s]):
                best = ('mame', s); break
        if best is None:
            break
        resyncs.append((agree, best[0], best[1]))
        if best[0] == 'rtl': i += best[1]
        else:                j += best[1]

    print(f'reference {len(mame)} accesses, rtl {len(rtl)}, compared window {n}')
    print(f'exact prefix match      : {first_bad if first_bad is not None else agree}')
    print(f'accesses agreeing total : {agree}')
    print(f'realignments needed     : {len(resyncs)}')
    if resyncs:
        from collections import Counter
        c = Counter((w, s) for _, w, s in resyncs)
        print('  skip histogram (side, length) -> count:')
        for k, v in sorted(c.items(), key=lambda t: -t[1])[:8]:
            print(f'    {k[0]:4} +{k[1]:2}  x{v}')
        print(f'  first at access {resyncs[0][0]}, last at {resyncs[-1][0]}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
