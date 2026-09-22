// Arcade-JalecoMS1BCD_MiSTer — MiSTer top level for the Jaleco Mega System 1
// B, C and D boards (1991-1993).
//
// One .rbf for all 17 romsets. The .mra chooses the board by the third
// <switches> byte (see "The game-mode byte" below); nothing here is per-set
// except the three input layouts, and those are selected from that same byte.
//
// Adapted from Arcade-SandScrp_MiSTer/SandScrp.sv, which is itself adapted
// from Arcade-NMK16_MiSTer's NMK16_Macross2.sv. The OSD layout, keyboard map,
// autofire, savestate and CRT Adjust wiring come from there. What differs:
//
//   * The raster is 384x278 at a 6 MHz pixel clock, visible 256x224 from row
//     16 (56.2 Hz). video_retime's DEFAULT VTOTAL_P is 278 -- this is the
//     raster that parameter was written for -- and the horizontal set is
//     384 px / 16 clk_r, 6144 clk_r per line at 96 MHz.
//   * Stereo. The YM2151 and the two OKIM6295s are panned in ms1_sound.sv, so
//     AUDIO_L and AUDIO_R carry different samples; SandScrp's board is mono.
//   * Both DIP banks reach the main 68000 through the I/O-MCU port mux
//     (rtl/jaleco/ms1_iomcu.sv), not through a sound chip.
//   * Three input layouts, not one: the megasys1 generic layout, hayaosi1's
//     three-player quiz panel, and peekaboo's paddle. See "Inputs" below.
//
// DEFERRED, and deliberately absent from the OSD rather than wired to
// nothing: Pause, High Scores, Cheats and Flip Screen. Each needs a port
// ms1bcd_core does not have (a CPU clock-enable gate, a work-RAM back door,
// an OSD flip input). They are M5 work; see docs/known-issues.md MS1-39.
//
// NOT yet run on hardware. This compiles and is consistent with the
// simulations, which are pixel-exact against MAME through the SDRAM path, but
// no bitstream has been on a DE10-Nano.
module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1; // signed PCM
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

wire [1:0] ar = status[122:121];
// "Original" aspect follows the orientation: 4:3 as the board outputs it,
// 3:4 once the framebuffer rotation turns cybattlr upright.
assign VIDEO_ARX = (!ar) ? (video_rotated ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (video_rotated ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	// Savestates: 4 slots of 0x80000 bytes at 0x3E000000. The image is
	// 0x30000 16-bit words = 0x60000 bytes (docs/m3-gate4.md), so the slot is
	// the next power of two up; SLOT_STRIDE below is this figure >> 3.
	"JalecoMS1BCD;SS3E000000:80000;",
	"-;",
	// Aspect ratio and Scandoubler Fx are the scaler's business; both hidden
	// (HB, menumask bit 11) under direct video, where the picture goes out at
	// native timing.
	"HBO[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"HBO[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	// Only cybattlr is ROT90 in MAME; the other 16 sets are ROT0 and want
	// Horz. ROT90 means the board draws on its side and the picture has to be
	// turned CLOCKWISE to stand upright, which is screen_rotate's
	// rotate_ccw = 0 case -- "Vert 90" here. "Vert 270" exists because a
	// cabinet's monitor can be mounted either way round. Hidden (H0) under
	// direct video, where the framebuffer path is unavailable.
	"H0O[9:8],Orientation,Horz,Vert 90,Vert 270;",
	"P3,CRT Adjust;",
	"P3O[101],CRT Adjust,Off,On;",
	"P3O[100:96],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[85:79],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[78:74],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[107:104],CRT V-Size,0,+1,+2,+3,+4,-4,-3,-2,-1;",
	"P3O[108],CRT V-Size Mode,PVM,Cabinet;",
	// Autofire on button 1, clocked by the game's own vblank. While a player
	// has it on, that player's button 3 is a plain button 1 and no longer
	// reaches the game. Always visible here: the sibling cores hide this
	// behind bit 6 of the .mra's third <switches> byte, and on this board that
	// byte is the game-mode byte with bits 6:5 already spoken for.
	"O[12:10],P1 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
	"O[15:13],P2 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
	"-;",
	// Where MiSTer inserts the DIP submenu it builds from the .mra's own
	// <switches>/<dip> entries. Changes arrive on ioctl index 254.
	"DIP;",
	"-;",
	"P4,Savestates;",
	"P4O[41:40],Slot,1,2,3,4;",
	"P4-;",
	// Slot 2 is F5, not F2: F2 is this core's Service Mode toggle.
	"P4R[42],Save state (Alt+F1 F5 F3 F4);",
	"P4R[43],Load state (F1 F5 F3 F4);",
	"-;",
	"R[0],Reset;",
	// Five entries, positionally matched against the <buttons> list
	// tools/gen_ms1bcd_mra.py writes into every .mra.
	"J1,Button 1,Button 2,Button 3,Start,Coin;",
	"I,",
	"Slot=F1 F5 F3 F4|Save=+Alt,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"State 1 saved,",
	"State 2 saved,",
	"State 3 saved,",
	"State 4 saved,",
	"State 1 loaded,",
	"State 2 loaded,",
	"State 3 loaded,",
	"State 4 loaded,",
	"Savestate failed,",
	"Slot empty;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire         direct_video;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;
wire   [7:0] paddle_0;

wire         ioctl_download;
wire         ioctl_wr;
wire  [26:0] ioctl_addr_full;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;
wire  [15:0] ioctl_index;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(vm_gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	// [11] hides Aspect ratio and Scandoubler Fx under direct video;
	// [0] hides Orientation under direct video. Nothing else is conditional.
	.status_menumask({4'd0, direct_video, 10'd0, direct_video}),
	.status_in({status[127:42], ss_slot, status[39:0]}),
	.status_set(ss_status_update),
	.info_req(ss_info_req),
	.info(ss_info),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.paddle_0(paddle_0),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr_full),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ioctl_index(ioctl_index),

	.ps2_key(ps2_key)
);
wire [24:0] ioctl_addr = ioctl_addr_full[24:0];

///////////////////////   CLOCKS   ///////////////////////////////

// 48 MHz. Every clock on these boards divides into it exactly: the main 68000
// is 12 MHz on System C and 8 MHz on B/D (/4 and /6), the sound 68000 7 MHz,
// the YM2151 3.5 MHz, both OKIs 4 MHz (/12), the pixel clock 6 MHz (/8).
// Only the two 7 MHz-family clocks need an accumulator, and its width is
// docs/known-issues.md MS1-28.
wire clk_sys;
wire clk_ram;     // 96 MHz, the SDRAM controller's own clock
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	.locked(pll_locked)
);

// The GAME reset. Held for the whole download, which is right: both CPUs must
// be quiescent while their ROMs load -- and then for a short tail afterwards.
//
// The tail is not cosmetic. The .mra's <switches> block arrives as its own
// ioctl session, so dip_sw -- and with it `mode`, which picks the memory map,
// the CPU divider and the input layout -- can take its final value on the very
// last cycle of ioctl_download. Without the tail the core leaves reset on the
// next cycle, and the fan-out of `mode` into the protection MCU's datapath is
// a ~34 ns path that has had one 20.8 ns cycle to settle. 255 clk_sys cycles
// (5.3 us) puts that beyond argument and is what lets JalecoMS1BCD.sdc call
// dip_sw a false path.
reg [7:0] dl_tail = 8'hFF;
always @(posedge clk_sys) begin
	if (ioctl_download)        dl_tail <= 8'd0;
	else if (dl_tail != 8'hFF) dl_tail <= dl_tail + 8'd1;
end
wire dl_settling = (dl_tail != 8'hFF);

wire reset = RESET | status[0] | buttons[1] | ioctl_download | dl_settling | ~pll_locked;

// The ROM loader's reset, and it is NOT the one above. ms1bcd_rom_hw IS the
// download: it has to keep working through the very window `reset` covers.
// Its request register is cleared by its reset --
//
//     if (reset) dl_req <= 1'b0;
//
// -- so any reset that is high during the transfer leaves dl_req permanently
// clear and not one byte reaches the SDRAM. Worse, ioctl_wait is then
// permanently low too, so the loader sees no backpressure, streams every byte
// at full speed and reports success. The board shows a perfectly timed,
// perfectly black screen while both CPUs execute whatever the previous core
// left in memory.
//
// This was measured twice on the sibling project's hardware (SandScrp SS-15,
// NMK16 before it, both after the same "0 bytes ever landing" result). So the
// loader gets a power-on-only reset. It is held until the PLL locks, because
// these 16 cycles are 333 ns at 48 MHz and a real altpll takes tens of
// microseconds to lock; without that the countdown can finish on an unstable
// clock and latch the SDRAM request logic into a state nothing ever resets.
reg [3:0] por_cnt = 4'd0;
reg       por_rst = 1'b1;
always @(posedge clk_sys) begin
	if (~pll_locked) begin
		por_cnt <= 4'd0;
		por_rst <= 1'b1;
	end else if (por_rst) begin
		if (por_cnt == 4'd15) por_rst <= 1'b0;
		else por_cnt <= por_cnt + 4'd1;
	end
end

// ------------------------------------------------------------------
// The .mra <switches> block, ioctl index 254. Bytes 0 and 1 are DSW1 and
// DSW2, which the main 68000 reads through the I/O-MCU's port mux. Byte 2 is
// NOT a DIP: it is the game-mode byte tools/gen_ms1bcd_mra.py writes into
// every .mra, and it is the only thing that tells one board apart from
// another.
//
//   bits 1:0  0 = System B, 1 = System C, 2 = System D
//   bit    4  the OKI sample clock is 2 MHz rather than 4 (MS1-8)
//   bits 6:5  protection: 0 real MCU, 1 simulated, 2 none, 3 System D's own
//
// It arrives LAST -- index 254 is a second ioctl session after the ROM -- so
// nothing that runs during the download may depend on it.
//
// Defaults are all-ones until the loader sends the block, matching an idle
// switch bank; the mode field therefore reads 3 (no board) until then, which
// is harmless because the core is in reset for the whole download.
// ------------------------------------------------------------------
reg [7:0] dip_sw [0:7];
integer dip_i;
initial for (dip_i = 0; dip_i < 8; dip_i = dip_i + 1) dip_sw[dip_i] = 8'hFF;
always @(posedge clk_sys) begin
	if (ioctl_download && ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

wire [1:0] mode     = dip_sw[2][1:0];
wire [1:0] prot_sel = dip_sw[2][6:5];
// Declared here because the .mra already carries it and the decode belongs
// with the rest of the byte; ms1_sound.sv has no port for it yet and runs
// both OKIs at 4 MHz. hayaosi1 and both peekaboo sets set it. MS1-8/MS1-40.
wire       oki_2mhz = dip_sw[2][4];

// ------------------------------------------------------------------
// Keyboard: MAME's own default bindings, always live, ORed with the pads.
//   P1: arrows, Left Ctrl = B1, Left Alt = B2, Space = B3,
//       Left Shift = B4, Z = B5  (the last two are hayaosi1 only)
//   P2: R/F/D/G, A = B1, S = B2, Q = B3
//   Coin 1 = 5, Coin 2 = 6, Service = 9, Start 1/2/3 = 1/2/3
//   F2 toggles Service Mode. Where that lands depends on the layout: DSW2
//   bit 7 on the generic boards, SYSTEM bit 3 on hayaosi1, SYSTEM bit 1 on
//   peekaboo (the input MAME labels "test").
// ------------------------------------------------------------------
reg [6:0] kb_p1 = 7'd0, kb_p2 = 7'd0;   // [0]=R [1]=L [2]=D [3]=U [4]=B1 [5]=B2 [6]=B3
reg kb_p1_b4 = 1'b0, kb_p1_b5 = 1'b0;
reg kb_start1 = 1'b0, kb_start2 = 1'b0, kb_start3 = 1'b0;
reg kb_coin1 = 1'b0, kb_coin2 = 1'b0, kb_service = 1'b0;
reg kb_test_mode = 1'b0, kb_f2_held = 1'b0, kb_toggle_d = 1'b0;
always @(posedge clk_sys) begin
	kb_toggle_d <= ps2_key[10];
	if (kb_toggle_d != ps2_key[10]) begin
		case (ps2_key[8:0])
			9'h175: kb_p1[3] <= ps2_key[9];
			9'h172: kb_p1[2] <= ps2_key[9];
			9'h16B: kb_p1[1] <= ps2_key[9];
			9'h174: kb_p1[0] <= ps2_key[9];
			9'h014: kb_p1[4] <= ps2_key[9];
			9'h011: kb_p1[5] <= ps2_key[9];
			9'h029: kb_p1[6] <= ps2_key[9];
			9'h012: kb_p1_b4  <= ps2_key[9];
			9'h01A: kb_p1_b5  <= ps2_key[9];
			9'h02D: kb_p2[3] <= ps2_key[9];
			9'h02B: kb_p2[2] <= ps2_key[9];
			9'h023: kb_p2[1] <= ps2_key[9];
			9'h034: kb_p2[0] <= ps2_key[9];
			9'h01C: kb_p2[4] <= ps2_key[9];
			9'h01B: kb_p2[5] <= ps2_key[9];
			9'h015: kb_p2[6] <= ps2_key[9];
			9'h016: kb_start1  <= ps2_key[9];
			9'h01E: kb_start2  <= ps2_key[9];
			9'h026: kb_start3  <= ps2_key[9];
			9'h02E: kb_coin1   <= ps2_key[9];
			9'h036: kb_coin2   <= ps2_key[9];
			9'h046: kb_service <= ps2_key[9];
			9'h006: begin
				if (ps2_key[9] && !kb_f2_held) kb_test_mode <= ~kb_test_mode;
				kb_f2_held <= ps2_key[9];
			end
			default: ;
		endcase
	end
end

// ------------------------------------------------------------------
// Autofire. The pattern advances once per game frame and restarts on each
// press, so a tap always fires on its first frame. With it on, button 1 is
// (held & pattern) | button 3, and button 3 itself stops reaching the game --
// it is the plain-fire escape hatch. bigstrik and the astyanax-family sets do
// use button 3, so this trade is real; leave Autofire off to keep it.
// ------------------------------------------------------------------
wire        vblank_core;
wire  [6:0] p1_raw = joystick_0[6:0] | kb_p1;
wire  [6:0] p2_raw = joystick_1[6:0] | kb_p2;
reg  vbl_d = 1'b0;
wire frame_tick = vblank_core & ~vbl_d;
always @(posedge clk_sys) vbl_d <= vblank_core;

function automatic [3:0] af_on(input [2:0] m);
	case (m) 3'd1: af_on = 4'd3; 3'd2: af_on = 4'd2; 3'd3: af_on = 4'd2; 3'd4: af_on = 4'd1; 3'd5: af_on = 4'd1; default: af_on = 4'd0; endcase
endfunction
function automatic [3:0] af_len(input [2:0] m);
	case (m) 3'd1: af_len = 4'd6; 3'd2: af_len = 4'd5; 3'd3: af_len = 4'd4; 3'd4: af_len = 4'd3; 3'd5: af_len = 4'd2; default: af_len = 4'd1; endcase
endfunction

reg  [3:0] af1_phase = 4'd0, af2_phase = 4'd0;
reg        af1_held_d = 1'b0, af2_held_d = 1'b0;
wire [2:0] af1_mode = status[12:10];
wire [2:0] af2_mode = status[15:13];
always @(posedge clk_sys) begin
	af1_held_d <= p1_raw[4];
	af2_held_d <= p2_raw[4];
	if (p1_raw[4] & ~af1_held_d) af1_phase <= 4'd0;
	else if (frame_tick) af1_phase <= (af1_phase + 4'd1 >= af_len(af1_mode)) ? 4'd0 : af1_phase + 4'd1;
	if (p2_raw[4] & ~af2_held_d) af2_phase <= 4'd0;
	else if (frame_tick) af2_phase <= (af2_phase + 4'd1 >= af_len(af2_mode)) ? 4'd0 : af2_phase + 4'd1;
end
wire af1_en = (af1_mode != 3'd0);
wire af2_en = (af2_mode != 3'd0);
wire p1_b1 = af1_en ? ((p1_raw[4] & (af1_phase < af_on(af1_mode))) | p1_raw[6]) : p1_raw[4];
wire p2_b1 = af2_en ? ((p2_raw[4] & (af2_phase < af_on(af2_mode))) | p2_raw[6]) : p2_raw[4];
wire p1_b3 = af1_en ? 1'b0 : p1_raw[6];
wire p2_b3 = af2_en ? 1'b0 : p2_raw[6];

// ------------------------------------------------------------------
// Inputs. Three layouts, all active low, all read through the I/O-MCU's port
// mux (rtl/jaleco/ms1_iomcu.sv), selected from the game-mode byte because
// nothing else here knows which set is loaded:
//
//   peekaboo   mode == D              -- both System D sets, and only those
//   hayaosi1   mode == B && prot == 1 -- the only simulated-protection B set
//                                        (chimeraba is the other iosim set,
//                                        and it is System C)
//   generic    everything else        -- MAME's INPUT_PORTS_START(megasys1_generic)
//
// The generic layout's direction order is right/left/down/up, which is the
// MiSTer pad's own bit order, so unlike Sand Scorpion nothing is reversed.
// ------------------------------------------------------------------
wire lay_peek = (mode == 2'd2);
wire lay_haya = (mode == 2'd0) & (prot_sel == 2'd1);

// --- generic: P1/P2 bit 0 right, 1 left, 2 down, 3 up, 4 B1, 5 B2, 6 B3.
//     SYSTEM bit 0 start 1, 1 start 2, 5 service, 6 coin 1, 7 coin 2.
wire [7:0] g_p1  = ~{1'b0, p1_b3, p1_raw[5], p1_b1, p1_raw[3], p1_raw[2], p1_raw[1], p1_raw[0]};
wire [7:0] g_p2  = ~{1'b0, p2_b3, p2_raw[5], p2_b1, p2_raw[3], p2_raw[2], p2_raw[1], p2_raw[0]};
wire [7:0] g_sys = ~{joystick_1[8] | kb_coin2, joystick_0[8] | kb_coin1, kb_service, 3'b000,
                     joystick_1[7] | kb_start2, joystick_0[7] | kb_start1};

// --- hayaosi1: a three-player quiz panel. Both "P1" and "P2" carry buttons
//     for all three players and no directions at all. Player 3 has no pad
//     here (only joystick_0 and joystick_1 are taken) and buttons 4 and 5
//     have no entry in the .mra's five-name <buttons> list, so P1's are on
//     the keyboard and P2's and P3's are unbound -- MS1-41.
//     SYSTEM bit 3 is PORT_SERVICE_NO_TOGGLE, which is where F2 goes here.
//     bit   7      6      5      4      3      2      1      0
//     P1   P3 B5  P1 B5  P3 B1  P3 B3  P1 B1  P1 B3  P2 B1  P2 B3
//     P2    --    P2 B5  P3 B2  P3 B4  P1 B2  P1 B4  P2 B2  P2 B4
wire [7:0] h_p1  = ~{1'b0, kb_p1_b5, 2'b00, p1_b1, p1_b3, p2_b1, p2_b3};
wire [7:0] h_p2  = ~{2'b00, 2'b00, p1_raw[5], kb_p1_b4, p2_raw[5], 1'b0};
wire [7:0] h_sys = ~{joystick_1[8] | kb_coin2, joystick_0[8] | kb_coin1, kb_service,
                     kb_start3, kb_test_mode, 1'b0,
                     joystick_1[7] | kb_start2, joystick_0[7] | kb_start1};

// --- peekaboo: P1 is an 8-bit PADDLE, not a joystick, clamped to the range
//     MAME's PORT_MINMAX gives it. SYSTEM is a 16-BIT port on this board and
//     ms1_iomcu's mux is 8 bits wide, so only the low half reaches the game:
//     the four coin inputs and the two starts. Its buttons live in the high
//     byte and are unreachable -- MS1-42, and moot until System D's memory
//     map exists (PLAN 2.5).
wire  [7:0] pad_cl = (paddle_0 < 8'h18) ? 8'h18 : (paddle_0 > 8'hE0) ? 8'hE0 : paddle_0;
wire  [7:0] k_p1   = pad_cl;
wire  [7:0] k_p2   = 8'hFF;
wire  [7:0] k_sys  = ~{2'b00,
                       joystick_1[7] | kb_start2, joystick_0[7] | kb_start1,
                       joystick_1[8] | kb_coin2,  joystick_0[8] | kb_coin1,
                       kb_test_mode, kb_service};

wire [7:0] in_p1     = lay_peek ? k_p1  : lay_haya ? h_p1  : g_p1;
wire [7:0] in_p2     = lay_peek ? k_p2  : lay_haya ? h_p2  : g_p2;
wire [7:0] in_system = lay_peek ? k_sys : lay_haya ? h_sys : g_sys;

// F2 is Service Mode. On the generic layout that is DSW2 bit 7
// (PORT_SERVICE, active low); the other two layouts put it in SYSTEM above,
// so the DSW2 bit must be left alone there or a real DIP gets flipped.
wire [7:0] in_dsw1 = dip_sw[0];
wire [7:0] in_dsw2 = dip_sw[1] ^ {(kb_test_mode & ~lay_peek & ~lay_haya), 7'd0};

// ------------------------------------------------------------------
// SDRAM: one controller on its own 96 MHz clock, four ports, fed by
// rtl/ms1bcd/ms1bcd_rom_hw.sv (nine caches, the arbiters and the download).
// Port 0 main 68000 + download, 1 layers 0/1, 2 layer 2 + sprites, 3 sound
// 68000 + MCU + both OKIs.
// ------------------------------------------------------------------
wire [24:1] sd0_addr, sd1_addr, sd2_addr, sd3_addr;
wire        sd0_wrl, sd0_wrh, sd1_wrl, sd1_wrh, sd2_wrl, sd2_wrh, sd3_wrl, sd3_wrh;
wire [15:0] sd0_din, sd1_din, sd2_din, sd3_din;
wire [15:0] sd0_dout, sd1_dout, sd2_dout, sd3_dout;
wire [31:0] sd0_pair, sd1_pair, sd2_pair, sd3_pair;
wire        sd0_req, sd1_req, sd2_req, sd3_req, sd0_ack, sd1_ack, sd2_ack, sd3_ack;
wire        sdram_ready;

// REFRESH_CYCLES at 96 MHz: 740 cycles is ~7.7 us, inside the 7.8125 us the
// MT48LC16M16 wants. rtl/sdram.sv's own default (850) is unsafe here and was
// measured producing real read-back corruption on silicon in the NMK16 work.
sdram #(.REFRESH_CYCLES(10'd740)) sdram_inst
(
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .ready(sdram_ready),
	.init(~pll_locked), .clk(clk_ram), .prio_mode(2'd0),
	.addr0(sd0_addr), .wrl0(sd0_wrl), .wrh0(sd0_wrh), .din0(sd0_din), .dout0(sd0_dout), .dout0_pair(sd0_pair), .req0(sd0_req), .ack0(sd0_ack),
	.addr1(sd1_addr), .wrl1(sd1_wrl), .wrh1(sd1_wrh), .din1(sd1_din), .dout1(sd1_dout), .dout1_pair(sd1_pair), .req1(sd1_req), .ack1(sd1_ack),
	.addr2(sd2_addr), .wrl2(sd2_wrl), .wrh2(sd2_wrh), .din2(sd2_din), .dout2(sd2_dout), .dout2_pair(sd2_pair), .req2(sd2_req), .ack2(sd2_ack),
	.addr3(sd3_addr), .wrl3(sd3_wrl), .wrh3(sd3_wrh), .din3(sd3_din), .dout3(sd3_dout), .dout3_pair(sd3_pair), .req3(sd3_req), .ack3(sd3_ack)
);

wire [18:0] rom_addr;      wire [15:0] rom_data;   wire rom_ready;
wire [16:0] srom_addr;     wire [15:0] srom_data;  wire srom_ready;
wire [13:0] mcu_rom_addr;  wire  [7:0] mcu_rom_data; wire mcu_rom_ready;
wire [20:0] l0_rom_addr, l1_rom_addr, l2_rom_addr;
wire [20:0] l0_use_addr, l1_use_addr, l2_use_addr;
wire  [7:0] l0_rom_data, l1_rom_data, l2_rom_data;
wire        l0_ready, l1_ready, l2_ready;
wire [21:0] spr_rom_addr; wire [7:0] spr_rom_data; wire spr_ready;
wire [17:0] oki1_rom_addr, oki2_rom_addr;
wire  [7:0] oki1_rom_data, oki2_rom_data;
wire        oki1_stall, oki2_stall;
wire  [8:0] prom_addr;     wire [7:0] prom_data;
wire [31:0] dbg_dl_bytes, dbg_prom_bytes;

// ---------------------------------------------------------------------------
// BRING-UP: the golden-byte audit, driven from here.
//
// dbg_dl_bytes counts what the core ACCEPTED from the loader, which is not the
// same as what the SDRAM stored or what the cache will hand back. This walks
// the main 68000 region and the MCU's internal ROM through the REAL caches and
// the REAL controller -- the same path the CPU uses -- and sums what comes
// back, so the sum can be compared against one computed off-board from the
// .mra stream. rom_hw's own comment records this instrument catching a bad
// word at address 0 once before.
//
// The core is held in reset for the whole walk (see the core's reset below),
// which is what lets rom_hw mux the audit address in without fighting it.
// ---------------------------------------------------------------------------
localparam DBG_AUDIT = 1;
wire [15:0] audit_data;
wire        audit_ready;
reg         aud_en   = 1'b0;
reg   [3:0] aud_sel  = 4'd0;
reg  [23:0] aud_addr = 24'd0;
reg  [31:0] aud_main = 32'd0, aud_mcu = 32'd0;
reg  [15:0] aud_w0 = 0, aud_w1 = 0, aud_w2 = 0, aud_w3 = 0;
reg  [31:0] aud_snd = 32'd0;
reg  [15:0] aud_sw0 = 0;
reg   [2:0] aud_rdy_n = 3'd0;
reg  [31:0] aud_main2 = 32'd0;
reg  [15:0] aud_wm = 0;
reg         aud_pass2 = 1'b0;
reg   [2:0] aud_st   = 3'd0;
reg   [7:0] aud_dly  = 8'd0;
reg  [15:0] aud_tmo  = 16'd0;
reg         aud_done = 1'b0;
always @(posedge clk_sys) begin
	case (aud_st)
	3'd0: begin   // wait for the loader to finish and the controller to come up
		if (DBG_AUDIT && !ioctl_download && !dl_settling && sdram_ready && !aud_done) begin
			aud_en <= 1'b1; aud_sel <= 4'd0; aud_addr <= 24'd0;
			aud_dly <= 8'd0; aud_tmo <= 16'd0; aud_st <= 3'd1;
		end
	end
	3'd1: begin   // let the new address propagate before believing `ready`
		// 7 cycles was not enough to trust, and worse, it was not REPRODUCIBLE:
		// two builds of the same design gave different main-region sums, which
		// is the signature of sampling a hit signal that has not settled. 31
		// cycles of settle, and `ready` must then be continuously high for 4
		// more before the word is taken.
		if (aud_dly == 8'd31) begin aud_st <= 3'd2; aud_rdy_n <= 3'd0; end
		else aud_dly <= aud_dly + 1'd1;
		aud_tmo <= 16'd0;
	end
	3'd2: begin   // wait for the cache, then take the word
		aud_tmo <= aud_tmo + 1'd1;
		if (audit_ready) aud_rdy_n <= (aud_rdy_n == 3'd4) ? 3'd4 : aud_rdy_n + 1'd1;
		else             aud_rdy_n <= 3'd0;
		if (aud_rdy_n == 3'd4 || aud_tmo == 16'hFFFF) begin
			if (aud_sel == 4'd1) begin
				aud_snd <= aud_snd + {16'd0, audit_data};
				if (aud_addr == 24'd0) aud_sw0 <= audit_data;
			end else if (aud_sel == 4'd0 && aud_pass2) begin
				aud_main2 <= aud_main2 + {16'd0, audit_data};
			end else if (aud_sel == 4'd0) begin
				aud_main <= aud_main + {16'd0, audit_data};
				if (aud_addr == 24'h001000) aud_wm <= audit_data;
				// The first four words of the main region, kept verbatim. A
				// checksum says "wrong" but not "how"; these have known values
				// -- avspirit's reset vector is SP 0x00080000, PC 0x000006B2,
				// so words 0..3 must read 0008 0000 0000 06B2.
				case (aud_addr[1:0])
					2'd0: if (aud_addr[23:2] == 22'd0) aud_w0 <= audit_data;
					2'd1: if (aud_addr[23:2] == 22'd0) aud_w1 <= audit_data;
					2'd2: if (aud_addr[23:2] == 22'd0) aud_w2 <= audit_data;
					2'd3: if (aud_addr[23:2] == 22'd0) aud_w3 <= audit_data;
				endcase
			end else begin
				aud_mcu  <= aud_mcu  + {24'd0, audit_data[7:0]};
			end
			aud_dly <= 8'd0;
			// main: 0x80000 bytes = 0x40000 words. MCU: 0x4000 bytes.
			if (aud_sel == 4'd0 && aud_addr == 24'h03FFFF && !aud_pass2) begin
				// Walk main a SECOND time. If the two passes agree with each
				// other but not with the expected sum, the data is wrong; if
				// they disagree, this instrument is and nothing it says about
				// the main region can be trusted.
				aud_pass2 <= 1'b1; aud_addr <= 24'd0; aud_st <= 3'd1;
			end else if (aud_sel == 4'd0 && aud_addr == 24'h03FFFF) begin
				aud_sel <= 4'd1; aud_addr <= 24'd0; aud_st <= 3'd1;
			end else if (aud_sel == 4'd1 && aud_addr == 24'h01FFFF) begin
				aud_sel <= 4'd2; aud_addr <= 24'd0; aud_st <= 3'd1;
			end else if (aud_sel == 4'd2 && aud_addr == 24'h003FFF) begin
				aud_en <= 1'b0; aud_done <= 1'b1; aud_st <= 3'd3;
			end else begin
				aud_addr <= aud_addr + 1'd1; aud_st <= 3'd1;
			end
		end
	end
	default: ;   // done; the core is released
	endcase
end
wire [31:0] dbg_irq2, dbg_int1e, dbg_mcuacc, dbg_vregw, dbg_vramw, dbg_romwait, dbg_romacc;
wire [23:0] tr_addr;  wire tr_valid;
wire [15:0] dbg_active;

ms1bcd_rom_hw rom_hw (
	.clk(clk_sys),
	.reset(reset),
	.pwr_reset(por_rst),   // power-on only -- see por_rst's declaration
	.mode(mode),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index[7:0]), .ioctl_wr(ioctl_wr),
	.ioctl_addr({2'd0, ioctl_addr}), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
	.rom_addr(rom_addr), .rom_data(rom_data), .rom_ready(rom_ready),
	.srom_addr(srom_addr), .srom_data(srom_data), .srom_ready(srom_ready),
	.mcu_rom_addr(mcu_rom_addr), .mcu_rom_data(mcu_rom_data), .mcu_rom_ready(mcu_rom_ready),
	.l0_rom_addr(l0_rom_addr), .l1_rom_addr(l1_rom_addr), .l2_rom_addr(l2_rom_addr),
	.l0_rom_use_addr(l0_use_addr), .l1_rom_use_addr(l1_use_addr), .l2_rom_use_addr(l2_use_addr),
	.l0_rom_data(l0_rom_data), .l1_rom_data(l1_rom_data), .l2_rom_data(l2_rom_data),
	.l0_ready(l0_ready), .l1_ready(l1_ready), .l2_ready(l2_ready),
	.spr_rom_addr(spr_rom_addr), .spr_rom_data(spr_rom_data), .spr_ready(spr_ready),
	.oki1_rom_addr(oki1_rom_addr), .oki2_rom_addr(oki2_rom_addr),
	.oki1_rom_data(oki1_rom_data), .oki2_rom_data(oki2_rom_data),
	.oki1_stall(oki1_stall), .oki2_stall(oki2_stall),
	.prom_addr(prom_addr), .prom_data(prom_data),
	// The golden-byte audit is a bring-up instrument, not a runtime feature.
	.audit_en(aud_en), .audit_sel(aud_sel), .audit_addr(aud_addr),
	.audit_data(audit_data), .audit_ready(audit_ready),
	.sdram_addr0(sd0_addr), .sdram_addr1(sd1_addr), .sdram_addr2(sd2_addr), .sdram_addr3(sd3_addr),
	.sdram_wrl0(sd0_wrl), .sdram_wrl1(sd1_wrl), .sdram_wrl2(sd2_wrl), .sdram_wrl3(sd3_wrl),
	.sdram_wrh0(sd0_wrh), .sdram_wrh1(sd1_wrh), .sdram_wrh2(sd2_wrh), .sdram_wrh3(sd3_wrh),
	.sdram_din0(sd0_din), .sdram_din1(sd1_din), .sdram_din2(sd2_din), .sdram_din3(sd3_din),
	.sdram_dout0(sd0_dout), .sdram_dout1(sd1_dout), .sdram_dout2(sd2_dout), .sdram_dout3(sd3_dout),
	.sdram_pair0(sd0_pair), .sdram_pair1(sd1_pair), .sdram_pair2(sd2_pair), .sdram_pair3(sd3_pair),
	.sdram_req0(sd0_req), .sdram_req1(sd1_req), .sdram_req2(sd2_req), .sdram_req3(sd3_req),
	.sdram_ack0(sd0_ack), .sdram_ack1(sd1_ack), .sdram_ack2(sd2_ack), .sdram_ack3(sd3_ack),
	.dbg_dl_bytes(dbg_dl_bytes), .dbg_prom_bytes(dbg_prom_bytes)
);

// ---------------------------------------------------------------------------
// Savestates. The engine parks both 68000s and the MCU, streams the core's
// image to a slot in DDR3 and back. Its DDR side shares the DDRAM port with
// screen_rotate and fills the gaps.
//
// SS_WORDS is the image size docs/m3-gate4.md maps, and RD_LAT 3 is the
// latency sim/rtl/ms1_frames/tb_frames.cpp streams the image at (three ticks
// between ss_addr and the ss_rdata it samples), so the engine sees exactly
// what every round-trip measurement so far has seen.
// ---------------------------------------------------------------------------
wire  [1:0] ss_slot;
wire  [7:0] ss_info;
wire        ss_save, ss_load, ss_info_req, ss_status_update;
wire        ss_busy, ss_done_ok, ss_done_fail, ss_was_load;
wire  [1:0] ss_fail_code;
wire        ss_freeze, ss_frozen, ss_parked, ss_resume, ss_active, ss_wr, ss_replay, ss_replay_done;
wire [19:0] ss_addr;
wire [15:0] ss_rdata, ss_wdata;
wire        eng_we, eng_rd;
wire [28:0] eng_addr;
wire [63:0] eng_din;

savestate_ui savestate_ui (
	.clk(clk_sys), .ps2_key(ps2_key), .allow_ss(~reset),
	.status_slot(status[41:40]), .OSD_saveload(status[43:42]),
	.done_ok(ss_done_ok), .done_fail(ss_done_fail), .fail_code(ss_fail_code), .was_load(ss_was_load),
	.ss_save(ss_save), .ss_load(ss_load), .ss_info_req(ss_info_req), .ss_info(ss_info),
	.statusUpdate(ss_status_update), .selected_slot(ss_slot)
);

savestate #(.SS_WORDS(20'h30000), .DDR_BASE(29'h07C00000), .SLOT_STRIDE(29'h00010000), .RD_LAT(3)) savestate (
	.clk(clk_sys), .reset(reset),
	.save_req(ss_save), .load_req(ss_load), .slot(ss_slot), .vblank(vblank_core), .allow(~ioctl_download),
	.ss_freeze(ss_freeze), .ss_frozen(ss_frozen), .ss_parked(ss_parked), .ss_resume(ss_resume), .ss_active(ss_active),
	.ss_addr(ss_addr), .ss_rdata(ss_rdata), .ss_wr(ss_wr), .ss_wdata(ss_wdata),
	.ss_replay(ss_replay), .ss_replay_done(ss_replay_done),
	.busy(ss_busy), .done_ok(ss_done_ok), .done_fail(ss_done_fail), .fail_code(ss_fail_code), .was_load(ss_was_load),
	.clk_ddr(CLK_VIDEO), .ddr_busy(DDRAM_BUSY), .rot_we(rot_we),
	.ddr_we(eng_we), .ddr_rd(eng_rd), .ddr_addr(eng_addr), .ddr_din(eng_din),
	.ddr_dout(DDRAM_DOUT), .ddr_dout_ready(DDRAM_DOUT_READY)
);

// ------------------------------------------------------------------
// The board
// ------------------------------------------------------------------
wire [23:0] core_rgb;
wire        ce_pix_core;
wire  [8:0] hcount_core, vcount_core;
wire signed [15:0] snd_l, snd_r;

// LOOKAHEAD 8 is the SDRAM path's tile-fetch head start; 0 is the
// zero-latency reference sim. The tile fetch is a raster and cannot stall, so
// it is given a lead instead and the misses are counted -- docs/PLAN.md 4.B.3
// and known-issues MS1-32.
ms1bcd_core #(.LOOKAHEAD(8)) core (
	.clk(clk_sys),
	// The CPUs are held in reset for the whole download and until the SDRAM
	// controller is up, so no cache can be asked for a byte that is not there.
	.reset(reset | ~sdram_ready | aud_en),
	.mode(mode),

	.rom_addr(rom_addr), .rom_data(rom_data), .rom_ready(rom_ready),
	.mcu_rom_addr(mcu_rom_addr), .mcu_rom_data(mcu_rom_data), .mcu_rom_ready(mcu_rom_ready),

	.in_p1(in_p1), .in_p2(in_p2), .in_dsw1(in_dsw1), .in_dsw2(in_dsw2), .in_system(in_system),

	.l0_rom_addr(l0_rom_addr), .l1_rom_addr(l1_rom_addr), .l2_rom_addr(l2_rom_addr),
	.l0_rom_use_addr(l0_use_addr), .l1_rom_use_addr(l1_use_addr), .l2_rom_use_addr(l2_use_addr),
	.l0_rom_data(l0_rom_data), .l1_rom_data(l1_rom_data), .l2_rom_data(l2_rom_data),
	.l0_rom_ready(l0_ready), .l1_rom_ready(l1_ready), .l2_rom_ready(l2_ready),
	.spr_rom_addr(spr_rom_addr), .spr_rom_data(spr_rom_data), .spr_rom_ready(spr_ready),
	.prom_addr(prom_addr), .prom_data(prom_data),

	.srom_addr(srom_addr), .srom_data(srom_data), .srom_ready(srom_ready),
	.oki1_rom_addr(oki1_rom_addr), .oki2_rom_addr(oki2_rom_addr),
	.oki1_rom_data(oki1_rom_data), .oki2_rom_data(oki2_rom_data),
	.oki1_stall(oki1_stall), .oki2_stall(oki2_stall),
	// MAME returns 0 from both OKI status registers, and every audio
	// measurement this project has taken was taken against that. Whether real
	// silicon does the same is MS1-31, which only a PCB can settle; the
	// bitstream ships what the gates were measured with.
	.oki_status_real(1'b0),
	.snd_l(snd_l), .snd_r(snd_r),
	.dbg_ym_writes(), .dbg_oki1_writes(), .dbg_oki2_writes(),
	.dbg_fm_l(), .dbg_fm_r(), .dbg_oki1(), .dbg_oki2(),

	.rgb(core_rgb), .rgb_valid(),
	.vblank_rise(), .vcount_o(vcount_core), .hcount_o(hcount_core), .ce_pix_o(ce_pix_core),

	.dbg_active(dbg_active), .dbg_t0c(), .dbg_t1c(), .dbg_t2c(),
	.dbg_t0x(), .dbg_t0y(), .dbg_t1x(), .dbg_t1y(), .dbg_t2x(), .dbg_t2y(),
	.dbg_sf(), .dbg_sb(), .dbg_scf(),
	.dbg_acc(), .dbg_vregw(dbg_vregw), .dbg_vramw(dbg_vramw),
	.tr_addr(tr_addr), .tr_data(), .tr_we(), .tr_valid(tr_valid),
	.dbg_irq2(dbg_irq2), .dbg_int1e(dbg_int1e), .dbg_mcuacc(dbg_mcuacc), .dbg_mcubank(),

	.ss_freeze(ss_freeze), .ss_resume(ss_resume), .ss_active(ss_active),
	.ss_addr(ss_addr), .ss_wr(ss_wr), .ss_wdata(ss_wdata), .ss_rdata(ss_rdata),
	.ss_frozen(ss_frozen), .ss_parked(ss_parked),
	.ss_replay(ss_replay), .ss_replay_done(ss_replay_done),
	.ss_rst_dbg(4'd0),   // bisection aid; tied off in any real build

	.dbg_romwait(dbg_romwait), .dbg_romacc(dbg_romacc),
	.dbg_l0_miss(), .dbg_l1_miss(), .dbg_l2_miss(), .dbg_pix(),
	.dbg_l2_first_v(), .dbg_l2_first_h(),
	.dbg_spr_pass_cycles(), .dbg_spr_late_swaps(),
	.dbg_palnz(), .dbg_opaque0(), .dbg_opaque2()
);

// Stereo: ms1_sound.sv pans the YM2151 and the two OKIM6295s the way MAME's
// machine configuration does.
assign AUDIO_L = snd_l;
assign AUDIO_R = snd_r;

// The core reports only its raster position, so vblank is derived here:
// visible is rows 16..239 of 278. The autofire frame tick and the savestate
// engine's "wait for vblank" are its only consumers -- the picture's own
// blanking is regenerated inside video_retime from the same counters.
assign vblank_core = (vcount_core < 9'd16) | (vcount_core >= 9'd240);

// ------------------------------------------------------------------
// Video. The core renders in real time on clk_sys; video_retime moves that
// raster onto the 96 MHz video clock, crt_chain applies the analog geometry
// controls, and video_mixer drives VGA_*.
//
// The raster is 384 x 278 at 6 MHz (clk_sys / 8). LINE_CLKS is the video-clock
// count of one line: 96 MHz / (6 MHz / 384) = 6144. DIV is the video clocks
// per pixel, 96 / 6 = 16. HSync is placed nominally in the blanking (front
// porch 32 px, sync 28 px = 4.7 us, back porch 68 px); CRT Adjust H-Position
// trims it downstream. Only mode 0 is used, so mode 1 is given the same
// geometry rather than a second set.
// ------------------------------------------------------------------
// The video clock is clk_ram, the SDRAM controller's own 96 MHz, not a PLL of
// its own: a second 96 MHz altpll from the same 50 MHz reference would simply
// be merged into this one by the fitter. Both sides of the core-to-video
// crossing are unchanged either way -- video_retime carries it with its own
// synchronisers.
wire clk_vid = clk_ram;

wire        rt_ce, rt_hs, rt_vs, rt_hb, rt_vb, rt_vb_hs;
wire [23:0] rt_rgb;
video_retime #(
	.M0_X0(10'd0), .M0_HT(10'd384), .M0_HS(10'd288), .M0_HW(10'd28), .M0_AW(10'd256), .M0_DIV(5'd16),
	.M1_X0(10'd0), .M1_HT(10'd384), .M1_HS(10'd288), .M1_HW(10'd28), .M1_AW(10'd256), .M1_DIV(5'd16),
	.LINE_CLKS(6144), .VTOTAL_P(278)
) video_retime (
	.clk_w(clk_sys), .reset_w(reset), .ce_w(ce_pix_core),
	.hcount_w({1'b0, hcount_core}), .vcount_w({1'b0, vcount_core}), .rgb_w(core_rgb),
	.mode1(1'b0), .tall240(1'b0),
	.clk_r(clk_vid),
	.ce_r(rt_ce), .rgb_r(rt_rgb), .hs_r(rt_hs), .vs_r(rt_vs), .de_r(),
	.hb_r(rt_hb), .vb_r(rt_vb), .vb_hs_r(rt_vb_hs)
);
assign CLK_VIDEO = clk_vid;

// The scandoubler must be off whenever the rotation framebuffer is active
// (NMK-28). screen_rotate has no backpressure -- it writes on every CE_PIXEL &
// VGA_DE and never looks at DDRAM_BUSY -- so at the doubled pixel rate its
// writes are dropped and the picture comes out cut off.
wire       fb_rotating = ~((status[9:8] == 2'd0) | direct_video);
wire [2:0] fx = direct_video ? 3'd0 : status[3:1];
wire       scandoubler_en = ((fx != 3'd0) || forced_scandoubler) && ~fb_rotating;
wire [1:0] sl = fx[2:1];
assign VGA_SL = sl;

wire        vm_ce_pix, vm_hs, vm_vs, vm_hb, vm_vb;
wire [23:0] retimed_rgb;
wire [21:0] vm_gamma_bus;
wire        crt_on = status[101] & ~scandoubler_en & ~fb_rotating;
crt_chain #(
	.HTOTAL0(10'd384), .HTOTAL1(10'd384), .DIV0(5'd16), .DIV1(5'd16),
	.VTOTAL(278), .LINE_PX(272), .VSIZE_MAX(4)
) crt_chain (
	.clk(clk_vid), .ce_in(rt_ce), .rgb_in(rt_rgb),
	.hs_in(rt_hs), .vs_in(rt_vs), .hb_in(rt_hb), .vb_in(rt_vb), .vb_hs_in(rt_vb_hs),
	.mode1(1'b0), .enable(crt_on),
	.hsize($signed(status[100:96])), .hpos_raw(status[85:79]),
	.vshift($signed(status[78:74])), .vsize_code(status[107:104]),
	.vsize_mode(status[108]),
	.ce_out(vm_ce_pix), .rgb_out(retimed_rgb),
	.hs_out(vm_hs), .vs_out(vm_vs), .hb_out(vm_hb), .vb_out(vm_vb)
);

// ------------------------------------------------------------------
// BRING-UP OVERLAY (DBG_OVERLAY = 1). Sixteen squares along the top of the
// picture, lit = true. It is drawn HERE, on clk_vid, after crt_chain -- not
// in the core -- so it renders even if clk_sys is dead or the core is held
// in reset, which is exactly the case it has to be able to report.
//
// Set DBG_OVERLAY to 0 for a shipping build.
//
//   0  pll_locked            8  mode[0]
//   1  sdram_ready           9  mode[1]
//   2  ioctl_download seen  10  clk_sys is toggling
//   3  ioctl_download now   11  the core's raster is advancing
//   4  any ROM byte taken   12  the core drew a non-black pixel
//   5  >1 MB taken          13  the main 68000 asked for a ROM word
//   6  any PROM byte taken  14  reset
//   7  switches seen (254)  15  sdram_ready has EVER been low
// ------------------------------------------------------------------
localparam DBG_OVERLAY = 0;   // 1 paints the bring-up overlay over the top 144 lines

// clk_sys liveness and core liveness, carried into clk_vid by toggle flags.
reg [20:0] dbg_syscnt = 0;
always @(posedge clk_sys) dbg_syscnt <= dbg_syscnt + 1'd1;
reg  dbg_rast = 1'b0;
always @(posedge clk_sys) if (vcount_core == 9'd100 && hcount_core == 9'd0) dbg_rast <= ~dbg_rast;
// Where is the 68000? tr_addr is the address of every bus cycle, far too fast
// to read off a screen, so it is sampled about four times a second and also
// kept as a high-water mark. A loop shows up as a sample that keeps landing in
// the same small range.
reg [23:0] dbg_pc_slow = 24'd0, dbg_pc_max = 24'd0;
reg [23:0] dbg_pc_div  = 24'd0;
always @(posedge clk_sys) begin
	dbg_pc_div <= dbg_pc_div + 1'd1;
	if (tr_valid && tr_addr > dbg_pc_max) dbg_pc_max <= tr_addr;
	if (dbg_pc_div == 24'd0 && tr_valid) dbg_pc_slow <= tr_addr;
end

reg  dbg_rom_seen = 1'b0;   // NOT dbg_romacc: that name is the core's own
                            // 32-bit counter, wired in above.
always @(posedge clk_sys) if (rom_addr != 19'd0) dbg_rom_seen <= 1'b1;
reg  dbg_pix_seen = 1'b0;
always @(posedge clk_sys) if (ce_pix_core && core_rgb != 24'd0) dbg_pix_seen <= 1'b1;
reg  dbg_dl_seen = 1'b0, dbg_sw_seen = 1'b0, dbg_sd_wasdown = 1'b0;
always @(posedge clk_sys) begin
	if (ioctl_download) dbg_dl_seen <= 1'b1;
	if (ioctl_download && ioctl_wr && ioctl_index == 16'd254) dbg_sw_seen <= 1'b1;
	if (~sdram_ready) dbg_sd_wasdown <= 1'b1;
end

// Two-flop synchronisers into clk_vid, and edge detection for the toggles.
reg [1:0] sy_sys, sy_rast;
reg       sy_sys_d, sy_rast_d;
// The decay must outlast the slowest thing being watched. dbg_syscnt[20]
// toggles every 21.8 ms at 48 MHz and the raster flag every 17.8 ms; a 255
// clk_vid decay is 2.7 us, so the first version of this reported both as dead
// while the download and the 68000's ROM reads proved clk_sys was fine. 2^24
// clk_vid is 0.17 s, comfortably longer than either.
reg [23:0] sys_alive, rast_alive;   // saturating "seen a toggle recently"
always @(posedge clk_vid) begin
	sy_sys  <= {sy_sys[0],  dbg_syscnt[20]};
	sy_rast <= {sy_rast[0], dbg_rast};
	sy_sys_d  <= sy_sys[1];
	sy_rast_d <= sy_rast[1];
	if (sy_sys[1]  != sy_sys_d)  sys_alive  <= 24'hFFFFFF; else if (|sys_alive)  sys_alive  <= sys_alive  - 1'd1;
	if (sy_rast[1] != sy_rast_d) rast_alive <= 24'hFFFFFF; else if (|rast_alive) rast_alive <= rast_alive - 1'd1;
end

wire [15:0] dbg_bits = {
	dbg_sd_wasdown, reset, dbg_rom_seen, dbg_pix_seen,
	|rast_alive, |sys_alive, mode[1], mode[0],
	dbg_sw_seen, (dbg_prom_bytes != 0), (dbg_dl_bytes > 32'd1000000), (dbg_dl_bytes != 0),
	aud_done, dbg_dl_seen, sdram_ready, pll_locked
};

// Pixel coordinates on the crt_chain output, from its own blanking.
reg [9:0] dbg_x = 0, dbg_y = 0;
reg       vm_hb_d = 1'b1;
always @(posedge clk_vid) begin
	if (vm_ce_pix) begin
		vm_hb_d <= vm_hb;
		if (vm_hb) dbg_x <= 10'd0;
		else       dbg_x <= dbg_x + 1'd1;
		if (vm_vb)              dbg_y <= 10'd0;
		else if (vm_hb & ~vm_hb_d) dbg_y <= dbg_y + 1'd1;
	end
end
// Nine rows of sixteen cells. Row 0 is the status bits above; the rest are
// the core's own counters, MSB at the left, so "is it zero?" and "is it
// counting?" are both readable from one screenshot.
//
//   1  main word0     (expect 0008)   4  main sum PASS 2 (expect E54D)
//   2  main word 0x1000 (expect 07BC)   5  snd sum lo      (expect 42CA)
//   3  main sum PASS 1 (expect E54D)    6  mcuacc  7  irq2  8  int1e
//
// The MCU row is the control: it read back exactly right on the first try,
// which is what says the download, the SDRAM and a byte-wide cache path are
// all sound, and narrows a mismatch to the 16-bit paths.
//
// Status bit 3 is now "audit finished" (it was "a download is in progress").

reg [15:0] dbg_row;
always @(*) case (dbg_y[7:4])
	4'd0: dbg_row = dbg_bits;
	4'd1: dbg_row = aud_w0;
	4'd2: dbg_row = aud_wm;
	4'd3: dbg_row = aud_main[15:0];
	4'd4: dbg_row = aud_main2[15:0];
	4'd5: dbg_row = aud_snd[15:0];
	4'd6: dbg_row = dbg_mcuacc[15:0];
	4'd7: dbg_row = dbg_irq2[15:0];
	4'd8: dbg_row = dbg_int1e[15:0];
	default: dbg_row = 16'd0;
endcase
wire       dbg_in    = DBG_OVERLAY && (dbg_y < 10'd144) && (dbg_x < 10'd256);
wire [3:0] dbg_idx   = 4'd15 - dbg_x[7:4];      // MSB at the left
wire       dbg_gap   = (dbg_x[3:0] > 4'd12) || (dbg_y[3:0] > 4'd12);
wire [23:0] dbg_rgb  = dbg_gap           ? 24'h000000 :
                       dbg_row[dbg_idx]  ? 24'h00FF40 : 24'h400000;
wire [23:0] mixer_rgb = dbg_in ? dbg_rgb : retimed_rgb;

video_mixer #(.LINE_LENGTH(272), .HALF_DEPTH(0), .GAMMA(0)) video_mixer (
	.CLK_VIDEO(CLK_VIDEO),
	.ce_pix(vm_ce_pix),
	.CE_PIXEL(CE_PIXEL),
	.scandoubler(scandoubler_en),
	.hq2x(fx == 3'd1),
	.gamma_bus(vm_gamma_bus),
	.R(mixer_rgb[23:16]), .G(mixer_rgb[15:8]), .B(mixer_rgb[7:0]),
	.HSync(vm_hs), .VSync(vm_vs), .HBlank(vm_hb), .VBlank(vm_vb),
	.HDMI_FREEZE(1'b0), .freeze_sync(),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_VS(VGA_VS), .VGA_HS(VGA_HS), .VGA_DE(VGA_DE)
);

// ------------------------------------------------------------------
// Orientation. Sixteen of the seventeen sets are ROT0 and want Horz; only
// cybattlr is ROT90, where the image has to be turned CLOCKWISE to stand
// upright -- screen_rotate's rotate_ccw = 0 case, offered as "Vert 90".
// "Vert 270" is for a cabinet whose monitor is mounted the other way round.
// ------------------------------------------------------------------
wire  [1:0] orientation = status[9:8];
wire        video_rotated;
wire        no_rotate = (orientation == 2'd0) | direct_video;
wire        rotate_ccw = (orientation == 2'd2);
wire        rot_we;
wire [28:0] rot_addr;
wire [63:0] rot_din;
wire  [7:0] rot_be;
screen_rotate screen_rotate (
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw), .no_rotate(no_rotate), .flip(1'b0), .video_rotated(video_rotated),
	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(), .DDRAM_ADDR(rot_addr),
	.DDRAM_DIN(rot_din), .DDRAM_BE(rot_be), .DDRAM_WE(rot_we), .DDRAM_RD()
);
// screen_rotate's write wins any cycle it appears on; the savestate engine
// fills the gaps. Both run on CLK_VIDEO.
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_ADDR     = rot_we ? rot_addr : eng_addr;
assign DDRAM_DIN      = rot_we ? rot_din  : eng_din;
assign DDRAM_BE       = rot_we ? rot_be   : 8'hFF;
assign DDRAM_WE       = rot_we | eng_we;
assign DDRAM_RD       = eng_rd;
assign FB_FORCE_BLANK = 1'b0;

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
