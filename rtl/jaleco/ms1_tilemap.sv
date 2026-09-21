// Jaleco Mega System 1 scrolling layer.
//
// One of the three (two in System D) tilemap layers. The behaviour is taken
// from MAME's jaleco/ms1_tmap.cpp and verified pixel-exact against MAME by
// tools/ms1_video_model.py, which is the executable spec this mirrors.
//
//   control register (offset 04 of the layer's scroll registers):
//     bit 4     0 = 16x16 tiles, 1 = 8x8 tiles
//     bits 1:0  N, layer H pages = 16 >> N
//
// Everything is fetched as 8x8 tiles of 4bpp packed-MSB data (32 bytes each).
// A 16x16 tile is FOUR 8x8 tiles in COLUMN order -- (row&1) + (col&1)*2, so
// sub-tiles 0,1 are the left column top/bottom and 2,3 the right column. That
// ordering is the same one the sprite ROM uses, and getting it wrong is a
// silent quarter-tile scramble rather than an obvious break.
//
// The screen flip bit is NOT handled here. It is a 180-degree rotation of the
// finished frame (docs/known-issues.md MS1-13), applied once in ms1_video.sv,
// rather than mirrored into every layer's source coordinates.
//
// Three-stage pipeline, one pixel per `ce`:
//   stage 0  issue the VRAM word address for the tile under (sx, sy)
//   stage 1  VRAM word valid -> tile number and colour -> issue the ROM byte
//   stage 2  ROM byte valid  -> select the nibble -> pen out
// `pen_valid` follows the same three stages so the consumer never has to
// count clocks itself.

module ms1_tilemap #(
	// Extra pixels between issuing the ROM address and consuming the byte.
	// 0 is the original pipeline and the reference sim. On the SDRAM path the
	// byte comes from a cache and one pixel (8 clocks at 48 MHz) is not enough
	// for a miss, so the address is issued FETCH_LEAD pixels earlier and
	// everything that travels with it is delayed to match. Simply moving the
	// sample point does NOT help: it shifts the whole pipeline, address and
	// use together, and the cache still gets one pixel.
	parameter integer FETCH_LEAD = 0
) (
	input               clk,
	input               ce,            // one tick per pixel

	// where to sample, in BITMAP coordinates (visible rows start at 16)
	input        [8:0]  sx,
	input        [8:0]  sy,

	// layer registers
	input       [15:0]  scroll_x,
	input       [15:0]  scroll_y,
	input       [15:0]  ctrl,

	// VRAM: 0x4000 bytes = 8192 words, word addressed
	output reg  [12:0]  vram_addr,
	input       [15:0]  vram_data,

	// tile ROM: byte addressed, 32 bytes per 8x8 tile
	output reg  [20:0]  rom_addr,      // live: what to PREFETCH
	output      [20:0]  rom_use_addr,  // delayed: what to READ this pixel
	input        [7:0]  rom_data,

	output reg   [3:0]  pen,
	output reg   [3:0]  color,
	output reg          opaque,        // pen != 15
	output reg          pen_valid
);
	wire        eight = ctrl[4];
	wire  [1:0] npages = ctrl[1:0];

	// Tilemap size in 8x8 tiles. TILES_PER_PAGE_X/Y are both 0x20, and the
	// multipliers come straight from the eight tilemap_create() calls in
	// ms1_tmap.cpp. Note 8x8 N=1 and N=2 are the SAME shape upstream; that is
	// not a typo here, it is a duplicate in MAME.
	reg [9:0] ncols, nrows;
	always @* begin
		if (eight) begin
			case (npages)
				2'd0: begin ncols = 10'd256; nrows = 10'd32;  end  // 8 x 1 pages
				2'd1: begin ncols = 10'd128; nrows = 10'd64;  end  // 4 x 2
				2'd2: begin ncols = 10'd128; nrows = 10'd64;  end  // 4 x 2 (same)
				2'd3: begin ncols = 10'd64;  nrows = 10'd128; end  // 2 x 4
			endcase
		end else begin
			case (npages)
				2'd0: begin ncols = 10'd512; nrows = 10'd64;  end  // 16 x 2 pages
				2'd1: begin ncols = 10'd256; nrows = 10'd128; end  // 8 x 4
				2'd2: begin ncols = 10'd128; nrows = 10'd256; end  // 4 x 8
				2'd3: begin ncols = 10'd64;  nrows = 10'd512; end  // 2 x 16
			endcase
		end
	end

	// Source coordinate inside the map, wrapped. ncols/nrows are powers of two
	// in every case above, so the wrap is a mask and not a modulo.
	wire [12:0] map_w_mask = {ncols, 3'b000} - 13'd1;
	wire [12:0] map_h_mask = {nrows, 3'b000} - 13'd1;
	wire [12:0] tx = ({4'd0, sx} + scroll_x[12:0]) & map_w_mask;
	wire [12:0] ty = ({4'd0, sy} + scroll_y[12:0]) & map_h_mask;

	wire  [9:0] col = tx[12:3];
	wire  [9:0] row = ty[12:3];
	wire  [2:0] fx  = tx[2:0];
	wire  [2:0] fy  = ty[2:0];

	// scan_8x8 / scan_16x16 from ms1_tmap.cpp. TILES_PER_PAGE_Y = 0x20,
	// TILES_PER_PAGE = 0x400, so the divisions are shifts.
	// Tile index inside VRAM. Worst cases: 8x8 maps hold 8192 tiles and 16x16
	// maps 32768 sub-tiles, so the intermediates are carried at 22 bits and
	// narrowed only at the end. Every divisor and multiplier below is a power
	// of two, so these all synthesise to shifts.
	wire [21:0] w_col    = {12'd0, col};
	wire [21:0] w_row    = {12'd0, row};
	wire [21:0] w_pagesx = {17'd0, ncols[9:5]};        // ncols / 32, 2..16

	// scan_8x8:  col*32 + (row/32)*1024*pages_x + (row%32)
	wire [21:0] scan8  = (w_col << 5)
	                   + (((w_row >> 5) * w_pagesx) << 10)
	                   + (w_row & 22'd31);

	// scan_16x16: ((col/2)*16 + ((row/2)/16)*256*pages_x + ((row/2)%16))*4
	//             + (row&1) + (col&1)*2
	wire [21:0] scan16 = ((((w_col >> 1) << 4)
	                     + (((w_row >> 5) * w_pagesx) << 8)
	                     + ((w_row >> 1) & 22'd15)) << 2)
	                   + (w_row & 22'd1)
	                   + ((w_col & 22'd1) << 1);

	wire [21:0] tindex = eight ? scan8 : scan16;
	wire [12:0] vcell  = eight ? tindex[12:0] : tindex[14:2];

	// ---- stage 0: address VRAM
	reg [2:0] fx0, fy0;
	reg [1:0] sub0;
	reg       eight0, v0;
	always @(posedge clk) if (ce) begin
		vram_addr <= vcell;
		fx0 <= fx; fy0 <= fy;
		sub0 <= tindex[1:0];
		eight0 <= eight;
		v0 <= 1'b1;
	end

	// tile number -> byte base. Declared outside the block so the widths
	// are visible; `eight0`/`sub0` are the stage-0 copies.
	wire [21:0] w_code  = {10'd0, vram_data[11:0]};
	wire [21:0] w_tile  = eight0 ? w_code : ((w_code << 2) + {20'd0, sub0});
	wire [21:0] w_tilebase = w_tile << 5;

	// ---- stage 1: VRAM word -> tile number, colour -> address the ROM
	reg       fx1;
	reg [3:0] color1;
	reg       v1;
	always @(posedge clk) if (ce) begin
		// 16x16: tile = (code & 0xfff)*4 + sub; 8x8: tile = code & 0xfff
		// 16x16: tile = (code & 0xfff)*4 + sub. 8x8: tile = code & 0xfff.
		// 32 bytes per 8x8 tile, 4 bytes per row, 2 pixels per byte.
		rom_addr <= w_tilebase[20:0] + {18'd0, fy0, 2'd0}[20:0] + {20'd0, fx0[2:1]}[20:0];
		color1 <= vram_data[15:12];
		fx1 <= fx0[0];
		v1 <= v0;
	end

	// ---- the FETCH_LEAD gap: hold everything that travels with the address
	// until the byte for that address is the one being read.
	wire       fx1d;
	wire [3:0] color1d;
	wire       v1d;
	generate
		if (FETCH_LEAD == 0) begin : g_nolead
			assign fx1d = fx1; assign color1d = color1; assign v1d = v1;
			assign rom_use_addr = rom_addr;
		end else begin : g_lead
			reg [5:0]  pl [0:FETCH_LEAD-1];   // {v, colour, fx}
			reg [20:0] al [0:FETCH_LEAD-1];
			integer k;
			always @(posedge clk) if (ce) begin
				pl[0] <= {v1, color1, fx1};
				al[0] <= rom_addr;
				for (k = 1; k < FETCH_LEAD; k = k + 1) begin
					pl[k] <= pl[k-1];
					al[k] <= al[k-1];
				end
			end
			assign {v1d, color1d, fx1d} = pl[FETCH_LEAD-1];
			assign rom_use_addr = al[FETCH_LEAD-1];
		end
	endgenerate

	// ---- stage 2: ROM byte -> nibble. packed MSB: even x is the high nibble.
	always @(posedge clk) if (ce) begin
		pen       <= fx1d ? rom_data[3:0] : rom_data[7:4];
		color     <= color1d;
		opaque    <= (fx1d ? rom_data[3:0] : rom_data[7:4]) != 4'hF;
		pen_valid <= v1d;
	end
endmodule
