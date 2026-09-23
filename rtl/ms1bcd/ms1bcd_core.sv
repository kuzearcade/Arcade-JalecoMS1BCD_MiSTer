// Jaleco Mega System 1 B/C/D core: the main-CPU subsystem and the video,
// with the raster that paces both.
//
// The raster is the board's clock in every sense that matters here: it drives
// the main CPU's scanline interrupts (level 1 at line 96, level 4 at line
// 240), the protection MCU's INT1 (the display-enable signal, high from line
// 16 to 239 -- docs/known-issues.md MS1-19), and the object/sprite buffer
// shift at the start of vblank.
//
// 384 x 278 at a 6 MHz pixel clock, visible 256 x 224 from row 16.

module ms1bcd_core #(
	// 0 = reference sim (ROMs served with no latency). 8 = SDRAM path, where
	// the tile fetch needs a head start on the cache; see ms1_video.sv.
	parameter integer LOOKAHEAD = 0
) (
	input               clk,           // 48 MHz
	input               reset,
	input        [1:0]  mode,          // 0 = B, 1 = C
	// .mra game-mode byte bits 6:5: 0 real MCU, 1 simulated, 2 none, 3 D's own.
	input        [1:0]  prot,

	output      [18:0]  rom_addr,
	input       [15:0]  rom_data,
	// HW_ROMS handshakes. The reference sim ties every *_ready high and every
	// *_stall low, which is timing-identical to the zero-latency arrays it
	// used before -- that equivalence is what M3's "frames identical to the
	// reference sim" gate rests on.
	input               rom_ready,

	output      [13:0]  mcu_rom_addr,
	input        [7:0]  mcu_rom_data,
	input               mcu_rom_ready,

	input        [7:0]  in_p1, in_p2, in_dsw1, in_dsw2, in_system,

	// tile and sprite ROM, served by the caller
	output      [20:0]  l0_rom_addr, l1_rom_addr, l2_rom_addr,
	output      [20:0]  l0_rom_use_addr, l1_rom_use_addr, l2_rom_use_addr,
	input        [7:0]  l0_rom_data, l1_rom_data, l2_rom_data,
	// The tile fetch cannot stall -- it is a raster -- so instead it is given
	// a head start (LOOKAHEAD) and the misses are COUNTED. docs/PLAN.md 4.B.3:
	// judge the video fetch with a miss measure, never with frame diffs.
	input               l0_rom_ready, l1_rom_ready, l2_rom_ready,
	output      [21:0]  spr_rom_addr,
	input        [7:0]  spr_rom_data,
	input               spr_rom_ready,
	output       [8:0]  prom_addr,
	input        [7:0]  prom_data,

	// sound ROMs, served by the caller
	output      [16:0]  srom_addr,
	input       [15:0]  srom_data,
	input               srom_ready,
	output      [17:0]  oki1_rom_addr, oki2_rom_addr,
	input        [7:0]  oki1_rom_data, oki2_rom_data,
	input               oki1_stall, oki2_stall,
	input               oki_status_real,
	output signed [15:0] snd_l, snd_r,
	output      [31:0]  dbg_ym_writes, dbg_oki1_writes, dbg_oki2_writes,
	output signed [15:0] dbg_fm_l, dbg_fm_r,
	output signed [13:0] dbg_oki1, dbg_oki2,

	output      [23:0]  rgb,
	output              rgb_valid,
	output              vblank_rise,
	output       [8:0]  vcount_o,
	output       [8:0]  hcount_o,
	output              ce_pix_o,   // one tick per pixel; a consumer MUST
	                                // sample rgb/rgb_valid on this, not on clk


	// probes for the frame harness
	output      [15:0]  dbg_active, dbg_t0c, dbg_t1c, dbg_t2c,
	output      [15:0]  dbg_t0x, dbg_t0y,
	output      [15:0]  dbg_t1x, dbg_t1y, dbg_t2x, dbg_t2y,
	output      [15:0]  dbg_sf, dbg_sb, dbg_scf,
	output      [31:0]  dbg_acc, dbg_vregw, dbg_vramw,
	output      [23:0]  tr_addr,
	output      [15:0]  tr_data,
	output              tr_we, tr_valid,
	output      [31:0]  dbg_irq2, dbg_int1e, dbg_mcuacc, dbg_mcubank,
	output      [15:0]  dbg_mcu_pc,
	output              dbg_mcu_halt, dbg_mcu_if,
	output      [10:0]  dbg_mcu_irqp, dbg_mcu_mask,
	// ---- savestate snapshot bus (see docs/m3-gate4.md for the image map)
	input               ss_freeze,
	input               ss_resume,
	input               ss_active,
	input       [19:0]  ss_addr,
	input               ss_wr,
	input       [15:0]  ss_wdata,
	output reg  [15:0]  ss_rdata,
	output              ss_frozen,
	output              ss_parked,
	input               ss_replay,
	output              ss_replay_done,
	// Bisection aid (debug only, tied 0 in any real build): pulse a reset at
	// one subsystem so it enters both spans of a round trip from the same
	// state. If that makes the divergence vanish, the state it holds is the
	// state the image is missing. Bit 0 sound, 1 MCU, 2 sprite engine.
	input        [3:0]  ss_rst_dbg,

	output      [31:0]  dbg_romwait, dbg_romacc,
	output reg  [31:0]  dbg_l0_miss, dbg_l1_miss, dbg_l2_miss, dbg_pix,
	// where in the frame the first layer-2 miss of each frame happened
	output reg  [15:0]  dbg_l2_first_v, dbg_l2_first_h,
	output      [31:0]  dbg_spr_pass_cycles,
	output      [15:0]  dbg_spr_late_swaps,
	output reg  [31:0]  dbg_palnz, dbg_opaque0, dbg_opaque2
);
	// The whole savestate window: park, stream, resume. Holding only during
	// ss_active left the raster free to advance while the CPU ran its park
	// monitor, and the monitor's exit is not cycle-identical between a save
	// and a restore -- so the game resumed at a different point in the frame
	// than it was saved at. See MS1-33.
	wire ss_hold = ss_freeze | ss_active | ss_resume;

	// ---------------------------------------------------------- raster
	reg [2:0] pdiv;
	reg [8:0] hcount, vcount;
	reg       ce_pix;
	// The savestate restore of these four lives HERE, not in a block of its
	// own: two always blocks driving the same register is a multiple driver,
	// which Verilator will resolve by block order and Quartus will refuse.
	always @(posedge clk) begin
		ce_pix <= 1'b0;
		if (reset) begin pdiv <= 3'd0; hcount <= 9'd0; vcount <= 9'd0; end
		else if (ss_hold & ~(ss_wr & ss_ras)) begin
			// Held for the whole window, not just the transfer.
			pdiv <= pdiv; hcount <= hcount; vcount <= vcount;
		end
		else if (ss_active & ss_wr & ss_ras) begin
			case (ss_addr[3:0])
				4'd0: begin hcount <= ss_wdata[12:4]; pdiv <= ss_wdata[3:1];
				            ce_pix <= ss_wdata[0]; end
				4'd1: vcount <= ss_wdata[8:0];
				default: ;
			endcase
		end
		else if (pdiv == 3'd7) begin
			pdiv <= 3'd0;
			ce_pix <= 1'b1;
			if (hcount == 9'd383) begin
				hcount <= 9'd0;
				vcount <= (vcount == 9'd277) ? 9'd0 : vcount + 9'd1;
			end else hcount <= hcount + 9'd1;
		end else pdiv <= pdiv + 3'd1;
	end
	assign vcount_o = vcount;
	assign hcount_o = hcount;
	assign ce_pix_o = ce_pix;

	wire vtick = ce_pix & (hcount == 9'd383);
	assign vblank_rise = vtick & (vcount == 9'd239);   // entering line 240

	wire visible = (hcount < 9'd256) && (vcount >= 9'd16) && (vcount < 9'd240);

	// ------------------------------------------------------ main CPU side
	wire [12:0] v0a, v1a, v2a;
	wire [15:0] v0d, v1d, v2d;
	wire  [9:0] pala;
	wire [15:0] pald;
	wire [11:0] obja, spra;
	wire [15:0] objd, sprd;
	wire [15:0] r_act, r_sf, r_sb, r_scf;
	wire [15:0] r0x, r0y, r0c, r1x, r1y, r1c, r2x, r2y, r2c;

	ms1_main u_main (
		.clk(clk), .reset(reset), .mode(mode), .prot(prot),
		.rom_addr(rom_addr), .rom_data(rom_data), .rom_ready(rom_ready),
		.ss_active(ss_active), .ss_addr(ss_addr), .ss_wr(ss_wr),
		.ss_wdata(ss_wdata), .ss_rdata(ss_main_rdata),
		.ss_rst_dbg(ss_rst_dbg[2:1]), .ss_hold(ss_hold),
		.ss_freeze(ss_freeze), .ss_resume(ss_resume),
		.ss_m68k_parked(ss_m68k_parked), .ss_mcu_frozen(ss_mcu_frozen),
		.mcu_rom_addr(mcu_rom_addr), .mcu_rom_data(mcu_rom_data),
		.mcu_rom_ready(mcu_rom_ready),
		.dbg_romwait(dbg_romwait), .dbg_romacc(dbg_romacc),
		.in_p1(in_p1), .in_p2(in_p2), .in_dsw1(in_dsw1),
		.in_dsw2(in_dsw2), .in_system(in_system),
		.vcount(vcount), .vtick(vtick),
		.tr_addr(tr_addr), .tr_data(tr_data), .tr_we(tr_we), .tr_valid(tr_valid),
		.v0_rd_addr(v0a), .v1_rd_addr(v1a), .v2_rd_addr(v2a),
		.v0_rd_data(v0d), .v1_rd_data(v1d), .v2_rd_data(v2d),
		.pal_rd_addr(pala), .pal_rd_data(pald),
		.vbl_rise(vblank_rise),
		.obj_rd_addr(obja), .obj_rd_data(objd),
		.spr_rd_addr(spra), .spr_rd_data(sprd),
		.reg_active_layers(r_act), .reg_sprite_flag(r_sf),
		.reg_sprite_bank(r_sb),    .reg_screen_flag(r_scf),
		.reg_t0_sx(r0x), .reg_t0_sy(r0y), .reg_t0_ctrl(r0c),
		.reg_t1_sx(r1x), .reg_t1_sy(r1y), .reg_t1_ctrl(r1c),
		.reg_t2_sx(r2x), .reg_t2_sy(r2y), .reg_t2_ctrl(r2c),
		.dbg_ramw_addr(), .dbg_ramw_data(), .dbg_ramw(),
		.slatch_we(slatch_we), .slatch_data(slatch_data),
		.dbg_acc(dbg_acc), .dbg_vregw(dbg_vregw), .dbg_vramw(dbg_vramw),
		.dbg_irq2(dbg_irq2), .dbg_int1e(dbg_int1e),
		.dbg_mcuacc(dbg_mcuacc), .dbg_mcubank(dbg_mcubank),
		.dbg_mcu_pc(dbg_mcu_pc), .dbg_mcu_halt(dbg_mcu_halt), .dbg_mcu_if(dbg_mcu_if),
		.dbg_mcu_irqp(dbg_mcu_irqp), .dbg_mcu_mask(dbg_mcu_mask)
	);

	assign dbg_active = r_act;
	assign dbg_t0c = r0c;
	assign dbg_t1c = r1c;
	assign dbg_t2c = r2c;
	assign dbg_t0x = r0x;
	assign dbg_t0y = r0y;
	assign dbg_t1x = r1x;  assign dbg_t1y = r1y;
	assign dbg_t2x = r2x;  assign dbg_t2y = r2y;
	assign dbg_sf = r_sf;  assign dbg_sb = r_sb;  assign dbg_scf = r_scf;

	// The sprite pass runs once a frame, started just after the buffers are
	// shifted so it draws the frame the hardware would show next.
	reg spr_start;
	always @(posedge clk) spr_start <= vblank_rise;

	// count non-black pixels actually emitted, plus per-layer opacity: tells
	// a black screen caused by "nothing opaque" from one caused by "every
	// opaque pixel maps to palette entry 0".
	always @(posedge clk) begin
		if (reset) begin dbg_palnz <= 0; dbg_opaque0 <= 0; dbg_opaque2 <= 0; end
		else if (ce_pix) begin
			if (rgb_valid && rgb != 24'd0) dbg_palnz <= dbg_palnz + 1;
			if (vid_o0) dbg_opaque0 <= dbg_opaque0 + 1;
			if (vid_o2) dbg_opaque2 <= dbg_opaque2 + 1;
		end
	end

	// ---- sound subsystem. The main CPU's latch write is the only signal
	// that crosses: it carries the command and raises the sound CPU's
	// interrupt (level 4 on System B, level 2 on System C).
	wire        slatch_we;
	wire [15:0] slatch_data;

	ms1_sound u_sound (
		.clk(clk), .reset(reset), .mode(mode),
		.sreset(r_scf[4] | ss_rst_dbg[0]),   // + the bisection aid
		.oki_status_real(oki_status_real),
		.ss_active(ss_active), .ss_addr(ss_addr), .ss_wr(ss_wr),
		.ss_wdata(ss_wdata), .ss_rdata(ss_snd_rdata),
		.ss_freeze(ss_freeze), .ss_resume(ss_resume), .ss_hold(ss_hold),
		.ss_parked(ss_snd_parked),
		.ss_replay(ss_replay), .ss_replay_done(ss_replay_done),
		.latch_we(slatch_we), .latch_data(slatch_data), .latch_to_main(),
		.rom_addr(srom_addr), .rom_data(srom_data), .rom_ready(srom_ready),
		.oki1_stall(oki1_stall), .oki2_stall(oki2_stall),
		.oki1_rom_addr(oki1_rom_addr), .oki2_rom_addr(oki2_rom_addr),
		.oki1_rom_data(oki1_rom_data), .oki2_rom_data(oki2_rom_data),
		.snd_l(snd_l), .snd_r(snd_r),
		.dbg_ym_writes(dbg_ym_writes),
		.dbg_oki1_writes(dbg_oki1_writes), .dbg_oki2_writes(dbg_oki2_writes),
		.dbg_fm_l(dbg_fm_l), .dbg_fm_r(dbg_fm_r),
		.dbg_oki1(dbg_oki1), .dbg_oki2(dbg_oki2)
	);

	reg l2_seen;
	wire vbl_rise_i = vblank_rise;
	wire vis_pix = (vcount >= 9'd16) & (vcount < 9'd240) & (hcount < 9'd256);

	// Every CPU parked, and the readback merged. The sound half owns
	// 0x10000-0x17FFF and 0x1D02x/0x1D03x/0x1E0xx; everything else is the
	// main half's, which includes the MCU's own window at 0x1C000.
	wire [15:0] ss_main_rdata, ss_snd_rdata, ss_spr_rdata;
	wire        vid_o0, vid_o2;
	wire        ss_m68k_parked, ss_mcu_frozen, ss_snd_parked;
	assign ss_frozen = ss_m68k_parked & ss_mcu_frozen & ss_snd_parked;
	assign ss_parked = ss_m68k_parked | ss_snd_parked;
	// ---- the raster is core state too. Without it the CPU comes back at a
	// different point in the frame than it was saved at, and every frame after
	// the restore is drawn against a different scan position -- which is what
	// the first round-trip attempt failed on.
	reg [15:0] ss_ras_rdata;
	wire ss_ras = ss_active & (ss_addr[19:4] == 16'h1D04);
	always @* begin
		case (ss_addr[3:0])
			4'd0: ss_ras_rdata = {4'd0, hcount[8:0], pdiv, 1'b0} | {15'd0, ce_pix};
			4'd1: ss_ras_rdata = {7'd0, vcount};
			default: ss_ras_rdata = 16'h0000;
		endcase
	end
	wire ss_plane_sel = (ss_addr[19:16] == 4'h2);
	wire ss_from_snd = (ss_addr[19:15] == 5'h02)      // sound RAM
	                 | (ss_addr[19:8]  == 12'h1E0)    // YM shadow
	                 | (ss_addr[19:4]  == 16'h1D02)   // sound scalars
	                 | (ss_addr[19:4]  == 16'h1D03);  // sound park registers
	reg ss_from_snd_d, ss_plane_d, ss_ras_d;
	reg [15:0] ss_ras_d_data;
	always @(posedge clk) begin
		ss_from_snd_d <= ss_from_snd;
		ss_plane_d    <= ss_plane_sel;
		ss_ras_d      <= ss_ras;
		ss_ras_d_data <= ss_ras_rdata;
	end
	always @(posedge clk)
		ss_rdata <= ss_ras_d      ? ss_ras_d_data
		          : ss_plane_d    ? ss_spr_rdata
		          : ss_from_snd_d ? ss_snd_rdata
		                          : ss_main_rdata;

	always @(posedge clk) begin
		if (reset) begin
			dbg_l0_miss <= 0; dbg_l1_miss <= 0; dbg_l2_miss <= 0; dbg_pix <= 0;
			l2_seen <= 1'b0; dbg_l2_first_v <= 0; dbg_l2_first_h <= 0;
		end else begin
			if (vbl_rise_i) l2_seen <= 1'b0;
			// Count ONLY pixels that reach the screen. The fetch also runs
			// through blanking, where a miss paints nothing -- counting those
			// made a working video path look broken (21 phantom misses a
			// frame, all of them at v=255).
			if (ce_pix & vis_pix) begin
				dbg_pix <= dbg_pix + 32'd1;
				if (!l0_rom_ready) dbg_l0_miss <= dbg_l0_miss + 32'd1;
				if (!l1_rom_ready) dbg_l1_miss <= dbg_l1_miss + 32'd1;
				if (!l2_rom_ready) begin
					dbg_l2_miss <= dbg_l2_miss + 32'd1;
					if (!l2_seen) begin
						l2_seen <= 1'b1;
						dbg_l2_first_v <= {7'd0, vcount};
						dbg_l2_first_h <= {7'd0, hcount};
					end
				end
			end
		end
	end

	ms1_video #(.LOOKAHEAD(LOOKAHEAD)) u_video (
		.clk(clk), .ce(ce_pix), .reset(reset),
		.mode(mode), .nlayers(2'd3),
		.active_layers(r_act), .sprite_flag(r_sf),
		.sprite_bank(r_sb), .screen_flag(r_scf),
		.t0_sx(r0x), .t0_sy(r0y), .t0_ctrl(r0c),
		.t1_sx(r1x), .t1_sy(r1y), .t1_ctrl(r1c),
		.t2_sx(r2x), .t2_sy(r2y), .t2_ctrl(r2c),
		.vx(hcount), .vy(vcount - 9'd16), .vvalid(visible),
		.l0_vram_addr(v0a), .l1_vram_addr(v1a), .l2_vram_addr(v2a),
		.l0_vram_data(v0d), .l1_vram_data(v1d), .l2_vram_data(v2d),
		.l0_rom_addr(l0_rom_addr), .l1_rom_addr(l1_rom_addr), .l2_rom_addr(l2_rom_addr),
		.l0_rom_use_addr(l0_rom_use_addr), .l1_rom_use_addr(l1_rom_use_addr),
		.l2_rom_use_addr(l2_rom_use_addr),
		.l0_rom_data(l0_rom_data), .l1_rom_data(l1_rom_data), .l2_rom_data(l2_rom_data),
		.spr_start(spr_start), .spr_busy(),
		.obj_addr(obja), .spr_ram_addr(spra),
		.obj_data(objd), .spr_ram_data(sprd),
		.spr_rom_addr(spr_rom_addr), .spr_rom_data(spr_rom_data),
		.spr_rom_ready(spr_rom_ready),
		.ss_rst_dbg(ss_rst_dbg[2]),
		.dbg_o0(vid_o0), .dbg_o2(vid_o2),
		.ss_active(ss_active), .ss_addr(ss_addr), .ss_wr(ss_wr),
		.ss_wdata(ss_wdata), .ss_spr_rdata(ss_spr_rdata),
		.dbg_spr_pass_cycles(dbg_spr_pass_cycles), .dbg_spr_late_swaps(dbg_spr_late_swaps),
		.prom_addr(prom_addr), .prom_data(prom_data),
		.pal_addr(pala), .pal_data(pald),
		.rgb(rgb), .rgb_valid(rgb_valid)
	);
endmodule
