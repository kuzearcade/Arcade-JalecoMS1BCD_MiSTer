-- Arcade-JalecoMS1BCD_MiSTer — MAME oracle capture for Mega System 1 B/C/D.
--
--   MS1_OUT=<dir> MS1_FRAMES=<n> [MS1_PIX=1] [MS1_STATE=1] \
--     mame <set> -rompath mame_roms -video none -sound none -nothrottle \
--          -autoboot_script sim/oracle/ms1_capture.lua
--
-- Modelled on Arcade-SandScrp_MiSTer's sandscrp_capture.lua, which is the
-- proven shape: everything keyed by the capture's own frame counter F, so a
-- frame's pixels and the state that produced them can never drift apart.
--
-- The one thing that is genuinely new here is that the memory map is
-- MODE-DEPENDENT.  B, C and D put the palette, object RAM and the three (or
-- two) scroll layers at completely different addresses, and System D inverts
-- the layer ORDER against its layer indices (docs/PLAN.md 1.1: m_tmap[0] is
-- at 0E8000 and m_tmap[1] at 0D0000, the opposite of System C).  That single
-- fact is called out in the plan as the likeliest source of a "D mode draws
-- the wrong layer" bug, so the map lives in ONE table here, keyed by mode and
-- written in MAME's m_tmap[] index order, and every consumer reads that table
-- rather than hardcoding an address.
--
-- Outputs:
--   frames/f<F>.raw  pixels of frame F, host-endian xRGB as screen:pixels()
--                    returns them
--   state/s<F>.bin   palette, object RAM and each scroll layer's VRAM, in the
--                    order listed by MAP[mode].regions, each u16 LE, read at
--                    the same instant as frame F
--   layout.txt       the exact region list, sizes and offsets for this set,
--                    so the consumer never has to guess the file's shape
--   index.txt        F -> frame_number, machine time

local out    = os.getenv('MS1_OUT')    or 'sim/oracle/traces/ms1'
local frames = tonumber(os.getenv('MS1_FRAMES') or '120')
local do_pix = os.getenv('MS1_PIX')   == '1'
local do_st  = os.getenv('MS1_STATE') == '1'

-- setname -> mode.  Derived from tools/ms1_romdata.py; kept here as a literal
-- so the Lua side has no dependency on the Python table at capture time.
local MODE = {
  avspirit='B', monkelf='B', edf='B', edfa='B', edfb='B', edfu='B', hayaosi1='B',
  ['64street']='C', ['64streetj']='C', ['64streetja']='C',
  bigstrik='C', chimerab='C', chimeraba='C', cybattlr='C',
  peekaboo='D', peekaboou='D',
}

-- Regions in MAME's m_tmap[] index order.  name, base, length (bytes).
local MAP = {
  B = { palette={0x048000,0x0800}, objram={0x04E000,0x2000},
        layers={ {0x050000,0x4000}, {0x054000,0x4000}, {0x058000,0x4000} },
        vregs ={0x044000,0x0400} },
  C = { palette={0x0F8000,0x0800}, objram={0x0D2000,0x2000},
        layers={ {0x0E0000,0x4000}, {0x0E8000,0x4000}, {0x0F0000,0x4000} },
        vregs ={0x0C2000,0x0400} },
  -- D: note the inversion.  m_tmap[0] is the HIGHER address here.
  D = { palette={0x0D8000,0x0800}, objram={0x0CA000,0x2000},
        layers={ {0x0E8000,0x4000}, {0x0D0000,0x4000} },
        vregs ={0x0C2000,0x0400} },
}

local setname = emu.romname()
local mode = MODE[setname]
if not mode then
  print(('ms1_capture: %s is not a B/C/D set; nothing to capture'):format(setname))
  return
end
local m = MAP[mode]

local cpu   = manager.machine.devices[':maincpu']
local mem   = cpu.spaces['program']
local scr   = manager.machine.screens:at(1)

os.execute(('mkdir -p %q %q'):format(out..'/frames', out..'/state'))

-- The region list, flattened once, in the order they are written to s<F>.bin.
local regions = { {'palette', m.palette[1], m.palette[2]},
                  {'objram',  m.objram[1],  m.objram[2]},
                  {'vregs',   m.vregs[1],   m.vregs[2]} }
for i, L in ipairs(m.layers) do
  regions[#regions+1] = {('layer%d'):format(i-1), L[1], L[2]}
end

do
  local f = io.open(out..'/layout.txt', 'w')
  f:write(('set %s mode %s\n'):format(setname, mode))
  local off = 0
  for _, r in ipairs(regions) do
    f:write(('%-8s base=%06X len=%04X fileoff=%06X\n'):format(r[1], r[2], r[3], off))
    off = off + r[3]
  end
  f:write(('total %06X\n'):format(off))
  f:close()
end

local idx = io.open(out..'/index.txt', 'w')
local F = 0

local function dump_state()
  local f = io.open(('%s/state/s%d.bin'):format(out, F), 'wb')
  for _, r in ipairs(regions) do
    local base, len = r[2], r[3]
    local t = {}
    for a = 0, len - 2, 2 do
      local v = mem:read_u16(base + a)
      t[#t+1] = string.char(v & 0xFF, (v >> 8) & 0xFF)   -- u16 LE
    end
    f:write(table.concat(t))
  end
  f:close()
end

local function dump_pixels()
  -- screen:pixels() returns THREE values (pixels, width, height), and
  -- io.write writes all of its arguments -- writing it directly appends the
  -- ASCII "256224" to every frame. Bind the first value only.
  local px = scr:pixels()
  local f = io.open(('%s/frames/f%d.raw'):format(out, F), 'wb')
  f:write(px)
  f:close()
end

emu.register_frame_done(function()
  if F >= frames then
    idx:close()
    print(('ms1_capture: %s (mode %s) captured %d frames -> %s'):format(setname, mode, F, out))
    manager.machine:exit()
    return
  end
  if do_pix then dump_pixels() end
  if do_st  then dump_state()  end
  idx:write(('%d %d %s\n'):format(F, scr:frame_number(), tostring(manager.machine.time.seconds)))
  F = F + 1
end)
