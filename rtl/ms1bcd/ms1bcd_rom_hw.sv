// The SDRAM side of the Jaleco Mega System 1 B/C/D core: the ioctl download,
// the priority PROM's write port, and a cache in front of every ROM the core
// reads. It presents exactly the zero-latency-looking ports ms1bcd_core.sv
// already has, so the reference sim (which serves those ports from plain
// arrays) and the hardware path differ only in what sits behind them.
//
// Region bases come from ms1bcd_rom_map.vh, which tools/gen_rom_map.py
// generates from the same tools/ms1_romdata.py the .mra files are built from.
// docs/PLAN.md 1.5 requires one table; `tools/gen_rom_map.py --check` is what
// enforces it.
//
// Port allocation over rtl/sdram.sv's four physical ports:
//
//   0   main 68000 program  +  the ioctl download
//   1   scroll layers 0 and 1
//   2   scroll layer 2      +  sprites
//   3   sound 68000  +  MCU  +  OKI #1  +  OKI #2
//
// The download shares port 0 with the main CPU because the two never overlap:
// the core is held in reset for the whole transfer.
module ms1bcd_rom_hw (
	input               clk,          // 48 MHz clk_sys
	input               reset,        // core reset
	// SS-15: the loader gets a POWER-ON-ONLY reset. Its request register is
	// cleared by its reset, so any reset asserted during the transfer means
	// not one byte reaches the SDRAM -- and since ioctl_wait is suppressed
	// too, the loader streams every byte at full speed and reports success.
	// Both ioctl_download and the framework's own RESET are held high for the
	// whole download, so neither may be allowed anywhere near this.
	input               pwr_reset,
	input        [1:0]  mode,         // 0 = B, 1 = C, 2 = D

	// ------------------------------------------------------------- ioctl
	input               ioctl_download,
	input        [7:0]  ioctl_index,
	input               ioctl_wr,
	input       [26:0]  ioctl_addr,
	input        [7:0]  ioctl_dout,
	output              ioctl_wait,

	// ------------------------------------------- consumer ports (to core)
	input       [18:0]  rom_addr,      // main 68000, word address
	output      [15:0]  rom_data,
	output              rom_ready,

	input       [16:0]  srom_addr,     // sound 68000, word address
	output      [15:0]  srom_data,
	output              srom_ready,

	input       [13:0]  mcu_rom_addr,  // TMP91640 internal ROM, byte
	output       [7:0]  mcu_rom_data,
	output              mcu_rom_ready,

	input       [20:0]  l0_rom_addr, l1_rom_addr, l2_rom_addr,
	output       [7:0]  l0_rom_data, l1_rom_data, l2_rom_data,
	output              l0_ready, l1_ready, l2_ready,

	input       [21:0]  spr_rom_addr,
	output       [7:0]  spr_rom_data,
	output              spr_ready,

	input       [17:0]  oki1_rom_addr, oki2_rom_addr,
	output       [7:0]  oki1_rom_data, oki2_rom_data,
	output              oki1_stall, oki2_stall,

	input        [8:0]  prom_addr,     // priority PROM, 512 B, ioctl index 1
	output       [7:0]  prom_data,

	// ------------------------------------------------- golden-byte audit
	// Walks every byte of every region through the REAL cache and the REAL
	// SDRAM controller, so a mismatch separates "the cache never fills" from
	// "the cache fills with the wrong bytes". The core is held in reset while
	// this runs, so the muxes below cannot fight it.
	input               audit_en,
	input        [3:0]  audit_sel,
	input       [23:0]  audit_addr,
	output reg  [15:0]  audit_data,
	output reg          audit_ready,

	// --------------------------------------------------- rtl/sdram.sv side
	output      [24:1]  sdram_addr0, sdram_addr1, sdram_addr2, sdram_addr3,
	output              sdram_wrl0,  sdram_wrl1,  sdram_wrl2,  sdram_wrl3,
	output              sdram_wrh0,  sdram_wrh1,  sdram_wrh2,  sdram_wrh3,
	output      [15:0]  sdram_din0,  sdram_din1,  sdram_din2,  sdram_din3,
	input       [15:0]  sdram_dout0, sdram_dout1, sdram_dout2, sdram_dout3,
	input       [31:0]  sdram_pair0, sdram_pair1, sdram_pair2, sdram_pair3,
	output              sdram_req0,  sdram_req1,  sdram_req2,  sdram_req3,
	input               sdram_ack0,  sdram_ack1,  sdram_ack2,  sdram_ack3,

	// -------------------------------------------------------- diagnostics
	output reg  [31:0]  dbg_dl_bytes,    // bytes accepted into SDRAM
	output reg  [31:0]  dbg_prom_bytes
);
	`include "ms1bcd_rom_map.vh"

	// =================================================== ioctl: the download
	// Every SDRAM write is gated on ioctl_index == 0. The .mra sends
	// <switches> as a second session on index 254 with the address restarting
	// at 0; ungated it lands on the 68000's reset vector, which is NMK16's
	// first black screen. Index 1 is the priority PROM and goes to the RAM
	// below, never to SDRAM.
	wire dl_rom  = ioctl_download && (ioctl_index == 8'd0);
	wire dl_prom = ioctl_download && (ioctl_index == 8'd1);

	reg         dl_req;
	reg  [24:1] dl_addr;
	reg  [15:0] dl_din;
	reg         dl_wrl, dl_wrh;
	wire        dl_busy, dl_valid;

	// One byte per SDRAM write, selected by the byte mask. Simpler than
	// pairing bytes and fast enough: ~3.3 MB at a few clocks each is a
	// fraction of a second, and it cannot mis-order the final odd byte of a
	// region the way a pair accumulator can.
	always @(posedge clk) begin
		if (pwr_reset) begin
			dl_req <= 1'b0; dl_wrl <= 1'b0; dl_wrh <= 1'b0;
			dbg_dl_bytes <= 32'd0;
		end else begin
			if (dl_req && !dl_busy) dl_req <= dl_req;   // hold until taken
			if (dl_valid) dl_req <= 1'b0;
			if (dl_rom && ioctl_wr && !dl_req) begin
				dl_addr <= ioctl_addr[24:1];
				dl_din  <= {ioctl_dout, ioctl_dout};    // same byte on both lanes
				dl_wrl  <= ~ioctl_addr[0];
				dl_wrh  <=  ioctl_addr[0];
				dl_req  <= 1'b1;
				dbg_dl_bytes <= dbg_dl_bytes + 32'd1;
			end
		end
	end
	// The loader must be told to wait while a write is outstanding, or bytes
	// are dropped silently.
	assign ioctl_wait = dl_req;

	// ------------------------------------------- priority PROM (index 1)
	// 512 bytes, no initial contents anywhere: docs/PLAN.md 2.3 forbids ROM or
	// PROM data in the bitstream, and the thing to grep for in review is a
	// $readmemh outside an HW_ROMS == 0 guard. There is none in this file.
	reg [7:0] promram [0:511];
	always @(posedge clk) begin
		if (pwr_reset) dbg_prom_bytes <= 32'd0;
		else if (dl_prom && ioctl_wr && ioctl_addr < 27'd512) begin
			promram[ioctl_addr[8:0]] <= ioctl_dout;
			dbg_prom_bytes <= dbg_prom_bytes + 32'd1;
		end
	end
	reg [7:0] prom_q;
	always @(posedge clk) prom_q <= promram[prom_addr];
	assign prom_data = prom_q;

	// Every cache is held in reset for the whole transfer. Without this they
	// run while the ROM streams, and since the core's address inputs sit at
	// their reset value the main cache happily fetches word 0, caches the
	// zeros that are there BEFORE the download writes it, and keeps them --
	// so the 68000 comes out of reset reading a zeroed reset vector. The
	// golden-byte audit caught it as exactly one wrong word, at address 0.
	//
	// This is why the loader's reset is separate (SS-15): everything else here
	// may be reset freely during the download; the loader may not.
	wire cache_reset = reset | ioctl_download;

	// ------------------------------------------------- audit address muxes
	// audit_sel: 0 main, 1 sound, 2 MCU, 3 L0, 4 L1, 5 L2, 6 sprites,
	//            7 OKI1, 8 OKI2, 9 PROM.
	wire [18:0] a_main = audit_en ? audit_addr[18:0] : rom_addr;
	wire [16:0] a_snd  = audit_en ? audit_addr[16:0] : srom_addr;
	wire [23:0] a_mcu  = audit_en ? audit_addr : {10'd0, mcu_rom_addr};
	wire [23:0] a_l0   = audit_en ? audit_addr : {3'd0, l0_rom_addr};
	wire [23:0] a_l1   = audit_en ? audit_addr : {3'd0, l1_rom_addr};
	wire [23:0] a_l2   = audit_en ? audit_addr : {3'd0, l2_rom_addr};
	wire [23:0] a_spr  = audit_en ? audit_addr : {2'd0, spr_rom_addr};
	wire [23:0] a_oki1 = audit_en ? audit_addr : {6'd0, oki1_rom_addr};
	wire [23:0] a_oki2 = audit_en ? audit_addr : {6'd0, oki2_rom_addr};
	wire        oki1_ready, oki2_ready;

	// Byte order is a PER-CONSUMER decision (docs/PLAN.md 4.A.5), and the two
	// conventions in this core disagree. The download writes the byte at an
	// even ioctl address to the LOW lane, which is what every byte cache here
	// assumes (rom_cache_n_byte.sv:50, oki_rom_cache.sv:82) and what the tile,
	// sprite, OKI and MCU fetches therefore need. The two 68000s want the
	// opposite: the reference sim builds their words as
	// (image[even] << 8) | image[odd], which is the even byte in the HIGH
	// lane -- and it is right, because that is what puts avspirit's reset
	// vector at SP 0x00080000 / PC 0x000006B2. So the swap belongs on these
	// two read paths and nowhere else; doing it in the download instead would
	// have silently mangled every graphics and sample byte.
	wire [15:0] main_word, snd_word;
	assign rom_data  = {main_word[7:0], main_word[15:8]};
	assign srom_data = {snd_word[7:0],  snd_word[15:8]};

	always @* begin
		case (audit_sel)
			4'd0: begin audit_data = rom_data;                audit_ready = rom_ready;     end
			4'd1: begin audit_data = srom_data;               audit_ready = srom_ready;    end
			4'd2: begin audit_data = {8'd0, mcu_rom_data};    audit_ready = mcu_rom_ready; end
			4'd3: begin audit_data = {8'd0, l0_rom_data};     audit_ready = l0_ready;      end
			4'd4: begin audit_data = {8'd0, l1_rom_data};     audit_ready = l1_ready;      end
			4'd5: begin audit_data = {8'd0, l2_rom_data};     audit_ready = l2_ready;      end
			4'd6: begin audit_data = {8'd0, spr_rom_data};    audit_ready = spr_ready;     end
			4'd7: begin audit_data = {8'd0, oki1_rom_data};   audit_ready = oki1_ready;    end
			4'd8: begin audit_data = {8'd0, oki2_rom_data};   audit_ready = oki2_ready;    end
			// The PROM is a plain RAM, not a cache: its read is registered, so
			// it is ready one clock later, always.
			4'd9: begin audit_data = {8'd0, prom_q};          audit_ready = 1'b1;          end
			default: begin audit_data = 16'd0;                audit_ready = 1'b1;          end
		endcase
	end

	// ============================================== port 0: main CPU + load
	wire [24:1] p0_addr [0:1];  wire p0_we [0:1];  wire p0_wrl [0:1];
	wire        p0_wrh  [0:1];  wire [15:0] p0_din [0:1];
	wire        p0_req  [0:1];  wire p0_busy [0:1]; wire p0_valid [0:1];
	wire [15:0] p0_dout [0:1];  wire [31:0] p0_pair [0:1];

	wire [24:1] main_sd_addr;  wire main_sd_req;
	rom_cache_n #(.LINES(16), .PREFETCH(1), .LAST_PAIR(22'h3FFFFF)) u_main (
		.clk(clk), .reset(cache_reset),
		.addr({MAIN_BASE[23:1] + {4'd0, a_main}}),
		.data(main_word), .ready(rom_ready),
		.sd_addr(main_sd_addr), .sd_req(main_sd_req),
		.sd_busy(p0_busy[0]), .sd_valid(p0_valid[0]),
		.sd_dout(p0_dout[0]), .sd_dout_pair(p0_pair[0])
	);
	assign p0_addr[0] = main_sd_addr; assign p0_req[0] = main_sd_req;
	assign p0_we[0] = 1'b0; assign p0_wrl[0] = 1'b0; assign p0_wrh[0] = 1'b0;
	assign p0_din[0] = 16'd0;

	assign p0_addr[1] = dl_addr;  assign p0_req[1] = dl_req;
	assign p0_we[1]   = 1'b1;     assign p0_wrl[1] = dl_wrl;
	assign p0_wrh[1]  = dl_wrh;   assign p0_din[1] = dl_din;
	assign dl_busy    = p0_busy[1];
	assign dl_valid   = p0_valid[1];

	sdram_arb #(.N(2)) u_arb0 (
		.clk(clk), .reset(pwr_reset),
		.i_addr(p0_addr), .i_we(p0_we), .i_wrl(p0_wrl), .i_wrh(p0_wrh),
		.i_din(p0_din), .i_req(p0_req), .i_busy(p0_busy),
		.i_valid(p0_valid), .i_dout(p0_dout), .i_dout_pair(p0_pair),
		.sdram_addr(sdram_addr0), .sdram_wrl(sdram_wrl0), .sdram_wrh(sdram_wrh0),
		.sdram_din(sdram_din0), .sdram_dout(sdram_dout0),
		.sdram_dout_pair(sdram_pair0), .sdram_req(sdram_req0), .sdram_ack(sdram_ack0)
	);

	// ================================================ port 1: layers 0 and 1
	wire [24:1] p1_addr [0:1];  wire p1_we [0:1];  wire p1_wrl [0:1];
	wire        p1_wrh  [0:1];  wire [15:0] p1_din [0:1];
	wire        p1_req  [0:1];  wire p1_busy [0:1]; wire p1_valid [0:1];
	wire [15:0] p1_dout [0:1];  wire [31:0] p1_pair [0:1];

	rom_cache_n_byte #(.LINES(8), .PREFETCH(1)) u_l0 (
		.clk(clk), .reset(cache_reset),
		.base_word(L0_BASE[23:1]), .byte_addr(a_l0),
		.data(l0_rom_data), .word(), .ready(l0_ready),
		.sd_addr(p1_addr[0]), .sd_req(p1_req[0]),
		.sd_busy(p1_busy[0]), .sd_valid(p1_valid[0]),
		.sd_dout(p1_dout[0]), .sd_dout_pair(p1_pair[0])
	);
	rom_cache_n_byte #(.LINES(8), .PREFETCH(1)) u_l1 (
		.clk(clk), .reset(cache_reset),
		.base_word(L1_BASE[23:1]), .byte_addr(a_l1),
		.data(l1_rom_data), .word(), .ready(l1_ready),
		.sd_addr(p1_addr[1]), .sd_req(p1_req[1]),
		.sd_busy(p1_busy[1]), .sd_valid(p1_valid[1]),
		.sd_dout(p1_dout[1]), .sd_dout_pair(p1_pair[1])
	);
	assign p1_we[0] = 1'b0; assign p1_wrl[0] = 1'b0; assign p1_wrh[0] = 1'b0; assign p1_din[0] = 16'd0;
	assign p1_we[1] = 1'b0; assign p1_wrl[1] = 1'b0; assign p1_wrh[1] = 1'b0; assign p1_din[1] = 16'd0;

	sdram_arb #(.N(2)) u_arb1 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p1_addr), .i_we(p1_we), .i_wrl(p1_wrl), .i_wrh(p1_wrh),
		.i_din(p1_din), .i_req(p1_req), .i_busy(p1_busy),
		.i_valid(p1_valid), .i_dout(p1_dout), .i_dout_pair(p1_pair),
		.sdram_addr(sdram_addr1), .sdram_wrl(sdram_wrl1), .sdram_wrh(sdram_wrh1),
		.sdram_din(sdram_din1), .sdram_dout(sdram_dout1),
		.sdram_dout_pair(sdram_pair1), .sdram_req(sdram_req1), .sdram_ack(sdram_ack1)
	);

	// ============================================== port 2: layer 2 + sprites
	wire [24:1] p2_addr [0:1];  wire p2_we [0:1];  wire p2_wrl [0:1];
	wire        p2_wrh  [0:1];  wire [15:0] p2_din [0:1];
	wire        p2_req  [0:1];  wire p2_busy [0:1]; wire p2_valid [0:1];
	wire [15:0] p2_dout [0:1];  wire [31:0] p2_pair [0:1];

	rom_cache_n_byte #(.LINES(8), .PREFETCH(1)) u_l2 (
		.clk(clk), .reset(cache_reset),
		.base_word(L2_BASE[23:1]), .byte_addr(a_l2),
		.data(l2_rom_data), .word(), .ready(l2_ready),
		.sd_addr(p2_addr[0]), .sd_req(p2_req[0]),
		.sd_busy(p2_busy[0]), .sd_valid(p2_valid[0]),
		.sd_dout(p2_dout[0]), .sd_dout_pair(p2_pair[0])
	);
	rom_cache_n_byte #(.LINES(8), .PREFETCH(1)) u_spr (
		.clk(clk), .reset(cache_reset),
		.base_word(SPR_BASE[23:1]), .byte_addr(a_spr),
		.data(spr_rom_data), .word(), .ready(spr_ready),
		.sd_addr(p2_addr[1]), .sd_req(p2_req[1]),
		.sd_busy(p2_busy[1]), .sd_valid(p2_valid[1]),
		.sd_dout(p2_dout[1]), .sd_dout_pair(p2_pair[1])
	);
	assign p2_we[0] = 1'b0; assign p2_wrl[0] = 1'b0; assign p2_wrh[0] = 1'b0; assign p2_din[0] = 16'd0;
	assign p2_we[1] = 1'b0; assign p2_wrl[1] = 1'b0; assign p2_wrh[1] = 1'b0; assign p2_din[1] = 16'd0;

	sdram_arb #(.N(2)) u_arb2 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p2_addr), .i_we(p2_we), .i_wrl(p2_wrl), .i_wrh(p2_wrh),
		.i_din(p2_din), .i_req(p2_req), .i_busy(p2_busy),
		.i_valid(p2_valid), .i_dout(p2_dout), .i_dout_pair(p2_pair),
		.sdram_addr(sdram_addr2), .sdram_wrl(sdram_wrl2), .sdram_wrh(sdram_wrh2),
		.sdram_din(sdram_din2), .sdram_dout(sdram_dout2),
		.sdram_dout_pair(sdram_pair2), .sdram_req(sdram_req2), .sdram_ack(sdram_ack2)
	);

	// ======================================= port 3: sound + MCU + both OKIs
	wire [24:1] p3_addr [0:3];  wire p3_we [0:3];  wire p3_wrl [0:3];
	wire        p3_wrh  [0:3];  wire [15:0] p3_din [0:3];
	wire        p3_req  [0:3];  wire p3_busy [0:3]; wire p3_valid [0:3];
	wire [15:0] p3_dout [0:3];  wire [31:0] p3_pair [0:3];

	rom_cache_n #(.LINES(8), .PREFETCH(1), .LAST_PAIR(22'h3FFFFF)) u_snd (
		.clk(clk), .reset(cache_reset),
		.addr({SND_BASE[23:1] + {6'd0, a_snd}}),
		.data(snd_word), .ready(srom_ready),
		.sd_addr(p3_addr[0]), .sd_req(p3_req[0]),
		.sd_busy(p3_busy[0]), .sd_valid(p3_valid[0]),
		.sd_dout(p3_dout[0]), .sd_dout_pair(p3_pair[0])
	);
	rom_cache_n_byte #(.LINES(4), .PREFETCH(1)) u_mcu (
		.clk(clk), .reset(cache_reset),
		.base_word(MCU_BASE[23:1]), .byte_addr(a_mcu),
		.data(mcu_rom_data), .word(), .ready(mcu_rom_ready),
		.sd_addr(p3_addr[1]), .sd_req(p3_req[1]),
		.sd_busy(p3_busy[1]), .sd_valid(p3_valid[1]),
		.sd_dout(p3_dout[1]), .sd_dout_pair(p3_pair[1])
	);
	// Two OKIs, so two caches, each with its stall ANDed into the chip's cen
	// by the core. jt6295 ignores rom_ok; Sand Scorpion shipped 37.6 % stale
	// sample bytes for a week without this.
	oki_rom_cache #(.LINES(16)) u_oki1 (
		.clk(clk), .reset(cache_reset),
		.base_word(OKI1_BASE[23:1]), .byte_addr(a_oki1[21:0]),
		.data(oki1_rom_data), .ready(oki1_ready), .stall(oki1_stall),
		.sd_addr(p3_addr[2]), .sd_req(p3_req[2]),
		.sd_busy(p3_busy[2]), .sd_valid(p3_valid[2]),
		.sd_dout(p3_dout[2]), .sd_dout_pair(p3_pair[2])
	);
	oki_rom_cache #(.LINES(16)) u_oki2 (
		.clk(clk), .reset(cache_reset),
		.base_word(OKI2_BASE[23:1]), .byte_addr(a_oki2[21:0]),
		.data(oki2_rom_data), .ready(oki2_ready), .stall(oki2_stall),
		.sd_addr(p3_addr[3]), .sd_req(p3_req[3]),
		.sd_busy(p3_busy[3]), .sd_valid(p3_valid[3]),
		.sd_dout(p3_dout[3]), .sd_dout_pair(p3_pair[3])
	);
	genvar gi;
	generate for (gi = 0; gi < 4; gi = gi + 1) begin : g_p3_ro
		assign p3_we[gi] = 1'b0; assign p3_wrl[gi] = 1'b0;
		assign p3_wrh[gi] = 1'b0; assign p3_din[gi] = 16'd0;
	end endgenerate

	sdram_arb #(.N(4)) u_arb3 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p3_addr), .i_we(p3_we), .i_wrl(p3_wrl), .i_wrh(p3_wrh),
		.i_din(p3_din), .i_req(p3_req), .i_busy(p3_busy),
		.i_valid(p3_valid), .i_dout(p3_dout), .i_dout_pair(p3_pair),
		.sdram_addr(sdram_addr3), .sdram_wrl(sdram_wrl3), .sdram_wrh(sdram_wrh3),
		.sdram_din(sdram_din3), .sdram_dout(sdram_dout3),
		.sdram_dout_pair(sdram_pair3), .sdram_req(sdram_req3), .sdram_ack(sdram_ack3)
	);
endmodule
