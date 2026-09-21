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

module ms1bcd_core (
	input               clk,           // 48 MHz
	input               reset,
	input        [1:0]  mode,          // 0 = B, 1 = C

	output      [18:0]  rom_addr,
	input       [15:0]  rom_data,

	input               mcu_rom_we,
	input       [13:0]  mcu_rom_addr,
	input        [7:0]  mcu_rom_data,

	input        [7:0]  in_p1, in_p2, in_dsw1, in_dsw2, in_system,

	// tile and sprite ROM, served by the caller
	output      [20:0]  l0_rom_addr, l1_rom_addr, l2_rom_addr,
	input        [7:0]  l0_rom_data, l1_rom_data, l2_rom_data,
	output      [21:0]  spr_rom_addr,
	input        [7:0]  spr_rom_data,
	output       [8:0]  prom_addr,
	input        [7:0]  prom_data,

	output      [23:0]  rgb,
	output              rgb_valid,
	output              vblank_rise,
	output       [8:0]  vcount_o,
	output       [8:0]  hcount_o,

	// probes for the frame harness
	output      [15:0]  dbg_active, dbg_t0c, dbg_t1c, dbg_t2c,
	output      [15:0]  dbg_t0x, dbg_t0y,
	output      [15:0]  dbg_t1x, dbg_t1y, dbg_t2x, dbg_t2y,
	output      [15:0]  dbg_sf, dbg_sb, dbg_scf,
	output      [31:0]  dbg_acc, dbg_vregw, dbg_vramw,
	output      [23:0]  tr_addr,
	output      [15:0]  tr_data,
	output              tr_we, tr_valid,
	output      [31:0]  dbg_irq2, dbg_int1e, dbg_mcuacc, dbg_mcubank
);
	// ---------------------------------------------------------- raster
	reg [2:0] pdiv;
	reg [8:0] hcount, vcount;
	reg       ce_pix;
	always @(posedge clk) begin
		ce_pix <= 1'b0;
		if (reset) begin pdiv <= 3'd0; hcount <= 9'd0; vcount <= 9'd0; end
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
		.clk(clk), .reset(reset), .mode(mode),
		.rom_addr(rom_addr), .rom_data(rom_data),
		.mcu_rom_we(mcu_rom_we), .mcu_rom_addr(mcu_rom_addr), .mcu_rom_data(mcu_rom_data),
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
		.dbg_acc(dbg_acc), .dbg_vregw(dbg_vregw), .dbg_vramw(dbg_vramw),
		.dbg_irq2(dbg_irq2), .dbg_int1e(dbg_int1e),
		.dbg_mcuacc(dbg_mcuacc), .dbg_mcubank(dbg_mcubank)
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

	ms1_video u_video (
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
		.l0_rom_data(l0_rom_data), .l1_rom_data(l1_rom_data), .l2_rom_data(l2_rom_data),
		.spr_start(spr_start), .spr_busy(),
		.obj_addr(obja), .spr_ram_addr(spra),
		.obj_data(objd), .spr_ram_data(sprd),
		.spr_rom_addr(spr_rom_addr), .spr_rom_data(spr_rom_data),
		.prom_addr(prom_addr), .prom_data(prom_data),
		.pal_addr(pala), .pal_data(pald),
		.rgb(rgb), .rgb_valid(rgb_valid)
	);
endmodule
