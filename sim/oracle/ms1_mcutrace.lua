-- MAME oracle: the protection MCU's OWN bus trace.
--
--   MS1_OUT=<dir> [MS1_MACC=<n>] mame <set> ... -autoboot_script this
--
-- docs/PLAN.md step 4 says to run the re-parameterised TLCS-90 "standalone
-- against MAME's MCU trace". This produces that trace: every access the
-- TMP91640 makes in its own address space, which is directly comparable with
-- the RTL wrapper's dbg_addr/dbg_rd/dbg_wr probes.
--
-- Needs SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy (MS1-14) and no pipe on
-- stdout. Tap handles are globals on purpose (MS1-10).
local out  = os.getenv('MS1_OUT') or '/tmp/mcutrace'
local maxn = tonumber(os.getenv('MS1_MACC') or '400000')

local mcu = manager.machine.devices[':iomcu']
if not mcu then print('ms1_mcutrace: no :iomcu on this set'); return end
local mem = mcu.spaces['program']

os.execute(('mkdir -p %q'):format(out))
local f = io.open(out..'/mcu.log', 'w')
local n, done = 0, false

local function finish()
	if done then return end
	done = true
	f:close()
	print(('ms1_mcutrace: %d mcu accesses -> %s'):format(n, out))
	manager.machine:exit()
end

MR = mem:install_read_tap(0, mem.address_mask, 'mcur', function(offset, data, mask)
	if done then return data end
	n = n + 1
	f:write(('R %06X %02X\n'):format(offset, data & 0xFF))
	if n >= maxn then finish() end
	return data
end)
MW = mem:install_write_tap(0, mem.address_mask, 'mcuw', function(offset, data, mask)
	if done then return data end
	n = n + 1
	f:write(('W %06X %02X\n'):format(offset, data & 0xFF))
	if n >= maxn then finish() end
	return data
end)
