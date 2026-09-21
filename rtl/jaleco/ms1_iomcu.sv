// Jaleco Mega System 1 protection MCU: a Toshiba TMP91640.
//
// This is the same TLCS-90 core this project family already uses as the
// NMK004, re-roled rather than rewritten -- docs/PLAN.md's step 4 calls it
// "the one genuinely new CPU integration, mostly already done". Nothing in
// tlcs90.sv changes: the core exposes a flat address/data bus and the part
// number lives entirely in this wrapper's decode.
//
// TMP91640 internal map, from MAME's cpu/tlcs90/tlcs90.cpp tmp91640_mem:
//   0000-3FFF  16 KB internal ROM   (the .mra's iomcu region; NEVER baked
//                                    into the bitstream, see PLAN 2.3)
//   FDC0-FFBF  512 B internal RAM
//   FFC0-FFEF  on-chip registers    (the tmp90840_regs block, which is what
//                                    tlcs90_periph_ref.sv already models)
//
// Everything else in the MCU's 20-bit space is the board's input latch,
// selected by the ADDRESS BANK -- MAME's mcu_capture_inputs_r takes
// offset>>16 and returns:
//   1 = P1, 2 = P2, 3 = DSW1, 4 = DSW2, 5 = SYSTEM,
//   7 = raise IRQ 2 on the MAIN CPU and return 0, anything else = 0.
// The MCU reaches those banks through the TLCS-90's IX/IY bank extension,
// which is why the core's addr_bank output is wired from the peripheral
// block's BX/BY registers.
//
// Host protocol (jaleco/megasys1.cpp):
//   main CPU writes the protection port -> byte latched into `to_mcu`, and
//     INT0 pulsed on the MCU
//   MCU reads port 1                    -> that byte
//   MCU writes port 2                   -> the answer
//   main CPU reads the protection port  -> that answer
//
// So the whole conversation is visible from the 68000 bus alone, which is
// what makes it checkable command by command against a MAME trace rather
// than by "the game boots" (docs/PLAN.md M2 gate 5).

module ms1_iomcu (
	input             clk,
	input             cen,          // MCU clock enable
	input             reset,

	// ---- host side
	input             host_we,      // main CPU wrote the protection port
	input       [7:0] host_data,

	// INT1 is the board's DISPLAY ENABLE, not a timer: MAME asserts it at
	// scanline 16 (end of vblank) and clears it at 240 (start of vblank), so
	// the MCU's whole command loop is paced by the video frame. Without it
	// the MCU boots, initialises, and parks in its wait loop forever -- which
	// is exactly what happened before this input existed.
	input             int1,
	output reg  [7:0] mcu_data,     // what the main CPU reads back
	output reg        main_irq2,    // pulse: MCU asked for IRQ 2 (bank 7)

	// ---- board inputs, active-low as the ports read them
	input       [7:0] in_p1,
	input       [7:0] in_p2,
	input       [7:0] in_dsw1,
	input       [7:0] in_dsw2,
	input       [7:0] in_system,

	// ---- internal ROM load (ioctl), 16 KB
	input             rom_we,
	input      [13:0] rom_addr,
	input       [7:0] rom_data,

	// probes for the replay harness
	output     [15:0] dbg_addr,
	output      [3:0] dbg_bank,
	output            dbg_rd,
	output            dbg_wr,
	output      [7:0] dbg_din
);
	// ---------------------------------------------------------- memories
	reg [7:0] irom [0:16383];
	reg [7:0] iram [0:511];
	always @(posedge clk) if (rom_we) irom[rom_addr] <= rom_data;

	// ---------------------------------------------------------- CPU core
	wire [15:0] addr;
	wire  [3:0] addr_bank;
	wire        mem_rd, mem_wr;
	wire  [7:0] dout;
	reg   [7:0] din;

	wire [10:0] irq_mask, irq_req_p;
	wire  [3:0] bx, by;
	wire  [7:0] preg_rdata;
	wire        p2_we;
	wire  [7:0] p2_wdata;

	// INT0 is bit 0 of the core's irq_req -- the highest-priority maskable
	// source, and the one the host pulses on every protection write.
	reg int0_pending;
	always @(posedge clk) begin
		if (reset)        int0_pending <= 1'b0;
		else if (host_we) int0_pending <= 1'b1;
		else if (cen)     int0_pending <= 1'b0;   // one-cen pulse, edge taken
	end
	// INT1 is a LEVEL in MAME (assert/clear around the visible area) but the
	// core latches irq_req internally and does not clear on take, so a held
	// level would re-pend immediately and interrupt forever. Take the edge.
	reg int1_d, int1_pending;
	always @(posedge clk) begin
		// int1_d follows int1 through reset, so coming out of reset with the
		// beam already inside the visible area does not manufacture an edge
		// that never happened.
		if (reset) begin int1_d <= int1; int1_pending <= 1'b0; end
		else begin
			int1_d <= int1;
			if (int1 & ~int1_d) int1_pending <= 1'b1;
			else if (cen)       int1_pending <= 1'b0;
		end
	end

	wire [10:0] irq_req = irq_req_p
	                    | {10'd0, int0_pending}
	                    | {4'd0, int1_pending, 6'd0};

	// ------------------------------------------------------------ decode
	wire bank0    = (addr_bank == 4'd0);
	wire sel_rom  = bank0 & (addr < 16'h4000);
	wire sel_ram  = bank0 & (addr >= 16'hFDC0) & (addr <= 16'hFFBF);
	wire sel_preg = bank0 & (addr >= 16'hFFC0) & (addr <= 16'hFFEF);
	wire sel_in   = ~(sel_rom | sel_ram | sel_preg);

	reg [7:0] in_mux;
	always @* begin
		case (addr_bank)
			4'd1:    in_mux = in_p1;
			4'd2:    in_mux = in_p2;
			4'd3:    in_mux = in_dsw1;
			4'd4:    in_mux = in_dsw2;
			4'd5:    in_mux = in_system;
			default: in_mux = 8'h00;          // bank 7 included: returns 0
		endcase
	end

	// Bank 7 is not an input at all: reading it is how the MCU asks the MAIN
	// CPU for IRQ 2. One pulse per read.
	always @(posedge clk) main_irq2 <= cen & mem_rd & sel_in & (addr_bank == 4'd7);

	always @(posedge clk) if (cen) begin
		if (mem_wr & sel_ram) iram[addr[8:0] - 9'h1C0] <= dout;
	end

	// combinational read, the bus convention tlcs90.sv documents
	always @* begin
		if      (sel_rom)  din = irom[addr[13:0]];
		else if (sel_ram)  din = iram[addr[8:0] - 9'h1C0];
		else if (sel_preg) din = preg_rdata;
		else               din = in_mux;
	end

	// ------------------------------------------------- host-facing latches
	reg [7:0] to_mcu;
	always @(posedge clk) begin
		if (reset) begin to_mcu <= 8'h00; mcu_data <= 8'h00; end
		else begin
			if (host_we)          to_mcu   <= host_data;
			if (cen && p2_we)     mcu_data <= p2_wdata;
		end
	end

	assign dbg_addr = addr;
	assign dbg_bank = addr_bank;
	assign dbg_rd   = mem_rd;
	assign dbg_wr   = mem_wr;
	assign dbg_din  = mem_wr ? dout : din;   // writes show the DATA WRITTEN

	tlcs90 u_cpu (
		.clk(clk), .cen(cen), .reset(reset),
		.din(din), .dout(dout), .addr(addr), .addr_bank(addr_bank),
		.mem_rd(mem_rd), .mem_wr(mem_wr),
		.nmi(1'b0), .irq_req(irq_req), .irq_mask(irq_mask),
		.ix_bank(bx), .iy_bank(by)
	);

	nmk004_periph u_preg (
		.clk(clk), .cen(cen), .reset(reset),
		.reg_addr(addr[5:0]), .wdata(dout),
		.we(cen & mem_wr & sel_preg), .re(cen & mem_rd & sel_preg),
		.rdata(preg_rdata),
		.irq_mask(irq_mask), .irq_req(irq_req_p),
		.p4_latch(), .bx(bx), .by(by),
		.p5_ext_en(1'b0), .p5_ext_val(8'h00),
		.p6_ext_en(1'b0), .p6_ext_val(8'h00),
		.p6_we(), .p6_wdata(),
		.p1_ext_en(1'b1), .p1_ext_val(to_mcu),
		.p2_we(p2_we), .p2_wdata(p2_wdata)
	);
endmodule
