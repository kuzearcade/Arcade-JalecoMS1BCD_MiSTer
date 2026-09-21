// Jaleco Mega System 1 video top: three tilemap layers (two in System D),
// the sprite plane, the priority PROM and the palette.
//
// Pixels are produced one per `ce`, in a fixed pipeline so a consumer never
// has to count clocks:
//
//   tick i     sample point issued to the tilemaps and the sprite plane
//   tick i+1   tilemaps address their ROMs; the sprite pixel advances
//   tick i+2   tilemap pens land, aligned with the sprite pixel
//   tick i+3   priority PROM decides the winner; pens wait a stage for it
//   tick i+4   palette word -> rgb, with rgb_valid
//
// So the total latency is FOUR ticks, and a consumer collecting pixel i must
// read it after tick i+4. Getting that count wrong is not a visible break --
// it is a one-pixel horizontal shift that looks like a subtle addressing bug
// in whichever block you happen to suspect.
//
// SCREEN FLIP is a 180-degree rotation of the finished visible frame
// (docs/known-issues.md MS1-13), so it is applied here by mirroring the
// SAMPLE POINT rather than by flipping each layer and each sprite the way
// MAME does. That is not an assumption: MAME was captured twice from the same
// point, flipped and not, and the two frames are rot180 of each other with
// zero differing pixels. The visible window is symmetric about the bitmap
// centre (rows 16..239 of 256, columns 0..255), which is why it holds.
//
// The palette bit layout differs by MODE, and MAME's own header comment about
// it is wrong. B and C use RRRRGGGGBBBBRGBx, so bits 11:8 are GREEN and 7:4
// are BLUE -- the comment says the opposite. System D does not use that format
// at all; it is plain RGBx_555. Both are below.

module ms1_video #(
	parameter integer VIS_W = 256,
	parameter integer VIS_H = 224,
	parameter integer VIS_Y0 = 16      // first visible bitmap row
) (
	input               clk,
	input               ce,
	input               reset,

	input        [1:0]  mode,          // 0 = B, 1 = C, 2 = D
	input        [1:0]  nlayers,       // 3 for B/C, 2 for D

	// video registers
	input       [15:0]  active_layers,
	input       [15:0]  sprite_flag,
	input       [15:0]  sprite_bank,
	input       [15:0]  screen_flag,
	input       [15:0]  t0_sx, t0_sy, t0_ctrl,
	input       [15:0]  t1_sx, t1_sy, t1_ctrl,
	input       [15:0]  t2_sx, t2_sy, t2_ctrl,

	// where to sample, in VISIBLE coordinates
	input        [8:0]  vx,
	input        [8:0]  vy,
	input               vvalid,

	// layer VRAM and tile ROM
	output      [12:0]  l0_vram_addr, l1_vram_addr, l2_vram_addr,
	input       [15:0]  l0_vram_data, l1_vram_data, l2_vram_data,
	output      [20:0]  l0_rom_addr,  l1_rom_addr,  l2_rom_addr,
	input        [7:0]  l0_rom_data,  l1_rom_data,  l2_rom_data,

	// sprite engine ports
	input               spr_start,
	output              spr_busy,
	output      [11:0]  obj_addr, spr_ram_addr,
	input       [15:0]  obj_data, spr_ram_data,
	output      [21:0]  spr_rom_addr,
	input        [7:0]  spr_rom_data,

	// priority PROM and palette, both loaded from the .mra, never baked in
	output       [8:0]  prom_addr,
	input        [7:0]  prom_data,
	output      [9:0]   pal_addr,
	input       [15:0]  pal_data,

	output reg  [23:0]  rgb,
	output reg          rgb_valid
);
	// ---- flip: mirror the sample point over the visible window
	wire flip = screen_flag[0];
	wire [8:0] mx = flip ? (VIS_W[8:0] - 9'd1 - vx) : vx;
	wire [8:0] my = flip ? (VIS_H[8:0] - 9'd1 - vy) : vy;
	wire [8:0] bx = mx;                           // bitmap x
	wire [8:0] by = my + VIS_Y0[8:0];             // bitmap y

	// ---- three tilemap layers
	wire [3:0] p0, p1, p2, c0, c1, c2;
	wire       o0, o1, o2, v0;

	ms1_tilemap u_l0 (.clk(clk), .ce(ce), .sx(bx), .sy(by),
		.scroll_x(t0_sx), .scroll_y(t0_sy), .ctrl(t0_ctrl),
		.vram_addr(l0_vram_addr), .vram_data(l0_vram_data),
		.rom_addr(l0_rom_addr), .rom_data(l0_rom_data),
		.pen(p0), .color(c0), .opaque(o0), .pen_valid(v0));

	ms1_tilemap u_l1 (.clk(clk), .ce(ce), .sx(bx), .sy(by),
		.scroll_x(t1_sx), .scroll_y(t1_sy), .ctrl(t1_ctrl),
		.vram_addr(l1_vram_addr), .vram_data(l1_vram_data),
		.rom_addr(l1_rom_addr), .rom_data(l1_rom_data),
		.pen(p1), .color(c1), .opaque(o1), .pen_valid());

	ms1_tilemap u_l2 (.clk(clk), .ce(ce), .sx(bx), .sy(by),
		.scroll_x(t2_sx), .scroll_y(t2_sy), .ctrl(t2_ctrl),
		.vram_addr(l2_vram_addr), .vram_data(l2_vram_data),
		.rom_addr(l2_rom_addr), .rom_data(l2_rom_data),
		.pen(p2), .color(c2), .opaque(o2), .pen_valid());

	// ---- sprite plane. Its readback is one cycle, the tilemaps are three,
	// so the sprite pixel is delayed two stages to meet them.
	wire [8:0] fb_q;
	ms1_sprites u_spr (.clk(clk), .reset(reset),
		.start(spr_start), .busy(spr_busy),
		.sprite_flag(sprite_flag), .sprite_bank(sprite_bank),
		.obj_addr(obj_addr), .obj_data(obj_data),
		.spr_addr(spr_ram_addr), .spr_data(spr_ram_data),
		.rom_addr(spr_rom_addr), .rom_data(spr_rom_data),
		.fb_rd_addr({by[7:0], bx[7:0]}), .fb_rd_data(fb_q));

	reg [8:0] fb_d1, fb_d2;
	always @(posedge clk) if (ce) begin fb_d1 <= fb_q; fb_d2 <= fb_d1; end

	// ---- priority. The enables come from active_layers; layer 2 does not
	// exist in mode D and is forced transparent there.
	wire l2_exists = (nlayers == 2'd3);
	wire e0 = active_layers[0];
	wire e1 = active_layers[1];
	wire e2 = active_layers[2] & l2_exists;
	wire espr = active_layers[3];

	wire spr_present = espr & (fb_d2[3:0] != 4'hF);
	// The PROM's bit 0 is "low priority sprite AND splitting". Measured
	// against MAME on bigstrik's split scenes: the low group is the one
	// whose attribute bit 3 is SET, not clear. Inverting this is invisible
	// on every scene that has no sprites or no splitting, and wrong on
	// 25205 of 57344 pixels on one that has both.
	wire spr_lowpri  = fb_d2[8];

	wire [1:0] win;
	ms1_prio u_prio (.clk(clk), .ce(ce),
		.pri_code(active_layers[11:8]), .split(sprite_flag[8]),
		.l0_opaque(o0 & e0), .l1_opaque(o1 & e1), .l2_opaque(o2 & e2),
		.spr_present(spr_present), .spr_lowpri(spr_lowpri),
		.prom_addr(prom_addr), .prom_data(prom_data), .win(win));

	// the pens have to wait one stage for the PROM result
	reg [3:0] p0d, p1d, p2d, c0d, c1d, c2d;
	reg [8:0] fb_d3;
	// vvalid follows the pixel through the four stages between being sampled
	// and emerging as rgb: tilemap pen (2), priority (3), palette+rgb (4).
	reg [3:0] vpipe;
	always @(posedge clk) if (ce) begin
		p0d <= p0; p1d <= p1; p2d <= p2;
		c0d <= c0; c1d <= c1; c2d <= c2;
		fb_d3 <= fb_d2;
		vpipe <= {vpipe[2:0], vvalid};
	end

	// ---- palette index. 256 entries per layer group, sprites at 256*3.
	reg [9:0] pal_idx;
	always @* begin
		case (win)
			2'd0: pal_idx = {2'd0, c0d, p0d};
			2'd1: pal_idx = {2'd1, c1d, p1d};
			2'd2: pal_idx = {2'd2, c2d, p2d};
			2'd3: pal_idx = {2'd3, fb_d3[7:0]};
		endcase
	end
	assign pal_addr = pal_idx;

	// ---- palette word -> rgb. pal5bit(v) = (v<<3)|(v>>2).
	function automatic [7:0] pal5 (input [4:0] v);
		pal5 = {v, v[4:2]};
	endfunction

	wire [4:0] r_bc = {pal_data[15:12], pal_data[3]};
	wire [4:0] g_bc = {pal_data[11:8],  pal_data[2]};
	wire [4:0] b_bc = {pal_data[7:4],   pal_data[1]};
	wire [4:0] r_d  = pal_data[15:11];
	wire [4:0] g_d  = pal_data[10:6];
	wire [4:0] b_d  = pal_data[5:1];

	always @(posedge clk) if (ce) begin
		rgb <= (mode == 2'd2) ? {pal5(r_d),  pal5(g_d),  pal5(b_d)}
		                      : {pal5(r_bc), pal5(g_bc), pal5(b_bc)};
		rgb_valid <= vpipe[3];
	end
endmodule
