#!/usr/bin/env python3
"""Compare the RTL's protection conversation with MAME's, command by command.

    prot_compare.py <rtl protlog> <mame prot.log> [max]

M2 gate (5) asks for "the protection handshake verified command by command
against MAME's MCU trace, not merely 'the game boots'". Both files are the
68000's side of that conversation: one line per access to the protection port,
`w <data>` for a command and `r <data>` for the MCU's answer.

The comparison is not a plain prefix diff. The game POLLS: it writes a command
and then reads the port repeatedly until the answer it wants appears, so a
sim whose MCU answers a fraction of a frame later than MAME's produces extra
`r` lines with the previous (stale) value and is not wrong. This aligns the
two by their COMMANDS -- the `w` lines, which are what the game decided to ask
-- and then checks that each command's eventual ANSWER matches.

Reported:
  * commands compared, and how many had a matching answer
  * any command whose answer differs, which is a real protection failure
  * how many extra polls each side needed, as a latency measure
"""
import sys

def load(p):
    out = []
    for ln in open(p):
        q = ln.split()
        if len(q) < 2:
            continue
        kind = q[0]
        val = int(q[-1], 16) & 0xFF
        if kind in ('r', 'w'):
            out.append((kind, val))
    return out

def transactions(seq):
    """[(command, [answers...]), ...] -- answers are every read before the next write."""
    out = []
    cur = None
    for kind, val in seq:
        if kind == 'w':
            if cur is not None:
                out.append(cur)
            cur = (val, [])
        elif cur is not None:
            cur[1].append(val)
    if cur is not None:
        out.append(cur)
    return out

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    a = transactions(load(sys.argv[1]))
    b = transactions(load(sys.argv[2]))
    n = min(len(a), len(b))
    if len(sys.argv) > 3:
        n = min(n, int(sys.argv[3]))

    cmd_ok = ans_ok = 0
    bad = []
    extra_rtl = extra_mame = 0
    for i in range(n):
        (ca, aa), (cb, ab) = a[i], b[i]
        if ca != cb:
            bad.append((i, 'command', ca, cb))
            break
        cmd_ok += 1
        # the answer that matters is the last one the game read before moving on
        la = aa[-1] if aa else None
        lb = ab[-1] if ab else None
        if la == lb:
            ans_ok += 1
        else:
            bad.append((i, f'answer to {ca:02X}', la, lb))
        extra_rtl += max(0, len(aa) - 1)
        extra_mame += max(0, len(ab) - 1)

    print(f'transactions compared      : {n}   (rtl has {len(a)}, mame {len(b)})')
    print(f'commands matching          : {cmd_ok}/{n}')
    print(f'answers matching           : {ans_ok}/{cmd_ok}')
    print(f'extra polls (rtl / mame)   : {extra_rtl} / {extra_mame}')
    if bad:
        print(f'first {min(5,len(bad))} mismatches:')
        for i, what, x, y in bad[:5]:
            xs = 'none' if x is None else f'{x:02X}'
            ys = 'none' if y is None else f'{y:02X}'
            print(f'   transaction {i}: {what}  rtl {xs}  mame {ys}')
    return 0 if (bad == [] ) else 2

if __name__ == '__main__':
    sys.exit(main())
