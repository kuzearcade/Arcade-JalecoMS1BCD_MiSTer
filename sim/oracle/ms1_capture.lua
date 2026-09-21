-- Arcade-JalecoMS1BCD_MiSTer — MAME oracle capture for Mega System 1 B/C/D.
--
--   MS1_OUT=<dir> MS1_FRAMES=<n> [MS1_PIX=1] [MS1_STATE=1] \
--     mame <set> -rompath mame_roms -video none -sound none -nothrottle \
--          -autoboot_script sim/oracle/ms1_capture.lua
--
-- Modelled on Arcade-SandScrp_MiSTer's sandscrp_capture.lua. Everything is
-- keyed by the capture's own frame counter F, so a frame's pixels and the
-- state that produced them can never drift apart.
--
-- THREE things here are specific to this board and each of them is a trap
-- docs/PLAN.md calls out by name:
--
-- 1. The memory map is MODE-DEPENDENT, and System D inverts the layer
--    ADDRESSES against the layer INDICES: MAME's m_tmap[0] VRAM is at
--    0E8000 and m_tmap[1] at 0D0000, the opposite of System C, while their
--    scroll REGISTERS stay in tmap-index order at 0C2000/0C2008. The map
--    below is written in m_tmap[] index order for both, so a consumer that
--    walks it by index is right in all three modes.
--
-- 2. SPRITES ARE TWO FRAMES AHEAD. megasys1_v.cpp screen_vblank does
--        buffer2 <- buffer ;  buffer <- live
--    every vblank, and draw_sprites reads buffer2. So the sprites in frame F
--    came from the object/sprite RAM that was live at frame F-2. This script
--    captures LIVE ram each frame; the consumer must use frame F-2's objram
--    and spriteram when reproducing frame F. Recorded in layout.txt so the
--    rule travels with the data.
--
-- 3. Several video registers are WRITE-ONLY (active_layers, screen_flag,
--    sprite_bank). Reading the register window through the CPU's program
--    space would return nothing for those AND would fire real read handlers
--    on everything else in range. Registers are therefore captured with
--    WRITE TAPS into a shadow table, which is side-effect free and exact.
--    Only plain RAM is read with read_u16.
--
-- Outputs:
--   frames/f<F>.raw  pixels of frame F, host-endian xRGB (256x224x4 bytes)
--   state/s<F>.bin   the RAM regions listed in layout.txt, each u16 LE
--   state/r<F>.txt   the register shadow at frame F, "name value" per line
--   layout.txt       region list, sizes, file offsets, and the F-2 rule
--   index.txt        F -> frame_number, machine time

local out    = os.getenv('MS1_OUT')    or 'sim/oracle/traces/ms1'
local frames = tonumber(os.getenv('MS1_FRAMES') or '120')
local do_pix = os.getenv('MS1_PIX')   == '1'
local do_st  = os.getenv('MS1_STATE') == '1'

local MODE = {
  avspirit='B', monkelf='B', edf='B', edfa='B', edfb='B', edfu='B', hayaosi1='B',
  ['64street']='C', ['64streetj']='C', ['64streetja']='C',
  bigstrik='C', chimerab='C', chimeraba='C', cybattlr='C',
  peekaboo='D', peekaboou='D',
}

-- Per mode: RAM regions (plain memory, safe to read) and the register file.
-- layers[] is in m_tmap[] INDEX order. wram is the work-RAM base; sprite RAM
-- is always wram + 0x8000, 0x2000 bytes (megasys1_v.cpp: &m_ram[0x8000/2]).
local MAP = {
  B = { palette=0x048000, objram=0x04E000, wram=0x060000,
        layers={0x050000, 0x054000, 0x058000},
        regs={ {0x044000,'active_layers'}, {0x044100,'sprite_flag'},
               {0x044300,'screen_flag'},
               {0x044200,'t0_sx'}, {0x044202,'t0_sy'}, {0x044204,'t0_ctrl'},
               {0x044208,'t1_sx'}, {0x04420A,'t1_sy'}, {0x04420C,'t1_ctrl'},
               {0x044008,'t2_sx'}, {0x04400A,'t2_sy'}, {0x04400C,'t2_ctrl'} },
        tapwin={0x044000,0x0443FF} },
  C = { palette=0x0F8000, objram=0x0D2000, wram=0x1C0000,
        layers={0x0E0000, 0x0E8000, 0x0F0000},
        regs={ {0x0C2208,'active_layers'}, {0x0C2200,'sprite_flag'},
               {0x0C2308,'screen_flag'},   {0x0C2108,'sprite_bank'},
               {0x0C2000,'t0_sx'}, {0x0C2002,'t0_sy'}, {0x0C2004,'t0_ctrl'},
               {0x0C2008,'t1_sx'}, {0x0C200A,'t1_sy'}, {0x0C200C,'t1_ctrl'},
               {0x0C2100,'t2_sx'}, {0x0C2102,'t2_sy'}, {0x0C2104,'t2_ctrl'} },
        tapwin={0x0C2000,0x0C23FF} },
  -- D: two layers. Note the VRAM inversion -- index 0 is the HIGHER address.
  D = { palette=0x0D8000, objram=0x0CA000, wram=0x1F0000,
        layers={0x0E8000, 0x0D0000},
        regs={ {0x0C2208,'active_layers'}, {0x0C2200,'sprite_flag'},
               {0x0C2308,'screen_flag'},
               {0x0C2000,'t0_sx'}, {0x0C2002,'t0_sy'}, {0x0C2004,'t0_ctrl'},
               {0x0C2008,'t1_sx'}, {0x0C200A,'t1_sy'}, {0x0C200C,'t1_ctrl'} },
        tapwin={0x0C2000,0x0C23FF} },
}

local setname = emu.romname()
local mode = MODE[setname]
if not mode then
  print(('ms1_capture: %s is not a B/C/D set; nothing to capture'):format(setname))
  return
end
local m = MAP[mode]

local cpu = manager.machine.devices[':maincpu']
local mem = cpu.spaces['program']
local scr = manager.machine.screens:at(1)

os.execute(('mkdir -p %q %q'):format(out..'/frames', out..'/state'))

-- RAM regions, in the order they are written to s<F>.bin.
local regions = { {'palette', m.palette, 0x0800},
                  {'objram',  m.objram,  0x2000},
                  {'spriteram', m.wram + 0x8000, 0x2000} }
for i, base in ipairs(m.layers) do
  regions[#regions+1] = {('layer%d'):format(i-1), base, 0x4000}
end

-- Register shadow, filled by write taps.
local shadow = {}
local byaddr = {}
for _, r in ipairs(m.regs) do shadow[r[2]] = 0; byaddr[r[1]] = r[2] end

-- NB: install_write_tap returns a memory_passthrough_handler that must be
-- kept alive. Let it go out of scope and Lua collects it, the tap is silently
-- removed, and every register reads back 0 forever -- which is exactly what
-- happened on the first attempt (docs/known-issues.md MS1-10). Hence TAP.
TAP = mem:install_write_tap(m.tapwin[1], m.tapwin[2], 'ms1regs', function(offset, data, mask)
  local name = byaddr[offset]
  if name then shadow[name] = data & 0xFFFF end
  return data
end)

do
  local f = io.open(out..'/layout.txt', 'w')
  f:write(('set %s mode %s\n'):format(setname, mode))
  local off = 0
  for _, r in ipairs(regions) do
    f:write(('%-9s base=%06X len=%04X fileoff=%06X\n'):format(r[1], r[2], r[3], off))
    off = off + r[3]
  end
  f:write(('total %06X\n'):format(off))
  f:write('layers are listed in MAME m_tmap[] INDEX order\n')
  f:write('SPRITES ARE TWO FRAMES AHEAD: to reproduce frame F, use the\n')
  f:write('objram and spriteram captured at frame F-2 (megasys1_v.cpp\n')
  f:write('screen_vblank: buffer2<-buffer, buffer<-live; draw reads buffer2)\n')
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
      t[#t+1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
    end
    f:write(table.concat(t))
  end
  f:close()
  local g = io.open(('%s/state/r%d.txt'):format(out, F), 'w')
  for _, r in ipairs(m.regs) do g:write(('%s %04X\n'):format(r[2], shadow[r[2]])) end
  g:close()
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
