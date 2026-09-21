// Jaleco Mega System 1 sprite engine.
//
// Sprites are placed INDIRECTLY. Object RAM holds 4 banks of 256 eight-byte
// entries; each points at one of 128 sixteen-byte Sprite Data entries and adds
// displacements to it:
//
//   Object RAM   00 index into Sprite Data (masked to 0x7f)
//                02 H displacement   04 V displacement   06 number displacement
//
//   Sprite Data  08 bit 12 mosaic solid, bits 11:8 mosaic, bit 7 y flip,
//                   bit 6 x flip, bits 3:0 colour (bit 3 = priority)
//                0A H position   0C V position   0E tile number
//
// Which of the four Object RAM banks an entry belongs to is decided by the
// SPRITE's own flip bits: the entry is skipped unless attr[7:6] equals the
// bank index, so exactly one bank ever matches a given sprite.
//
// Order: MAME walks Object RAM DESCENDING (0x3fc down to 0, step 4) and the
// framebuffer write is FIRST-WRITER-WINS. That makes the LAST entry frontmost,
// which contradicts megasys1_v.cpp's own comment ("From first in Object RAM
// (frontmost) to last") and the note carried into docs/PLAN.md 4.D item 8.
// The CODE is mirrored here, because the code is what produced the oracle
// frames. No captured scene distinguishes the two orders, so this is recorded
// as unproven rather than settled -- docs/known-issues.md MS1-16.
//
// Screen flip is NOT applied here; it is a rotation of the finished frame in
// ms1_video.sv (docs/known-issues.md MS1-13).
//
// The framebuffer is one 256x256 plane of 9 bits {priority, colour, pen}, pen
// 15 meaning empty -- the same encoding MAME's 0x7fff fill uses. It is NOT
// double buffered: sprite_flag bit 4 ("do not clear the sprite framebuffer")
// deliberately lets the previous frame survive, which a swap would destroy.
//
// Memories are read COMBINATIONALLY (data valid the cycle after the address
// register updates), the convention the rest of this project's sims use.
// The plane needs 2R1W: port A is the engine's read-modify-write, port B is
// the display readback.

module ms1_sprites (
	input               clk,
	input               reset,

	input               start,          // one pulse begins a pass
	output reg          busy,

	input       [15:0]  sprite_flag,
	input       [15:0]  sprite_bank,

	output reg  [11:0]  obj_addr,       // Object RAM, 4096 words
	input       [15:0]  obj_data,

	output reg  [11:0]  spr_addr,       // Sprite Data RAM, 4096 words
	input       [15:0]  spr_data,

	output reg  [21:0]  rom_addr,       // sprite ROM, 128 bytes per 16x16 tile
	input        [7:0]  rom_data,

	// Display readback. rd_ce must be the PIXEL enable, not the system
	// clock: the consumer's pipeline advances one stage per pixel, and a
	// readback that updates every clk instead runs ahead of it by however
	// many clocks there are per pixel. That is invisible when ce is tied
	// high (as in sim/rtl/video_state) and wrong as soon as it is not.
	input               rd_ce,
	input       [15:0]  fb_rd_addr,     // {y[7:0], x[7:0]}
	output reg   [8:0]  fb_rd_data      // {pri, colour[3:0], pen[3:0]}
);
	// ---------------------------------------------------------------- plane
	reg [8:0]  plane [0:65535];
	reg [15:0] eng_addr;
	wire [8:0] eng_q = plane[eng_addr];      // port A read
	reg [15:0] fb_wr_addr;
	reg  [8:0] fb_wr_data;
	reg        fb_we;

	always @(posedge clk) begin
		if (fb_we) plane[fb_wr_addr] <= fb_wr_data;
		if (rd_ce) fb_rd_data <= plane[fb_rd_addr];   // port B read
	end

	// ------------------------------------------------------------- sequencer
	localparam [4:0] S_IDLE = 5'd0,  S_CLEAR = 5'd1,
	                 S_O0   = 5'd2,  S_O1  = 5'd3,  S_O2 = 5'd4,  S_O3 = 5'd5,
	                 S_O4   = 5'd6,
	                 S_S0   = 5'd7,  S_S1  = 5'd8,  S_S2 = 5'd9,  S_S3 = 5'd10,
	                 S_DEC  = 5'd11, S_BA  = 5'd12, S_BB = 5'd13, S_NEXT = 5'd14;

	reg [4:0]  st;
	reg [16:0] clr;
	reg [7:0]  offs;          // object entry index, counts DOWN 255..0
	reg [1:0]  bank;
	reg [11:0] sbase;

	reg [15:0] o_idx, o_dx, o_dy, o_dn;
	reg [15:0] s_attr, s_x, s_y, s_code;

	reg signed [10:0] sx, sy;
	reg  [3:0] scol;
	reg        sflipx, sflipy, spri;
	reg  [3:0] mosaic;
	reg        mossol;
	reg [12:0] tile;
	reg  [3:0] bx, by;

	wire       split_on   = sprite_flag[8];
	wire [3:0] color_mask = split_on ? 4'h7 : 4'hF;
	wire       no_clear   = sprite_flag[4];

	wire [8:0] sum_x = s_x[8:0] + o_dx[8:0];
	wire [8:0] sum_y = s_y[8:0] + o_dy[8:0];

	// source pixel inside the tile, with flip and MAME's mosaic filter
	wire [3:0] srcx = bx ^ {4{sflipx}};
	wire [3:0] srcy = by ^ {4{sflipy}};
	wire [3:0] gx   = mossol ? (srcx | mosaic) : (srcx & ~mosaic);
	wire [3:0] gy   = mossol ? (srcy | mosaic) : (srcy & ~mosaic);

	// 128 bytes per tile: two stacked 8-wide column halves, 4 bytes per row
	wire [21:0] w_tile   = {9'd0, tile};
	wire [21:0] spr_byte = (w_tile << 7)
	                     + (gx[3] ? 22'd64 : 22'd0)
	                     + ({18'd0, gy} << 2)
	                     + {19'd0, gx[2:1]};

	wire [3:0] pix = gx[0] ? rom_data[3:0] : rom_data[7:4];

	wire signed [11:0] px = {sx[10], sx} + {8'd0, bx};
	wire signed [11:0] py = {sy[10], sy} + {8'd0, by};
	wire on_screen = (px >= 12'sd0) && (px < 12'sd256)
	              && (py >= 12'sd0) && (py < 12'sd256);

	// the next pixel's addresses, so S_BB can set up S_BA's fetch in one go
	wire [15:0] cur_fb = {py[7:0], px[7:0]};

	always @(posedge clk) begin
		fb_we <= 1'b0;

		if (reset) begin
			st <= S_IDLE; busy <= 1'b0;
		end else case (st)
		S_IDLE: if (start) begin
			busy <= 1'b1;
			clr  <= 17'd0;
			offs <= 8'd255;
			bank <= 2'd0;
			// sprite_flag bit 4 keeps the previous plane (the P47 trails
			// effect). MAME then partially clears by pen, which is not
			// modelled -- docs/known-issues.md MS1-17.
			if (no_clear) begin obj_addr <= {2'd0, 8'd255, 2'd0}; st <= S_O0; end
			else st <= S_CLEAR;
		end

		S_CLEAR: begin
			fb_wr_addr <= clr[15:0];
			fb_wr_data <= 9'h00F;             // pen 15 = empty
			fb_we      <= 1'b1;
			clr        <= clr + 17'd1;
			if (clr == 17'd65535) begin
				obj_addr <= {2'd0, 8'd255, 2'd0};
				st <= S_O0;
			end
		end

		// ---- object entry: four words. The address is registered and the
		// memory read is combinational, so the word for the address set in
		// state N-1 is on `obj_data` DURING state N -- it must be latched in
		// the state that follows the one which issued its address, not the
		// one after that. Getting this off by one reads each field as the
		// next field along, which is silent: every value is still a plausible
		// sprite, just the wrong one.
		S_O0: begin o_idx <= obj_data; obj_addr <= {bank, offs, 2'd1}; st <= S_O1; end
		S_O1: begin o_dx  <= obj_data; obj_addr <= {bank, offs, 2'd2}; st <= S_O2; end
		S_O2: begin o_dy  <= obj_data; obj_addr <= {bank, offs, 2'd3}; st <= S_O3; end
		S_O3: begin o_dn  <= obj_data;
		            sbase    <= {o_idx[6:0], 3'd0};
		            spr_addr <= {o_idx[6:0], 3'd0} + 12'd4;
		            st <= S_S0; end

		// ---- sprite data entry: words 4..7 (attr, X, Y, code)
		S_S0: begin s_attr <= spr_data; spr_addr <= sbase + 12'd5; st <= S_S1; end
		S_S1: begin s_x    <= spr_data; spr_addr <= sbase + 12'd6; st <= S_S2; end
		S_S2: begin s_y    <= spr_data; spr_addr <= sbase + 12'd7; st <= S_S3; end
		S_S3: begin s_code <= spr_data; st <= S_DEC; end

		S_DEC: begin
			// only the bank matching this sprite's flip bits draws it
			if (s_attr[7:6] != bank) st <= S_NEXT;
			else begin
				// The position is the 9-bit SUM, masked and only THEN sign
				// extended -- util::sext((pos + disp) & 0x1ff, 9). Sign
				// extending each term first and adding is not the same thing
				// whenever the sum wraps through bit 8.
				sx     <= $signed({2'b00, sum_x}) - (sum_x[8] ? 11'sd512 : 11'sd0);
				sy     <= $signed({2'b00, sum_y}) - (sum_y[8] ? 11'sd512 : 11'sd0);
				scol   <= s_attr[3:0] & color_mask;
				sflipx <= s_attr[6];
				sflipy <= s_attr[7];
				spri   <= s_attr[3];
				mosaic <= s_attr[11:8];
				mossol <= s_attr[12];
				tile   <= {sprite_bank[0], (s_code[11:0] + o_dn[11:0])};
				bx <= 4'd0; by <= 4'd0;
				st <= S_BA;
			end
		end

		// ---- blit 16x16, two clocks per pixel: address, then decide
		S_BA: begin
			rom_addr <= spr_byte;
			eng_addr <= cur_fb;
			st <= S_BB;
		end
		S_BB: begin
			// FIRST WRITER WINS: only an empty plane pixel (pen 15) is taken.
			if (on_screen && pix != 4'hF && eng_q[3:0] == 4'hF) begin
				fb_wr_addr <= cur_fb;
				fb_wr_data <= {spri, scol, pix};
				fb_we      <= 1'b1;
			end
			if (bx == 4'd15) begin
				bx <= 4'd0;
				if (by == 4'd15) st <= S_NEXT;
				else begin by <= by + 4'd1; st <= S_BA; end
			end else begin bx <= bx + 4'd1; st <= S_BA; end
		end

		S_NEXT: begin
			if (bank == 2'd3) begin
				bank <= 2'd0;
				if (offs == 8'd0) begin st <= S_IDLE; busy <= 1'b0; end
				else begin
					offs <= offs - 8'd1;
					obj_addr <= {2'd0, offs - 8'd1, 2'd0};
					st <= S_O0;
				end
			end else begin
				bank <= bank + 2'd1;
				obj_addr <= {bank + 2'd1, offs, 2'd0};
				st <= S_O0;
			end
		end
		default: st <= S_IDLE;
		endcase
	end
endmodule
