-- MAME oracle: the SOUND CPU's writes to the YM2151 and both OKIs, counted
-- per frame, for docs/PLAN.md M2 gate (3).
--
--   MS1_OUT=<dir> MS1_FRAMES=<n> mame <set> ... -autoboot_script this
--
-- Needs SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy (MS1-14), an absolute
-- -rompath (MS1-26), no pipe on stdout, and cfg/ cleared first (MS1-25).
-- Tap handles are globals on purpose (MS1-10), and NOTHING in the callback
-- may call scr:vpos(): it throws inside a memory tap and silently aborts the
-- rest of the callback (MS1-20's cousin, found the hard way).
local out   = os.getenv('MS1_OUT') or '/tmp/snd'
local maxf  = tonumber(os.getenv('MS1_FRAMES') or '400')

-- Also tap the MAIN CPU's writes to the sound latch, with the frame they
-- happen on. That sequence is the whole of the sound subsystem's input, so a
-- sound-only simulation can be driven from it -- which is the only practical
-- way to reach the frames where the OKIs are used (frame 1586 on avspirit)
-- without simulating the video for an hour.
local mcpu = manager.machine.devices[':maincpu']
local mmem = mcpu.spaces['program']
local cpu = manager.machine.devices[':audiocpu']
if not cpu then print('ms1_soundtrace: no :audiocpu'); return end
local mem = cpu.spaces['program']

os.execute(('mkdir -p %q'):format(out))
local f = io.open(out..'/sound.log','w')
local ym, o1, o2, frame = 0, 0, 0, 0

WT = mem:install_write_tap(0, mem.address_mask, 'ms1snd', function(offset, data, mask)
	if     offset >= 0x080000 and offset < 0x080004 then ym = ym + 1
	elseif offset >= 0x0A0000 and offset < 0x0A0004 then o1 = o1 + 1
	elseif offset >= 0x0C0000 and offset < 0x0C0004 then o2 = o2 + 1
	end
	return data
end)

local lf = io.open(out..'/latch.log','w')
local LATCH = (emu.romname() == '64street' or emu.romname() == '64streetj'
            or emu.romname() == '64streetja' or emu.romname() == 'bigstrik'
            or emu.romname() == 'chimerab' or emu.romname() == 'chimeraba'
            or emu.romname() == 'cybattlr') and 0x0C8000 or 0x044308
LT = mmem:install_write_tap(LATCH, LATCH + 1, 'ms1latch', function(offset, data, mask)
	local t = manager.machine.time
	lf:write(('%d %04X %d\n'):format(frame, data & 0xFFFF,
		math.floor((t.seconds + t.attoseconds / 1e18) * 48000000.0 + 0.5)))
	return data
end)

-- screen_flag bit 4 resets the sound 68000, the YM2151 and both OKIs at once
-- (megasys1_v.cpp:253-267). It is the only other input the sound side has, and
-- the games use it between tunes, so the sound-only harness needs it replayed
-- alongside the latch commands or the music never stops. See MS1-30.
local SCRFLAG = (LATCH == 0x0C8000) and 0x0C2308 or 0x044300
local sf = io.open(out..'/sreset.log','w')
local last_sr = 0
sf:write('0 0 0\n')
SF = mmem:install_write_tap(SCRFLAG, SCRFLAG + 1, 'ms1scrf', function(offset, data, mask)
	local b = (data >> 4) & 1
	-- Sub-frame position matters: this write lands mid-frame and the sound CPU
	-- keeps running until it does. Take it from machine.time -- NOT from
	-- scr:vpos(), which throws inside a memory tap and silently swallows the
	-- rest of the callback (MS1-20).
	if b ~= last_sr then
		local t = manager.machine.time
		local sec = t.seconds + t.attoseconds / 1e18
		sf:write(('%d %d %d\n'):format(frame, b, math.floor(sec * 48000000.0 + 0.5)))
		last_sr = b
	end
	return data
end)

emu.register_frame_done(function()
	f:write(('%d ym=%d oki1=%d oki2=%d\n'):format(frame, ym, o1, o2))
	frame = frame + 1
	if frame >= maxf then
		f:close(); lf:close(); sf:close()
		print(('ms1_soundtrace: %d frames, ym=%d oki1=%d oki2=%d -> %s'):format(frame, ym, o1, o2, out))
		manager.machine:exit()
	end
end)
