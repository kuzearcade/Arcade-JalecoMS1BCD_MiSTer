# The protection MCU, verified against MAME

`docs/PLAN.md` step 4: "Re-parameterise `tlcs90.sv` for the TMP91640's
16 KB/512 B and run it standalone against MAME's MCU trace. This is the one
genuinely new CPU integration, it is mostly already done, and **it gates M2**."

This is that. It is **not** M2 gate (5), which asks for the protection
handshake verified command by command and needs the MCU sitting next to the
main 68000; it is the prerequisite that gate depends on.

## Result

`rtl/jaleco/ms1_iomcu.sv` runs the real 16 KB MCU ROM and reproduces MAME's
own MCU bus trace **access for access, identically**, from reset:

| set | mode | MCU clock | cycles/scanline | accesses identical |
|---|---|---:|---:|---:|
| avspirit | B | 8 MHz | 512 | **35805** |
| 64street | C | 12 MHz | 768 | **53785** |

Both at a reset phase of scanline 240 — the start of vblank, which is the
physically sensible moment for a board to leave reset, and which was found by
sweeping rather than assumed.

That span covers the whole of initialisation (identical SFR writes, identical
watchdog-disable sequence), entry into the command loop, and several complete
INT1 service cycles.

## What the residual is

Both traces diverge on the exact access at which an INT1 lands — the RTL takes
it two accesses later than MAME, having executed identically up to that point.

It is not a scanline-length error: 384 pixels at 6 MHz against an 8 MHz MCU is
exactly 512 cycles, and against 12 MHz exactly 768. Both are used above. What
remains is that MAME delivers an interrupt line change on a scheduler boundary
and the driver sets `config.set_maximum_quantum(attotime::from_hz(120000))`,
about 66 MCU cycles of granularity, against a cycle-exact RTL sim.

This residual is a property of the harness's synthetic video timing, and it
disappears in the full sim, where the real raster drives INT1 directly.

## Reproducing

```sh
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy     # MS1-14
MS1_OUT=/tmp/mcu MS1_MACC=120000 ~/mame/mame -noreadconfig avspirit \
  -rompath mame_roms -video none -sound none -nothrottle \
  -autoboot_script sim/oracle/ms1_mcutrace.lua > /tmp/mt.log 2>&1

cd sim/rtl/iomcu && make
MCU_TRACE=900000 MS1_PHASE=122880 ./obj_dir/Vms1_iomcu \
  /tmp/iomcu_avspirit.bin ../../oracle/traces/bus_avspirit/prot.log FF FF FF FC FF
```
