// Hardware-path simulation for the Jaleco MS1 B/C/D core: every ROM byte comes
// out of the real rtl/sdram.sv talking to sim/models/sdram_model.sv, filled by
// a real ioctl_download byte stream -- the same bytes, in the same order, that
// the .mra loader sends on the board.
//
// The stream arrives in LOADER ORDER (index 0, then index 1, then <switches>
// on 254 LAST), because that is the order the real loader uses and anything
// decided while a ROM streams sees the switches at their idle value. NMK16
// shipped a bug that every simulation passed and the board failed, for exactly
// this reason.
module ms1_hw_top (
	input         clk_sys,        // 48 MHz
	input         clk_ram,        // SDRAM controller clock
	input         reset,
	input  [1:0]  mode,

	// ioctl download
	input         ioctl_download,
	input         ioctl_wr,
	input  [26:0] ioctl_addr,
	input  [7:0]  ioctl_dout,
	input  [7:0]  ioctl_index,
	output        ioctl_wait,

	// golden-byte audit
	input         audit_en,
	input  [3:0]  audit_sel,
	input  [23:0] audit_addr,
	output [15:0] audit_data,
	output        audit_ready,

	output        sdram_ready,
	output [31:0] dbg_dl_bytes, dbg_prom_bytes
);
	wire [15:0] SDRAM_DQ;
	wire [12:0] SDRAM_A;
	wire [1:0]  SDRAM_BA;
	wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS,
	            SDRAM_nWE, SDRAM_CLK, SDRAM_CKE;

	wire [24:1] p0_addr, p1_addr, p2_addr, p3_addr;
	wire        p0_wrl, p1_wrl, p2_wrl, p3_wrl;
	wire        p0_wrh, p1_wrh, p2_wrh, p3_wrh;
	wire [15:0] p0_din,  p1_din,  p2_din,  p3_din;
	wire [15:0] p0_dout, p1_dout, p2_dout, p3_dout;
	wire [31:0] p0_pair, p1_pair, p2_pair, p3_pair;
	wire        p0_req, p1_req, p2_req, p3_req;
	wire        p0_ack, p1_ack, p2_ack, p3_ack;

	// REFRESH_CYCLES must scale with the controller's own clock: the default
	// (850) is already over spec at 96 MHz and produced real, reproducible
	// read-back corruption on silicon at 40 MHz. 740 is this project's value.
	sdram #(.REFRESH_CYCLES(10'd740)) u_sdram (
		.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .ready(sdram_ready),
		.init(reset), .clk(clk_ram), .prio_mode(2'd0),
		.addr0(p0_addr), .wrl0(p0_wrl), .wrh0(p0_wrh), .din0(p0_din),
		.dout0(p0_dout), .dout0_pair(p0_pair), .req0(p0_req), .ack0(p0_ack),
		.addr1(p1_addr), .wrl1(p1_wrl), .wrh1(p1_wrh), .din1(p1_din),
		.dout1(p1_dout), .dout1_pair(p1_pair), .req1(p1_req), .ack1(p1_ack),
		.addr2(p2_addr), .wrl2(p2_wrl), .wrh2(p2_wrh), .din2(p2_din),
		.dout2(p2_dout), .dout2_pair(p2_pair), .req2(p2_req), .ack2(p2_ack),
		.addr3(p3_addr), .wrl3(p3_wrl), .wrh3(p3_wrh), .din3(p3_din),
		.dout3(p3_dout), .dout3_pair(p3_pair), .req3(p3_req), .ack3(p3_ack)
	);
	sdram_model u_model (
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
		.SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE)
	);

	ms1bcd_rom_hw u_rom (
		.clk(clk_sys), .reset(reset), .pwr_reset(reset), .mode(mode),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),

		// The core is not instantiated in this build: the audit drives every
		// cache directly, which is what isolates "the bytes reached SDRAM and
		// come back correctly" from anything the core does with them.
		.rom_addr(19'd0),  .rom_data(),  .rom_ready(),
		.srom_addr(17'd0), .srom_data(), .srom_ready(),
		.mcu_rom_addr(14'd0), .mcu_rom_data(), .mcu_rom_ready(),
		.l0_rom_addr(21'd0), .l1_rom_addr(21'd0), .l2_rom_addr(21'd0),
		.l0_rom_data(), .l1_rom_data(), .l2_rom_data(),
		.l0_ready(), .l1_ready(), .l2_ready(),
		.spr_rom_addr(22'd0), .spr_rom_data(), .spr_ready(),
		.oki1_rom_addr(18'd0), .oki2_rom_addr(18'd0),
		.oki1_rom_data(), .oki2_rom_data(),
		.oki1_stall(), .oki2_stall(),
		.prom_addr(audit_addr[8:0]), .prom_data(),

		.audit_en(audit_en), .audit_sel(audit_sel), .audit_addr(audit_addr),
		.audit_data(audit_data), .audit_ready(audit_ready),

		.sdram_addr0(p0_addr), .sdram_addr1(p1_addr), .sdram_addr2(p2_addr), .sdram_addr3(p3_addr),
		.sdram_wrl0(p0_wrl), .sdram_wrl1(p1_wrl), .sdram_wrl2(p2_wrl), .sdram_wrl3(p3_wrl),
		.sdram_wrh0(p0_wrh), .sdram_wrh1(p1_wrh), .sdram_wrh2(p2_wrh), .sdram_wrh3(p3_wrh),
		.sdram_din0(p0_din), .sdram_din1(p1_din), .sdram_din2(p2_din), .sdram_din3(p3_din),
		.sdram_dout0(p0_dout), .sdram_dout1(p1_dout), .sdram_dout2(p2_dout), .sdram_dout3(p3_dout),
		.sdram_pair0(p0_pair), .sdram_pair1(p1_pair), .sdram_pair2(p2_pair), .sdram_pair3(p3_pair),
		.sdram_req0(p0_req), .sdram_req1(p1_req), .sdram_req2(p2_req), .sdram_req3(p3_req),
		.sdram_ack0(p0_ack), .sdram_ack1(p1_ack), .sdram_ack2(p2_ack), .sdram_ack3(p3_ack),

		.dbg_dl_bytes(dbg_dl_bytes), .dbg_prom_bytes(dbg_prom_bytes)
	);
endmodule
