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

	// inputs + video, for the frames gate
	input  [7:0]  in_p1, in_p2, in_dsw1, in_dsw2, in_system,
	output [23:0] rgb,
	output        rgb_valid,
	output        ce_pix_o,
	output        vblank_rise,

	output        sdram_ready,
	output [31:0] dbg_dl_bytes, dbg_prom_bytes,
	output [31:0] dbg_romwait, dbg_romacc,
	output [31:0] dbg_l0_miss, dbg_l1_miss, dbg_l2_miss, dbg_pix,
	output [31:0] dbg_ym_writes, dbg_oki1_writes, dbg_oki2_writes,
	output [15:0] dbg_l2_first_v, dbg_l2_first_h,
	// MS1-51: the MCU's own throughput on the hardware ROM path. The
	// reference sim serves its ROM from an array, so the MCU never stalls
	// there; here it stalls on every cache miss (cen_eff in ms1_iomcu.sv), and
	// IRQ2 -- which the 68000's main loop waits on -- is the visible rate.
	output [31:0] dbg_irq2, dbg_int1e, dbg_mcuacc,
	// MS1-51 trace: port 3 carries the sound 68000, the MCU and both OKIs.
	output        dbg_p3_req, dbg_p3_ack,
	output [24:1] dbg_p3_addr,
	output        dbg_mcu_ready, dbg_srom_ready,
	output [31:0] dbg_spr_pass_cycles,
	output [15:0] dbg_spr_late_swaps
);
	wire [15:0] SDRAM_DQ;
	wire [12:0] SDRAM_A;
	wire [1:0]  SDRAM_BA;
	wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS,
	            SDRAM_nWE, SDRAM_CLK, SDRAM_CKE;

	assign dbg_p3_req  = p3_req;
	assign dbg_p3_ack  = p3_ack;
	assign dbg_p3_addr = p3_addr;
	assign dbg_mcu_ready  = c_mcu_ready;
	assign dbg_srom_ready = c_srom_ready;
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

	wire [18:0] c_rom_addr;  wire [15:0] c_rom_data;  wire c_rom_ready;
	wire [16:0] c_srom_addr; wire [15:0] c_srom_data; wire c_srom_ready;
	wire [13:0] c_mcu_addr;  wire  [7:0] c_mcu_data;  wire c_mcu_ready;
	wire [20:0] c_l0_addr, c_l1_addr, c_l2_addr;
	wire [20:0] c_l0_use, c_l1_use, c_l2_use;
	wire  [7:0] c_l0_data, c_l1_data, c_l2_data;
	wire        c_l0_ready, c_l1_ready, c_l2_ready;
	wire [21:0] c_spr_addr; wire [7:0] c_spr_data; wire c_spr_ready;
	wire [17:0] c_oki1_addr, c_oki2_addr;
	wire  [7:0] c_oki1_data, c_oki2_data;
	wire        c_oki1_stall, c_oki2_stall;
	wire  [8:0] c_prom_addr; wire [7:0] c_prom_data;

	// The core is held in reset for the whole transfer and until the
	// controller reports ready, so no cache is ever asked for a byte that is
	// not there yet -- and, just as importantly, no cache is left holding
	// something it fetched before the download wrote it.
	wire core_reset = reset | ioctl_download | ~sdram_ready | audit_en;

	ms1bcd_core #(.LOOKAHEAD(8)) u_core (
		.clk(clk_sys), .reset(core_reset), .mode(mode),
		// Debug-only bisection aid, explicitly off here: an unconnected reset
		// input is not something to leave to the tool's x-assign policy.
		.ss_rst_dbg(4'd0),
		.rom_addr(c_rom_addr), .rom_data(c_rom_data), .rom_ready(c_rom_ready),
		.mcu_rom_addr(c_mcu_addr), .mcu_rom_data(c_mcu_data),
		.mcu_rom_ready(c_mcu_ready),
		.in_p1(in_p1), .in_p2(in_p2), .in_dsw1(in_dsw1), .in_dsw2(in_dsw2),
		.in_system(in_system),
		.l0_rom_addr(c_l0_addr), .l1_rom_addr(c_l1_addr), .l2_rom_addr(c_l2_addr),
		.l0_rom_use_addr(c_l0_use), .l1_rom_use_addr(c_l1_use),
		.l2_rom_use_addr(c_l2_use),
		.l0_rom_data(c_l0_data), .l1_rom_data(c_l1_data), .l2_rom_data(c_l2_data),
		.l0_rom_ready(c_l0_ready), .l1_rom_ready(c_l1_ready), .l2_rom_ready(c_l2_ready),
		.spr_rom_addr(c_spr_addr), .spr_rom_data(c_spr_data),
		.spr_rom_ready(c_spr_ready),
		.prom_addr(c_prom_addr), .prom_data(c_prom_data),
		.srom_addr(c_srom_addr), .srom_data(c_srom_data), .srom_ready(c_srom_ready),
		.oki1_rom_addr(c_oki1_addr), .oki2_rom_addr(c_oki2_addr),
		.oki1_rom_data(c_oki1_data), .oki2_rom_data(c_oki2_data),
		.oki1_stall(c_oki1_stall), .oki2_stall(c_oki2_stall),
		.oki_status_real(1'b0),
		.snd_l(), .snd_r(),
		.dbg_ym_writes(dbg_ym_writes), .dbg_oki1_writes(dbg_oki1_writes),
		.dbg_oki2_writes(dbg_oki2_writes),
		.dbg_fm_l(), .dbg_fm_r(), .dbg_oki1(), .dbg_oki2(),
		.rgb(rgb), .rgb_valid(rgb_valid), .vblank_rise(vblank_rise),
		.vcount_o(), .hcount_o(), .ce_pix_o(ce_pix_o),
		.dbg_romwait(dbg_romwait), .dbg_romacc(dbg_romacc),
		.dbg_l0_miss(dbg_l0_miss), .dbg_l1_miss(dbg_l1_miss),
		.dbg_l2_miss(dbg_l2_miss), .dbg_pix(dbg_pix),
		.dbg_l2_first_v(dbg_l2_first_v), .dbg_l2_first_h(dbg_l2_first_h),
		.dbg_irq2(dbg_irq2), .dbg_int1e(dbg_int1e), .dbg_mcuacc(dbg_mcuacc),
		.dbg_spr_pass_cycles(dbg_spr_pass_cycles),
		.dbg_spr_late_swaps(dbg_spr_late_swaps)
	);

	ms1bcd_rom_hw u_rom (
		.clk(clk_sys), .reset(reset), .pwr_reset(reset), .mode(mode),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),

		.rom_addr(c_rom_addr),   .rom_data(c_rom_data),   .rom_ready(c_rom_ready),
		.srom_addr(c_srom_addr), .srom_data(c_srom_data), .srom_ready(c_srom_ready),
		.mcu_rom_addr(c_mcu_addr), .mcu_rom_data(c_mcu_data),
		.mcu_rom_ready(c_mcu_ready),
		.l0_rom_addr(c_l0_addr), .l1_rom_addr(c_l1_addr), .l2_rom_addr(c_l2_addr),
		.l0_rom_use_addr(c_l0_use), .l1_rom_use_addr(c_l1_use),
		.l2_rom_use_addr(c_l2_use),
		.l0_rom_data(c_l0_data), .l1_rom_data(c_l1_data), .l2_rom_data(c_l2_data),
		.l0_ready(c_l0_ready), .l1_ready(c_l1_ready), .l2_ready(c_l2_ready),
		.spr_rom_addr(c_spr_addr), .spr_rom_data(c_spr_data), .spr_ready(c_spr_ready),
		.oki1_rom_addr(c_oki1_addr), .oki2_rom_addr(c_oki2_addr),
		.oki1_rom_data(c_oki1_data), .oki2_rom_data(c_oki2_data),
		.oki1_stall(c_oki1_stall), .oki2_stall(c_oki2_stall),
		.prom_addr(audit_en ? audit_addr[8:0] : c_prom_addr), .prom_data(c_prom_data),

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
