// Jaleco Mega System 1 main-CPU subsystem: the 68000, the board decode, the
// scanline interrupt timer and the protection MCU.
//
// Built to be compared against MAME's own main-CPU bus trace
// (sim/oracle/ms1_bustrace.lua), which is docs/PLAN.md M2 gate (1).
//
// Decode, System B (megasys1B_map, global_mask 0xFFFFF):
//   000000-03FFFF  ROM
//   044000         active_layers (w)
//   044008-04400D  layer 2 scroll
//   044100         sprite_flag
//   044200-044205  layer 0 scroll
//   044208-04420D  layer 1 scroll
//   044300         screen_flag (w)
//   044308         sound latch (w)
//   048000-0487FF  palette
//   04E000-04FFFF  object RAM
//   050000-053FFF  scroll 0 VRAM
//   054000-057FFF  scroll 1 VRAM
//   058000-05BFFF  scroll 2 VRAM
//   060000-06FFFF  work RAM, MIRRORED at 070000 -- and the mirror is what
//                  the games actually use: 340k of avspirit's first 1.5M
//                  accesses are at 07xxxx and none at 06xxxx.
//   080000-0BFFFF  ROM (maincpu + 0x40000)
//   0E0000         protection port
//
// System C moves everything (0C2000 video regs, 0F8000 palette, 0D2000
// object RAM, 0E0000/0E8000/0F0000 VRAM with +0x4000 mirrors, 1C0000 work RAM
// mirrored +0x30000, 0D8000 protection) and masks to 21 bits.
//
// WORK RAM BYTE WRITES MIRROR INTO BOTH HALVES. MAME's ram_w says so in
// capitals -- "DON'T use COMBINE_DATA ... 64th Street and Chimera Beast rely
// on this for attract inputs" -- so a byte write puts the same byte in both
// lanes rather than leaving the other alone. This is a real hardware quirk
// and not an emulator shortcut.
//
// Interrupts, System B and C with the MCU: scanline 96 raises level 1,
// scanline 240 raises level 4, and the MCU raises level 2 when it reads
// bank 7 of its own space. All are HOLD_LINE in MAME, i.e. asserted until
// the CPU acknowledges.

module ms1_main (
	input               clk,
	input               reset,
	input        [1:0]  mode,          // 0 = B, 1 = C

	// program ROM, served by the caller (512 KB, word addressed)
	output      [18:0]  rom_addr,
	input       [15:0]  rom_data,
	// HW_ROMS: high when rom_data reflects rom_addr. The reference sim ties it
	// high and the timing is unchanged; on the SDRAM path a miss withholds
	// DTACK, which is the stall the M3 `romwait` gate measures.
	input               rom_ready,

	// MCU internal ROM load
	output      [13:0]  mcu_rom_addr,
	input        [7:0]  mcu_rom_data,
	input               mcu_rom_ready,

	// board inputs
	input        [7:0]  in_p1, in_p2, in_dsw1, in_dsw2, in_system,

	// video timing in, so the interrupt timer and the MCU's INT1 are real
	input        [8:0]  vcount,
	input               vtick,         // one pulse per scanline

	// bus trace
	output reg  [23:0]  tr_addr,
	output reg  [15:0]  tr_data,
	output reg          tr_we,
	output reg          tr_valid,

	// ---- video-side read ports (the CPU owns these memories; the video
	// only ever reads them, so one extra read port each is enough)
	input       [12:0]  v0_rd_addr, v1_rd_addr, v2_rd_addr,
	output reg  [15:0]  v0_rd_data, v1_rd_data, v2_rd_data,
	input        [9:0]  pal_rd_addr,
	output reg  [15:0]  pal_rd_data,

	// Object and sprite RAM as the VIDEO sees them: TWO frames behind the
	// CPU. megasys1_v.cpp's screen_vblank does buffer2 <- buffer <- live
	// every vblank and draw_sprites reads buffer2, so the sprites on screen
	// are those the CPU wrote two frames ago. Sprite RAM is not a named
	// region at all -- it is work RAM + 0x8000 (&m_ram[0x8000/2]).
	input               vbl_rise,      // one pulse at the start of vblank
	input       [11:0]  obj_rd_addr,
	output reg  [15:0]  obj_rd_data,
	input       [11:0]  spr_rd_addr,
	output reg  [15:0]  spr_rd_data,

	// video registers, decoded for the video block
	output      [15:0]  reg_active_layers, reg_sprite_flag,
	output      [15:0]  reg_sprite_bank,   reg_screen_flag,
	output      [15:0]  reg_t0_sx, reg_t0_sy, reg_t0_ctrl,
	output      [15:0]  reg_t1_sx, reg_t1_sy, reg_t1_ctrl,
	output      [15:0]  reg_t2_sx, reg_t2_sy, reg_t2_ctrl,

	// probes
	output reg  [23:0]  dbg_ramw_addr,
	output reg  [15:0]  dbg_ramw_data,
	output reg          dbg_ramw,
	// sound latch out: one pulse per main-CPU write to the sound latch
	// (044308 on System B, 0C8000 on System C), carrying the command.
	output reg          slatch_we,
	output reg  [15:0]  slatch_data,

	output reg  [31:0]  dbg_acc, dbg_vregw, dbg_vramw,
	// ---- savestate snapshot bus (docs/m3-gate4.md has the image map).
	// Only meaningful while every CPU is parked: ss_active hands the RAM
	// ports to the engine.
	input               ss_active,
	input       [19:0]  ss_addr,
	input               ss_wr,
	input       [15:0]  ss_wdata,
	output reg  [15:0]  ss_rdata,
	input               ss_freeze,
	input               ss_resume,
	output              ss_m68k_parked,
	output              ss_mcu_frozen,

	output reg  [31:0]  dbg_irq2, dbg_int1e,
	output reg  [31:0]  dbg_romwait, dbg_romacc,
	output reg  [31:0]  dbg_mcuacc, dbg_mcubank
);
	// ------------------------------------------------------- 68000 clocking
	// enPhi1/enPhi2 must strictly alternate; fx68k wedges mid-cycle otherwise.
	reg [2:0] phdiv;
	wire [2:0] phdiv_max = (mode == 2'd1) ? 3'd1 : 3'd2;   // 12 MHz : 8 MHz
	reg enPhi1, enPhi2, phase;
	always @(posedge clk) begin
		if (reset) begin phdiv <= 3'd0; phase <= 1'b0; enPhi1 <= 1'b0; enPhi2 <= 1'b0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd4)) phdiv <= ss_wdata[2:0];
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd5)) phase <= ss_wdata[1];
		else if (ss_active) begin enPhi1 <= 1'b0; enPhi2 <= 1'b0; end
		else begin
			enPhi1 <= 1'b0; enPhi2 <= 1'b0;
			if (phdiv == phdiv_max) begin
				phdiv <= 3'd0;
				phase <= ~phase;
				if (phase) enPhi2 <= 1'b1; else enPhi1 <= 1'b1;
			end else phdiv <= phdiv + 3'd1;
		end
	end

	wire        eRWn, ASn, LDSn, UDSn, VMAn, FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
	wire [15:0] oEdb;
	wire [23:1] eab;
	reg  [15:0] iEdb;

	wire [23:0] byte_addr = {eab, 1'b0};
	wire        as_active = ~ASn & (~LDSn | ~UDSn);

	// ------------------------------------------------------------- decode
	wire is_c = (mode == 2'd1);

	// THE GLOBAL ADDRESS MASK IS PART OF THE DECODE. MAME's maps open with
	// map.global_mask(0xfffff) on System B and 0x1fffff on System C, and the
	// board really does ignore the high address lines. It matters from the
	// very first instruction: 64street's reset stack pointer is 0, so its
	// first push is to 0xFFFFFC, which is nothing at all unmasked and is
	// work RAM at 0x1FFFFC once masked. Decoding the raw 24-bit address
	// silently dropped every one of those writes -- and because the harness
	// masked the address only on its way into the TRACE, the trace looked
	// correct while the memory behind it was not being written.
	wire [23:0] amask = is_c ? 24'h1FFFFF : 24'h0FFFFF;
	wire [23:0] a = byte_addr & amask;

	// System B
	wire b_rom0 = ~is_c & (a < 24'h040000);
	wire b_rom1 = ~is_c & (a >= 24'h080000) & (a < 24'h0C0000);
	wire b_vreg = ~is_c & (a >= 24'h044000) & (a < 24'h044400);
	wire b_pal  = ~is_c & (a >= 24'h048000) & (a < 24'h048800);
	wire b_obj  = ~is_c & (a >= 24'h04E000) & (a < 24'h050000);
	wire b_v0   = ~is_c & (a >= 24'h050000) & (a < 24'h054000);
	wire b_v1   = ~is_c & (a >= 24'h054000) & (a < 24'h058000);
	wire b_v2   = ~is_c & (a >= 24'h058000) & (a < 24'h05C000);
	wire b_ram  = ~is_c & (a >= 24'h060000) & (a < 24'h080000);   // + mirror
	wire b_prot = ~is_c & (a >= 24'h0E0000) & (a < 24'h0E0002);

	// System C
	wire c_rom0 = is_c & (a < 24'h080000);
	wire c_vreg = is_c & (a >= 24'h0C2000) & (a < 24'h0C2400);
	wire c_pal  = is_c & (a >= 24'h0F8000) & (a < 24'h0F8800);
	wire c_obj  = is_c & (a >= 24'h0D2000) & (a < 24'h0D4000);
	wire c_v0   = is_c & (a >= 24'h0E0000) & (a < 24'h0E8000);
	wire c_v1   = is_c & (a >= 24'h0E8000) & (a < 24'h0F0000);
	wire c_v2   = is_c & (a >= 24'h0F0000) & (a < 24'h0F8000);
	wire c_ram  = is_c & (a >= 24'h1C0000) & (a < 24'h200000);
	wire c_prot = is_c & (a >= 24'h0D8000) & (a < 24'h0D8002);

	wire sel_rom  = b_rom0 | b_rom1 | c_rom0;
	wire sel_vreg = b_vreg | c_vreg;
	wire sel_pal  = b_pal  | c_pal;
	wire sel_obj  = b_obj  | c_obj;
	wire sel_v0   = b_v0   | c_v0;
	wire sel_v1   = b_v1   | c_v1;
	wire sel_v2   = b_v2   | c_v2;
	wire sel_ram  = b_ram  | c_ram;
	wire sel_prot = b_prot | c_prot;

	// ROM word index: B's second bank continues the same region at +0x40000
	assign rom_addr = b_rom1 ? {2'b10, a[17:1]} : a[19:1];

	// Hold the bus cycle until the program byte is actually there.
	wire rom_stall = as_active & sel_rom & ~rom_ready;
	always @(posedge clk) begin
		if (reset) begin dbg_romwait <= 32'd0; dbg_romacc <= 32'd0; end
		else begin
			if (rom_stall)                     dbg_romwait <= dbg_romwait + 32'd1;
			if (as_active & sel_rom & ~as_d_r) dbg_romacc  <= dbg_romacc  + 32'd1;
		end
	end
	reg as_d_r;
	always @(posedge clk) as_d_r <= as_active;

	// ------------------------------------------------------------ memories
	reg [15:0] wram [0:32767];
	reg [15:0] pal  [0:1023];
	reg [15:0] obj  [0:4095];
	reg [15:0] vr0  [0:8191];
	reg [15:0] vr1  [0:8191];
	reg [15:0] vr2  [0:8191];
	reg [15:0] vreg [0:511];

	wire [14:0] wram_i = is_c ? a[15:1] : a[15:1];
	wire  [9:0] pal_i  = a[10:1];
	wire [11:0] obj_i  = a[12:1];
	wire [12:0] v_i    = a[13:1];
	wire  [8:0] vreg_i = a[9:1];

	wire we = as_active & ~eRWn;
	wire [15:0] wdat = oEdb;
	// the work-RAM byte-write quirk (see header)
	wire [15:0] ram_wdat = (~LDSn & ~UDSn) ? wdat
	                     : (~UDSn) ? {wdat[15:8], wdat[15:8]}
	                               : {wdat[7:0],  wdat[7:0]};

	// ---- savestate region decode. Word addresses in the image; every base
	// is aligned to its own size so each select is a prefix compare.
	wire ss_wram = ss_active & (ss_addr[19:15] == 5'h00);   // 0x00000 32768
	wire ss_vr0  = ss_active & (ss_addr[19:13] == 7'h04);   // 0x08000  8192
	wire ss_vr1  = ss_active & (ss_addr[19:13] == 7'h05);   // 0x0A000  8192
	wire ss_vr2  = ss_active & (ss_addr[19:13] == 7'h06);   // 0x0C000  8192
	wire ss_pal  = ss_active & (ss_addr[19:10] == 10'h38);  // 0x0E000  1024
	wire ss_vreg = ss_active & (ss_addr[19:9]  == 11'h72);  // 0x0E400   512
	wire ss_obj  = ss_active & (ss_addr[19:12] == 8'h0F);   // 0x0F000  4096
	wire ss_ob1  = ss_active & (ss_addr[19:12] == 8'h18);   // 0x18000  4096
	wire ss_ob2  = ss_active & (ss_addr[19:12] == 8'h19);
	wire ss_sb1  = ss_active & (ss_addr[19:12] == 8'h1A);
	wire ss_sb2  = ss_active & (ss_addr[19:12] == 8'h1B);
	wire ss_misc = ss_active & (ss_addr[19:4] == 16'h1D00);  // 0x1D000 scalars
	wire ss_mcu  = ss_active & (ss_addr[19:12] == 8'h1C);   // 0x1C000 the MCU
	wire [15:0] ss_mcu_rdata;
	wire ss_w    = ss_active & ss_wr;

	reg [15:0] rdat;
	always @(posedge clk) begin
		dbg_ramw <= we & sel_ram;
		dbg_ramw_data <= ram_wdat;
		dbg_ramw_addr <= a;
		dbg_ramw_data <= ram_wdat;
		if (ss_w) begin
			// The engine owns the ports while it is streaming an image down.
			if (ss_wram) wram[ss_addr[14:0]] <= ss_wdata;
			if (ss_vr0)  vr0[ss_addr[12:0]]  <= ss_wdata;
			if (ss_vr1)  vr1[ss_addr[12:0]]  <= ss_wdata;
			if (ss_vr2)  vr2[ss_addr[12:0]]  <= ss_wdata;
			if (ss_pal)  pal[ss_addr[9:0]]   <= ss_wdata;
			if (ss_vreg) vreg[ss_addr[8:0]]  <= ss_wdata;
			if (ss_obj)  obj[ss_addr[11:0]]  <= ss_wdata;
		end else if (we) begin
			if (sel_ram)  wram[wram_i] <= ram_wdat;
			if (sel_pal)  pal[pal_i]   <= wdat;
			if (sel_obj)  obj[obj_i]   <= wdat;
			if (sel_v0)   vr0[v_i]     <= wdat;
			if (sel_v1)   vr1[v_i]     <= wdat;
			if (sel_v2)   vr2[v_i]     <= wdat;
			if (sel_vreg) vreg[vreg_i] <= wdat;
		end
	end

	// ---- the scalar state: everything that is neither a RAM nor inside a
	// CPU. A savestate that restores every array and forgets these comes back
	// with the right picture and the wrong interrupt timing.
	reg [15:0] ss_misc_rdata;
	always @* begin
		case (ss_addr[3:0])
			4'd0: ss_misc_rdata = {2'd0, bufi, buf_busy};
			4'd1: ss_misc_rdata = {12'd0, irq1_h, irq2_h, irq4_h, iack_d};
			4'd2: ss_misc_rdata = {13'd0, int1_dd, slatch_d, prot_we_pulse};
			4'd3: ss_misc_rdata = {13'd0, mdiv};
			4'd4: ss_misc_rdata = {13'd0, phdiv};
			4'd5: ss_misc_rdata = {14'd0, phase, as_d};
			default: ss_misc_rdata = 16'h0000;
		endcase
	end
	// NOTE: every scalar above is restored INSIDE the block that owns it.
	// A separate restore block would be a second driver, and the owning
	// block wins on the next clock -- the restore then does nothing at all,
	// silently. The image loopback is what exposed this: 4 words of this
	// region did not read back what had just been written to them.

	// ---- savestate readback, registered once here (the core registers it
	// again, which is still inside the engine's RD_LAT).
	always @(posedge clk) begin
		if      (ss_wram) ss_rdata <= wram[ss_addr[14:0]];
		else if (ss_vr0)  ss_rdata <= vr0[ss_addr[12:0]];
		else if (ss_vr1)  ss_rdata <= vr1[ss_addr[12:0]];
		else if (ss_vr2)  ss_rdata <= vr2[ss_addr[12:0]];
		else if (ss_pal)  ss_rdata <= pal[ss_addr[9:0]];
		else if (ss_vreg) ss_rdata <= vreg[ss_addr[8:0]];
		else if (ss_obj)  ss_rdata <= obj[ss_addr[11:0]];
		else if (ss_ob1)  ss_rdata <= obj_b1[ss_addr[11:0]];
		else if (ss_ob2)  ss_rdata <= obj_b2[ss_addr[11:0]];
		else if (ss_sb1)  ss_rdata <= spr_b1[ss_addr[11:0]];
		else if (ss_sb2)  ss_rdata <= spr_b2[ss_addr[11:0]];
		else if (ss_mcu)  ss_rdata <= ss_mcu_rdata;
		else if (ss_park) ss_rdata <= ss_park_rdata;
		else if (ss_misc) ss_rdata <= ss_misc_rdata;
		else              ss_rdata <= 16'h0000;
	end

	// ---- video read ports.
	// COMBINATIONAL on purpose: ms1_tilemap and ms1_sprites register their
	// ADDRESS and expect the data in the following cycle, which is the bus
	// convention the whole video block was verified against in
	// sim/rtl/video_state. Making these registered instead would insert a
	// second cycle of latency and quietly shift every fetch by one.
	// (On hardware these become M10K reads with the same one-cycle shape.)
	always @* begin
		v0_rd_data  = vr0[v0_rd_addr];
		v1_rd_data  = vr1[v1_rd_addr];
		v2_rd_data  = vr2[v2_rd_addr];
		pal_rd_data = pal[pal_rd_addr];
	end

	// ---- the two-deep object/sprite buffers
	reg [15:0] obj_b1 [0:4095];
	reg [15:0] obj_b2 [0:4095];
	reg [15:0] spr_b1 [0:4095];
	reg [15:0] spr_b2 [0:4095];
	reg [12:0] bufi;
	reg        buf_busy;
	always @(posedge clk) begin
		if (reset) begin buf_busy <= 1'b0; bufi <= 13'd0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd0)) begin
			bufi <= ss_wdata[13:1]; buf_busy <= ss_wdata[0];
		end
		else if (vbl_rise) begin buf_busy <= 1'b1; bufi <= 13'd0; end
		else if (ss_w & (ss_ob1 | ss_ob2 | ss_sb1 | ss_sb2)) begin
			if (ss_ob1) obj_b1[ss_addr[11:0]] <= ss_wdata;
			if (ss_ob2) obj_b2[ss_addr[11:0]] <= ss_wdata;
			if (ss_sb1) spr_b1[ss_addr[11:0]] <= ss_wdata;
			if (ss_sb2) spr_b2[ss_addr[11:0]] <= ss_wdata;
		end
		else if (buf_busy) begin
			obj_b2[bufi[11:0]] <= obj_b1[bufi[11:0]];
			obj_b1[bufi[11:0]] <= obj[bufi[11:0]];
			spr_b2[bufi[11:0]] <= spr_b1[bufi[11:0]];
			// sprite RAM is work RAM + 0x8000, i.e. word 0x4000 upwards
			// sprite RAM is work RAM + 0x8000 BYTES, i.e. word 0x4000
			spr_b1[bufi[11:0]] <= wram[15'h4000 + {3'd0, bufi[11:0]}];
			if (bufi == 13'd4095) buf_busy <= 1'b0;
			else bufi <= bufi + 13'd1;
		end
	end
	always @* begin
		obj_rd_data = obj_b2[obj_rd_addr];
		spr_rd_data = spr_b2[spr_rd_addr];
	end

	// ---- video registers, at their System B offsets (the harness feeds
	// System C's addresses through the same array, since vreg is indexed by
	// the low bits of whichever window the mode decoded)
	assign reg_active_layers = is_c ? vreg[9'h104] : vreg[9'h000];
	assign reg_sprite_flag   = is_c ? vreg[9'h100] : vreg[9'h080];
	assign reg_sprite_bank   = is_c ? vreg[9'h084] : 16'h0000;
	assign reg_screen_flag   = is_c ? vreg[9'h184] : vreg[9'h180];
	assign reg_t0_sx         = is_c ? vreg[9'h000] : vreg[9'h100];
	assign reg_t0_sy         = is_c ? vreg[9'h001] : vreg[9'h101];
	assign reg_t0_ctrl       = is_c ? vreg[9'h002] : vreg[9'h102];
	assign reg_t1_sx         = is_c ? vreg[9'h004] : vreg[9'h104];
	assign reg_t1_sy         = is_c ? vreg[9'h005] : vreg[9'h105];
	assign reg_t1_ctrl       = is_c ? vreg[9'h006] : vreg[9'h106];
	assign reg_t2_sx         = is_c ? vreg[9'h080] : vreg[9'h004];
	assign reg_t2_sy         = is_c ? vreg[9'h081] : vreg[9'h005];
	assign reg_t2_ctrl       = is_c ? vreg[9'h082] : vreg[9'h006];

	wire [7:0] prot_rd;
	always @* begin
		if      (sel_mon)  rdat = mon_data;   // the park monitor's overlay
		else if (sel_rom)  rdat = rom_data;
		else if (sel_ram)  rdat = wram[wram_i];
		else if (sel_pal)  rdat = pal[pal_i];
		else if (sel_obj)  rdat = obj[obj_i];
		else if (sel_v0)   rdat = vr0[v_i];
		else if (sel_v1)   rdat = vr1[v_i];
		else if (sel_v2)   rdat = vr2[v_i];
		else if (sel_vreg) rdat = vreg[vreg_i];
		else if (sel_prot) rdat = {8'h00, prot_rd};
		else               rdat = 16'h0000;
	end
	always @* iEdb = rdat;

	// --------------------------------------------------------- protection
	// The MCU runs at the MAIN CPU's clock: 8 MHz on System B, 12 MHz on
	// System C. From 48 MHz that is a divide by 6 and by 4 -- NOT the same
	// count as the 68000's phi divider, which is half a CPU cycle. Getting
	// this wrong by 2x does not break anything visibly: the MCU simply
	// answers the protection handshake twice as fast, and the IRQ 2 it
	// raises lands tens of accesses early.
	wire [2:0] mdiv_max = is_c ? 3'd3 : 3'd5;
	reg  [2:0] mdiv;
	always @(posedge clk) begin
		if (reset) mdiv <= 3'd0;
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd3)) mdiv <= ss_wdata[2:0];
		else if (ss_active) mdiv <= mdiv;
		else mdiv <= (mdiv == mdiv_max) ? 3'd0 : mdiv + 3'd1;
	end
	wire mcu_cen_tick = (mdiv == mdiv_max);

	wire mcu_irq2;
	wire [3:0] mcu_dbg_bank;
	wire mcu_dbg_rd;
	// INT1 is display enable: high over the visible rows (MS1-19)
	wire int1 = (vcount >= 9'd16) && (vcount < 9'd240);

	reg prot_we_pulse;
	always @(posedge clk)
		if (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) prot_we_pulse <= ss_wdata[0];
		else prot_we_pulse <= we & sel_prot;
	wire prot_we_edge = (we & sel_prot) & ~prot_we_pulse;

	ms1_iomcu u_mcu (
		.clk(clk), .cen(mcu_cen_tick), .reset(reset),
		.host_we(prot_we_edge), .host_data(oEdb[7:0]),
		.mcu_data(prot_rd), .main_irq2(mcu_irq2),
		.int1(int1),
		.in_p1(in_p1), .in_p2(in_p2), .in_dsw1(in_dsw1),
		.in_dsw2(in_dsw2), .in_system(in_system),
				.rom_addr(mcu_rom_addr), .rom_data(mcu_rom_data), .rom_ready(mcu_rom_ready),
		.ss_active(ss_active), .ss_addr(ss_addr), .ss_wr(ss_wr),
		.ss_wdata(ss_wdata), .ss_rdata(ss_mcu_rdata),
		.ss_freeze(ss_freeze), .ss_frozen(ss_mcu_frozen),
		.dbg_addr(), .dbg_bank(mcu_dbg_bank), .dbg_rd(mcu_dbg_rd), .dbg_wr(), .dbg_din()
	);

	always @(posedge clk) begin
		if (reset) begin dbg_mcuacc <= 0; dbg_mcubank <= 0; end
		else if (mcu_cen_tick) begin
			if (mcu_dbg_rd) dbg_mcuacc <= dbg_mcuacc + 1;
			if (mcu_dbg_rd && mcu_dbg_bank != 4'd0) dbg_mcubank <= dbg_mcubank + 1;
		end
	end

	wire sel_slatch = is_c ? (a >= 24'h0C8000 && a < 24'h0C8002)
	                       : (a >= 24'h044308 && a < 24'h04430A);
	reg slatch_d;
	always @(posedge clk) begin
		slatch_d  <= (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) ? ss_wdata[1] : (we & sel_slatch);
		slatch_we <= (we & sel_slatch) & ~slatch_d;
		if ((we & sel_slatch) & ~slatch_d) slatch_data <= wdat;
	end

	// --------------------------------------------------- interrupt timer
	// HOLD_LINE: the level stays asserted until the CPU acknowledges it.
	reg irq1_h, irq2_h, irq4_h;
	wire iack = ~ASn & (FC0 & FC1 & FC2);
	// ONE clear per acknowledge CYCLE, not per clock. iack is a level that
	// stays asserted for the whole ack bus cycle; clearing on the level
	// walks down the priority chain and retires every pending interrupt at
	// once. The symptom is that only the highest-priority source is ever
	// seen: IRQ 4 fired every frame while IRQ 1 and the protection's IRQ 2
	// were raised and silently discarded, and the game sat in its STOP loop
	// waiting for a handler that never ran.
	reg int1_dd;
	always @(posedge clk) begin
		if (reset) begin dbg_irq2 <= 0; dbg_int1e <= 0; int1_dd <= 0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) int1_dd <= ss_wdata[2];
		else begin
			if (mcu_irq2) dbg_irq2 <= dbg_irq2 + 1;
			int1_dd <= int1;
			if (int1 & ~int1_dd) dbg_int1e <= dbg_int1e + 1;
		end
	end

	reg iack_d;
	always @(posedge clk)
		if (ss_w & ss_misc & (ss_addr[3:0] == 4'd1)) iack_d <= ss_wdata[0];
		else iack_d <= iack;
	wire iack_edge = iack & ~iack_d;
	always @(posedge clk) begin
		if (reset) begin irq1_h <= 1'b0; irq2_h <= 1'b0; irq4_h <= 1'b0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd1)) begin
			irq1_h <= ss_wdata[3]; irq2_h <= ss_wdata[2]; irq4_h <= ss_wdata[1];
		end
		else begin
			if (vtick && vcount == 9'd96)  irq1_h <= 1'b1;
			if (vtick && vcount == 9'd240) irq4_h <= 1'b1;
			if (mcu_irq2)                  irq2_h <= 1'b1;
			if (iack_edge) begin
				if      (irq4_h) irq4_h <= 1'b0;
				else if (irq2_h) irq2_h <= 1'b0;
				else if (irq1_h) irq1_h <= 1'b0;
			end
		end
	end
	// ---- savestate: park the 68000 at an instruction boundary.
	// MON_BASE must be unmapped on every board this core serves. 0x0C0000 is
	// free on System B (above rom1's 0x80000-0xBFFFF, below the protection
	// port at 0xE0000) and on System C (below c_vreg at 0xC2000).
	wire [2:0] ipl_park;
	wire       sel_mon;
	wire [15:0] mon_data;
	ss_m68k_park #(.MON_BASE(15'h600)) u_park (
		.clk(clk), .reset(reset), .phi(enPhi2),
		.park_req(ss_freeze), .parked(ss_m68k_parked), .resume(ss_resume),
		.eab(eab), .ASn(ASn), .eRWn(eRWn), .FC0(FC0), .FC1(FC1), .FC2(FC2),
		.oEdb(oEdb),
		.ipl_park(ipl_park), .sel_mon(sel_mon), .mon_data(mon_data),
		.ss_sel(ss_addr[1:0]), .ss_wr(ss_w & ss_park), .ss_wdata(ss_wdata),
		.ss_rdata(ss_park_rdata)
	);
	wire [15:0] ss_park_rdata;
	wire        ss_park = ss_active & (ss_addr[19:4] == 16'h1D01);  // 0x1D010

	wire [2:0] ipl_game = irq4_h ? 3'd4 : irq2_h ? 3'd2 : irq1_h ? 3'd1 : 3'd0;
	// The park request is level 7 and outranks everything the board can raise.
	wire [2:0] ipl = (ipl_park != 3'd0) ? ipl_park : ipl_game;

	// -------------------------------------------------------- bus tracing
	reg as_d;
	always @(posedge clk) begin
		if (reset) begin dbg_acc <= 0; dbg_vregw <= 0; dbg_vramw <= 0; end
		else if (as_active & ~as_d) begin
			dbg_acc <= dbg_acc + 1;
			if (~eRWn & sel_vreg) dbg_vregw <= dbg_vregw + 1;
			if (~eRWn & (sel_v0|sel_v1|sel_v2)) dbg_vramw <= dbg_vramw + 1;
		end
		as_d <= as_active;
		tr_valid <= 1'b0;
		// The interrupt-acknowledge cycle (FC = 111) is a real bus cycle on
		// hardware -- the 68000 drives 0xFFFFFx with the level in A3:A1 -- but
		// MAME services autovectors internally and its memory tap never sees
		// it. Excluding it here keeps the two traces comparable; it is a
		// difference in what is OBSERVABLE, not in what happens.
		if (as_active & ~as_d & ~iack) begin   // one event per bus cycle
			tr_addr  <= a;
			tr_data  <= eRWn ? rdat : oEdb;
			tr_we    <= ~eRWn;
			tr_valid <= 1'b1;
		end
	end

	fx68k u_cpu (
		.clk(clk), .HALTn(1'b1), .extReset(reset), .pwrUp(reset),
		.enPhi1(enPhi1), .enPhi2(enPhi2),
		.eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn), .E(), .VMAn(VMAn),
		.FC0(FC0), .FC1(FC1), .FC2(FC2), .BGn(BGn),
		.oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
		// DTACK must NOT be asserted during an interrupt acknowledge: the
		// 68000 prefers it over VPA, which turns an AUTOVECTORED interrupt
		// into a vectored one and fetches vector 0 off an undriven bus.
		// MAME's set_input_line/HOLD_LINE is autovectored.
		.DTACKn(~(as_active & ~iack & ~rom_stall)), .VPAn(~iack), .BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
		.IPL0n(~ipl[0]), .IPL1n(~ipl[1]), .IPL2n(~ipl[2]),
		.iEdb(iEdb), .oEdb(oEdb), .eab(eab)
	);
endmodule
