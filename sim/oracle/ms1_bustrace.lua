-- Arcade-JalecoMS1BCD_MiSTer -- MAME oracle: main-CPU bus trace and the
-- protection handshake, for docs/PLAN.md M2 gates (1) and (5).
--
--   MS1_OUT=<dir> [MS1_ACC=<n>] [MS1_SKIP_ACC=<n>] \
--     mame <set> -rompath mame_roms -video none -sound none -nothrottle \
--          -autoboot_script sim/oracle/ms1_bustrace.lua
--
--   MS1_ACC       how many main-CPU accesses to log (default 200000)
--   MS1_SKIP_ACC  skip this many first (to reach past the boot clear loops)
--
-- Outputs:
--   bus.log    one line per main-CPU access:
--                <r|w> <seq> <pc> <addr> <data> <mask>
--              addresses are the CPU's own, unmasked.
--   prot.log   one line per access to the protection port, which is the
--              whole of the game's conversation with the MCU:
--                <r|w> <seq> <pc> <data>
--              This is the trace M2 gate (5) wants verified command by
--              command -- "the game boots" is explicitly not enough.
--   sound.log  one line per write to the sound latch, and per YM2151/OKI
--              write seen on the SOUND cpu, so the write COUNTS of gate (3)
--              can be compared without a full audio render.
--   summary.txt  counts, so a run can be checked without parsing the logs.
--
-- SDL must be told not to touch real devices or MAME hangs in device init
-- with zero CPU and no output (docs/known-issues.md MS1-14):
--   export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
-- and never give MAME a pipe on stdout -- it hides every error it prints.
--
-- The tap handles are kept in globals ON PURPOSE: install_*_tap returns a
-- passthrough handler whose lifetime the tap depends on, and letting it be
-- collected silently uninstalls the tap (MS1-10).

local out      = os.getenv('MS1_OUT') or 'sim/oracle/traces/bus'
local max_acc  = tonumber(os.getenv('MS1_ACC') or '200000')
local skip_acc = tonumber(os.getenv('MS1_SKIP_ACC') or '0')

-- setname -> { mode, protection port, sound latch (main side) }
local SET = {
  avspirit={'B',0x0E0000,0x044308}, monkelf={'B',0x0E0000,0x044308},
  edf={'B',0x0E0000,0x044308},  edfa={'B',0x0E0000,0x044308},
  edfb={'B',0x0E0000,0x044308}, edfu={'B',0x0E0000,0x044308},
  hayaosi1={'B',0x0E0000,0x044308},
  ['64street']={'C',0x0D8000,0x0C8000}, ['64streetj']={'C',0x0D8000,0x0C8000},
  ['64streetja']={'C',0x0D8000,0x0C8000},
  bigstrik={'C',0x0D8000,0x0C8000}, chimerab={'C',0x0D8000,0x0C8000},
  chimeraba={'C',0x0D8000,0x0C8000}, cybattlr={'C',0x0D8000,0x0C8000},
  peekaboo={'D',0x100000,0}, peekaboou={'D',0x100000,0},
}

local setname = emu.romname()
local e = SET[setname]
if not e then
  print(('ms1_bustrace: %s is not a B/C/D set'):format(setname))
  return
end
local mode, prot_addr, latch_addr = e[1], e[2], e[3]

local cpu = manager.machine.devices[':maincpu']
local mem = cpu.spaces['program']
-- The program space is masked per mode -- System B to 20 bits, C to 21, D
-- unmasked -- and install_*_tap refuses a range past the mask. Ask the
-- space rather than assuming, so one script covers all three.
local amask = mem.address_mask

os.execute(('mkdir -p %q'):format(out))
local fbus  = io.open(out..'/bus.log',  'w')
local fprot = io.open(out..'/prot.log', 'w')
local fsnd  = io.open(out..'/sound.log','w')

local seq, logged, done = 0, 0, false
local n_rd, n_wr, n_prot_r, n_prot_w, n_latch = 0, 0, 0, 0, 0

local function pc()
	local ok, v = pcall(function() return cpu.state['PC'].value end)
	return ok and v or 0
end

local function finish()
	if done then return end
	done = true
	fbus:close(); fprot:close(); fsnd:close()
	local f = io.open(out..'/summary.txt','w')
	f:write(('set %s\nmode %s\nprot_addr %06X\nlatch_addr %06X\n'):format(
		setname, mode, prot_addr, latch_addr))
	f:write(('accesses %d\nreads %d\nwrites %d\n'):format(seq, n_rd, n_wr))
	f:write(('prot_reads %d\nprot_writes %d\nlatch_writes %d\n'):format(
		n_prot_r, n_prot_w, n_latch))
	f:close()
	print(('ms1_bustrace: %s (mode %s) %d accesses, %d prot r/%d w, %d latch -> %s'):format(
		setname, mode, seq, n_prot_r, n_prot_w, n_latch, out))
	manager.machine:exit()
end

RTAP = mem:install_read_tap(0, amask, 'ms1busr', function(offset, data, mask)
	if done then return data end
	seq = seq + 1; n_rd = n_rd + 1
	if seq > skip_acc and logged < max_acc then
		logged = logged + 1
		fbus:write(('r %d %06X %06X %04X %04X\n'):format(seq, pc(), offset, data & 0xFFFF, mask & 0xFFFF))
	end
	if offset == prot_addr then
		n_prot_r = n_prot_r + 1
		fprot:write(('r %d %06X %04X\n'):format(seq, pc(), data & 0xFFFF))
	end
	if logged >= max_acc then finish() end
	return data
end)

WTAP = mem:install_write_tap(0, amask, 'ms1busw', function(offset, data, mask)
	if done then return data end
	seq = seq + 1; n_wr = n_wr + 1
	if seq > skip_acc and logged < max_acc then
		logged = logged + 1
		fbus:write(('w %d %06X %06X %04X %04X\n'):format(seq, pc(), offset, data & 0xFFFF, mask & 0xFFFF))
	end
	if offset == prot_addr then
		n_prot_w = n_prot_w + 1
		fprot:write(('w %d %06X %04X\n'):format(seq, pc(), data & 0xFFFF))
	end
	if latch_addr ~= 0 and offset == latch_addr then
		n_latch = n_latch + 1
		fsnd:write(('latch %d %06X %04X\n'):format(seq, pc(), data & 0xFFFF))
	end
	if logged >= max_acc then finish() end
	return data
end)

-- MAME 0.289 has no emu.register_stop; the trace ends when the access
-- budget is reached, which finish() detects inline.
