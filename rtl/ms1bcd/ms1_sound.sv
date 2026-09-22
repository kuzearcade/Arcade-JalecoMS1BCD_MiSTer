// Jaleco Mega System 1 B/C sound subsystem: the second 68000, a YM2151 and
// two OKIM6295s.
//
// Sound CPU map (megasys1B_sound_map, shared by B and C):
//   000000-01FFFF  ROM
//   040000, 060000 read the latch FROM the main CPU, write the latch TO it
//                  -- both addresses do both, they are the same pair of
//                  latches seen twice
//   080000-080003  YM2151, LOW BYTE only (umask16 0x00ff)
//   0A0001         OKI 1 status read      0A0000-0A0003 OKI 1 write
//   0C0001         OKI 2 status read      0C0000-0C0003 OKI 2 write
//   0E0000-0EFFFF  RAM, mirrored at 0F0000
//
// Interrupts into the sound CPU:
//   * the YM2151's own IRQ pin raises level 4
//   * the main CPU writing the sound latch raises level 4 on System B
//     (soundlatch_w) and level 2 on System C (soundlatch_c_w -- "Cybattler
//     reads sound latch on irq 2")
//
// THE OKI STATUS HACK. MAME returns 0 from both OKI status registers unless
// the game is hachoo (`m_ignore_oki_status`, default 1), with the comment that
// it "fixes the music tempo in avspirit, 64street, astyanax etc. but makes
// most of the effects in hachoo disappear", and that a bootleg patched the
// game code to do the same. docs/PLAN.md section 5 carries this as an open
// question. It is modelled here because the reference does, and because gate
// (3) compares write COUNTS against that reference -- a real status register
// changes how often the game writes. `oki_status_real` exposes the other
// behaviour without editing this file.

module ms1_sound (
	input               clk,           // 48 MHz
	input               reset,
	input        [1:0]  mode,          // 0 = B, 1 = C
	input               oki_status_real,

	// latch from the main CPU
	input               latch_we,      // one pulse per main-CPU latch write
	// screen_flag bit 4: the main CPU holds the whole sound subsystem in reset
	// through this one bit -- the sound 68000, the YM2151 and both OKIs
	// (megasys1_v.cpp:253-267). Games use it between tunes, so without it the
	// music never stops and never restarts. See MS1-30.
	input               sreset,
	// HW_ROMS: rom_ready is the program cache; the two OKI stalls come from
	// their own caches and are ANDed into the chips' cen. jt6295 ignores
	// rom_ok, so without that AND it plays whatever byte happens to be on the
	// bus -- Sand Scorpion shipped 37.6 % stale sample bytes for a week.
	input               rom_ready,
	input               oki1_stall, oki2_stall,
	input       [15:0]  latch_data,
	output reg  [15:0]  latch_to_main,

	// sound program ROM, served by the caller
	output      [16:0]  rom_addr,      // word address, 128 KB
	input       [15:0]  rom_data,

	// sample ROMs
	output      [17:0]  oki1_rom_addr, oki2_rom_addr,
	input        [7:0]  oki1_rom_data, oki2_rom_data,

	output signed [15:0] snd_l, snd_r,

	// counters for M2 gate (3)
	// ---- savestate snapshot bus
	input               ss_active,
	input       [19:0]  ss_addr,
	input               ss_wr,
	input       [15:0]  ss_wdata,
	output reg  [15:0]  ss_rdata,
	input               ss_freeze,
	input               ss_resume,
	output              ss_parked,
	input               ss_replay,
	output reg          ss_replay_done,
	input               ss_hold,

	output reg  [31:0]  dbg_ym_writes, dbg_oki1_writes, dbg_oki2_writes,
	output      [23:0]  dbg_addr,
	output              dbg_acc, dbg_rw,
	output      [15:0]  dbg_wdata,
	output      [15:0]  dbg_rdata,
	output reg  [31:0]  dbg_phi1, dbg_cen, dbg_cenp1,
	output reg  [31:0]  dbg_ymirq, dbg_iack,
	// isolated taps for M2 gate (4)
	output signed [15:0] dbg_fm_l, dbg_fm_r,
	output signed [13:0] dbg_oki1, dbg_oki2
);
	// ------------------------------------------------------------ clocking
	// The sound CPU is 7 MHz and 48 is not a multiple of it, so phi1/phi2 come
	// from a fractional accumulator rather than a divider. The YM2151 is
	// exactly half the CPU clock and the OKIs are 4 MHz, which IS an exact
	// division of 48 (/12) -- so only this one domain needs the accumulator,
	// as docs/PLAN.md section 0 item 8 anticipated.
	localparam integer CLK_SYS = 48_000_000;
	localparam integer CPU_HZ  = 7_000_000;
	// 27 bits, NOT 25: the threshold constant is CLK_SYS - 2*CPU_HZ = 34e6,
	// which does not fit in 25 bits. Truncated it became 445568, the
	// accumulator cleared it almost every clock, and the whole sound domain
	// ran 3.3x fast -- see MS1-28. Any width here must hold CLK_SYS itself.
	reg [26:0] cpu_acc;
	reg        cpu_ph;
	reg        enPhi1, enPhi2;
	always @(posedge clk) begin
		enPhi1 <= 1'b0; enPhi2 <= 1'b0;
		if (reset) begin cpu_acc <= 27'd0; cpu_ph <= 1'b0; end
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd6)) cpu_acc[15:0] <= ss_wdata;
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd7)) begin
			cpu_ph <= ss_wdata[11]; cpu_acc[26:16] <= ss_wdata[10:0];
		end
		else if (ss_active) begin enPhi1 <= 1'b0; enPhi2 <= 1'b0; end
		else begin
			// two edges per CPU cycle
			if (cpu_acc >= 27'(CLK_SYS - 2 * CPU_HZ)) begin
				cpu_acc <= cpu_acc - 27'(CLK_SYS - 2 * CPU_HZ);
				cpu_ph  <= ~cpu_ph;
				if (cpu_ph) enPhi2 <= 1'b1; else enPhi1 <= 1'b1;
			end else cpu_acc <= cpu_acc + 27'(2 * CPU_HZ);
		end
	end

	// YM2151 at 3.5 MHz = half the CPU clock. jt51 wants cen AT the chip clock
	// and cen_p1 "at half the speed" (its own comment, jt51.v:28) -- i.e. a
	// 1.75 MHz enable aligned with every second cen, NOT a one-clock delay of
	// it. Getting this wrong runs the chip's timers fast, and megasys1.cpp:673
	// notes the YM2151 clock is what decides the music tempo -- so it lands
	// straight on the gate (3) write counts.
	reg [1:0] ymdiv;
	always @(posedge clk) if (reset) ymdiv <= 2'd0;
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd5)) ymdiv <= ss_wdata[5:4];
		else if (ss_hold) ymdiv <= ymdiv;
		else if (enPhi1) ymdiv <= ymdiv + 2'd1;
	wire ym_cen    = enPhi1 & (ymdiv[0] == 1'b1);
	wire ym_cen_p1 = enPhi1 & (ymdiv    == 2'd3);

	// OKIs at 4 MHz = 48/12 exactly.
	reg [3:0] okidiv;
	reg       oki_cen;
	always @(posedge clk) begin
		oki_cen <= 1'b0;
		if (reset) okidiv <= 4'd0;
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd5)) okidiv <= ss_wdata[3:0];
		else if (ss_hold) okidiv <= okidiv;
		else if (okidiv == 4'd11) begin okidiv <= 4'd0; oki_cen <= 1'b1; end
		else okidiv <= okidiv + 4'd1;
	end

	// Power-on reset OR the main CPU's screen_flag bit 4. The debug counters,
	// the clock dividers and the latches deliberately stay on `reset` alone:
	// MAME's write counts accumulate across a sound reset, and the clock does
	// not stop.
	wire snd_rst = reset | sreset;

	// --------------------------------------------------------------- 68000
	wire        eRWn, ASn, LDSn, UDSn, VMAn, FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
	wire [15:0] oEdb;
	wire [23:1] eab;
	reg  [15:0] iEdb;

	wire [23:0] a = {eab, 1'b0} & 24'h0FFFFF;
	wire        as_active = ~ASn & (~LDSn | ~UDSn);
	wire        we = as_active & ~eRWn;

	wire sel_rom   = (a < 24'h020000);
	wire srom_stall = as_active & sel_rom & ~rom_ready;
	wire sel_latch = (a >= 24'h040000 && a < 24'h040002) ||
	                 (a >= 24'h060000 && a < 24'h060002);
	wire sel_ym    = (a >= 24'h080000 && a < 24'h080004);
	wire sel_oki1  = (a >= 24'h0A0000 && a < 24'h0A0004);
	wire sel_oki2  = (a >= 24'h0C0000 && a < 24'h0C0004);
	wire sel_ram   = (a >= 24'h0E0000 && a < 24'h100000);   // + mirror

	assign rom_addr = a[17:1];

	reg [15:0] sram [0:32767];
	wire [14:0] ram_i = a[15:1];

	wire ss_sram  = ss_active & (ss_addr[19:15] == 5'h02);   // 0x10000 32768
	wire ss_smisc = ss_active & (ss_addr[19:4]  == 16'h1D02); // 0x1D020
	wire ss_spark = ss_active & (ss_addr[19:4]  == 16'h1D03); // 0x1D030
	wire ss_ymsh  = ss_active & (ss_addr[19:8]  == 12'h1E0);  // 0x1E000 256
	wire ss_w     = ss_active & ss_wr;

	always @(posedge clk) begin
		if (ss_w & ss_sram)       sram[ss_addr[14:0]] <= ss_wdata;
		else if (we && sel_ram)   sram[ram_i] <= oEdb;
	end

	// ------------------------------------------------------------ latches
	reg [15:0] latch_from_main;
	always @(posedge clk) begin
		if (reset) begin latch_from_main <= 16'd0; latch_to_main <= 16'd0; end
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd0)) latch_from_main <= ss_wdata;
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd1)) latch_to_main   <= ss_wdata;
		else begin
			if (latch_we) latch_from_main <= latch_data;
			if (we && sel_latch) latch_to_main <= oEdb;
		end
	end

	// --------------------------------------------------------------- chips
	wire  [7:0] ym_dout;
	wire        ym_irq_n;
	wire signed [15:0] ym_l, ym_r;

	// one write strobe per bus cycle, not per clock
	reg as_d;
	wire acc_edge = as_active & ~as_d;
	always @(posedge clk) as_d <= as_active;

	always @(posedge clk) begin
		if (reset) begin dbg_phi1<=0; dbg_cen<=0; dbg_cenp1<=0; end
		else begin
			if (enPhi1)    dbg_phi1  <= dbg_phi1  + 1;
			if (ym_cen)    dbg_cen   <= dbg_cen   + 1;
			if (ym_cen_p1) dbg_cenp1 <= dbg_cenp1 + 1;
		end
	end
	assign dbg_wdata = oEdb;
	assign dbg_rdata = iEdb;
	assign dbg_addr = a;
	assign dbg_acc  = acc_edge;
	assign dbg_rw   = eRWn;

	reg ym_wr, oki1_wr, oki2_wr;
	reg [7:0] chip_din;
	reg       chip_a0;
	always @(posedge clk) begin
		oki1_wr <= 1'b0; oki2_wr <= 1'b0;
		// jt51 wants `write` driven from the CPU's cs/wr for the whole bus
		// cycle, the way the real chip is wired: its register block runs on the
		// raw clock, but `busy` is sampled only on cen (jt51_mmr.v:264), which
		// is 1.75 MHz here -- about one pulse every 27 clk_sys. A one-clock
		// strobe therefore still wrote the registers but NEVER raised busy, so
		// the driver's busy-poll loop never waited and it took a different path
		// through the music code. See MS1-29. jt6295 is the opposite: it
		// edge-detects wrn on the full clock, so the OKI strobes stay one cycle.
		// Held until one cen_p1 has actually sampled it: the 68000's data strobe
		// is only ~10 clk_sys wide, while cen_p1 comes every 27, so tying the
		// strobe to the bus cycle still missed busy about two times in three.
		if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd3)) chip_din <= ss_wdata[7:0];
		if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd5)) chip_a0  <= ss_wdata[6];
		if (ym_wr & ym_cen_p1) ym_wr <= 1'b0;
		if (reset) begin
			ym_wr <= 1'b0;
			dbg_ym_writes <= 32'd0; dbg_oki1_writes <= 32'd0; dbg_oki2_writes <= 32'd0;
		end else if (acc_edge & ~eRWn) begin
			chip_din <= oEdb[7:0];      // every chip is on the LOW byte
			chip_a0  <= a[1];
			if (sel_ym)   begin ym_wr   <= 1'b1; dbg_ym_writes   <= dbg_ym_writes + 1; end
			if (sel_oki1) begin oki1_wr <= 1'b1; dbg_oki1_writes <= dbg_oki1_writes + 1; end
			if (sel_oki2) begin oki2_wr <= 1'b1; dbg_oki2_writes <= dbg_oki2_writes + 1; end
		end
	end

	// ---- YM2151 register shadow. jt51 has no savestate of its own, so every
	// register write is mirrored here and replayed into the chip on a load.
	// This restores the chip's REGISTERS, not its envelope phase -- which is
	// the usual savestate compromise and is invisible to this milestone's
	// gate, which compares pixels.
	reg [7:0] ymsh [0:255];
	reg [7:0] ym_reg_sel;
	wire ym_wr_pulse = acc_edge & ~eRWn & sel_ym;
	always @(posedge clk) begin
		if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd4)) ym_reg_sel <= ss_wdata[7:0];
		if (ss_w & ss_ymsh) ymsh[ss_addr[7:0]] <= ss_wdata[7:0];
		else if (ym_wr_pulse) begin
			if (!chip_a0) ym_reg_sel <= chip_din;
			else          ymsh[ym_reg_sel] <= chip_din;
		end
	end

	// Replay: two chip writes per register -- select, then data -- one per
	// cen_p1 so jt51 sees each exactly once, for all 256 registers.
	reg [7:0] rp_idx;
	reg       rp_phase, rp_run, rp_done;
	always @(posedge clk) begin
		if (reset) begin
			rp_run <= 1'b0; rp_idx <= 8'd0; rp_phase <= 1'b0;
			rp_done <= 1'b0; ss_replay_done <= 1'b0;
		end else begin
			if (!ss_replay) begin rp_done <= 1'b0; ss_replay_done <= 1'b0; end
			else if (!rp_run && !rp_done) begin
				rp_run <= 1'b1; rp_idx <= 8'd0; rp_phase <= 1'b0;
			end
			if (rp_run && ym_cen_p1) begin
				if (!rp_phase) rp_phase <= 1'b1;
				else begin
					rp_phase <= 1'b0;
					if (rp_idx == 8'd255) begin
						rp_run <= 1'b0; rp_done <= 1'b1; ss_replay_done <= 1'b1;
					end else rp_idx <= rp_idx + 8'd1;
				end
			end
		end
	end

	jt51 u_ym (
		.rst(snd_rst), .clk(clk), .cen(ym_cen), .cen_p1(ym_cen_p1),
		.cs_n(1'b0), .wr_n(~(ym_wr | rp_run)), .a0(rp_run ? rp_phase : chip_a0),
		.din(rp_run ? (rp_phase ? ymsh[rp_idx] : rp_idx) : chip_din),
		.dout(ym_dout), .ct1(), .ct2(), .irq_n(ym_irq_n),
		.sample(), .left(), .right(),
		.xleft(ym_l), .xright(ym_r)
	);

	wire [7:0] oki1_dout, oki2_dout;
	wire signed [13:0] oki1_snd, oki2_snd;

	jt6295 #(.INTERPOL(0)) u_oki1 (
		.rst(snd_rst), .clk(clk), .cen(oki_cen & ~oki1_stall), .ss(1'b1),
		.wrn(~oki1_wr), .din(chip_din), .dout(oki1_dout),
		.rom_addr(oki1_rom_addr), .rom_data(oki1_rom_data), .rom_ok(1'b1),
		.sound(oki1_snd), .sample()
	);
	jt6295 #(.INTERPOL(0)) u_oki2 (
		.rst(snd_rst), .clk(clk), .cen(oki_cen & ~oki2_stall), .ss(1'b1),
		.wrn(~oki2_wr), .din(chip_din), .dout(oki2_dout),
		.rom_addr(oki2_rom_addr), .rom_data(oki2_rom_data), .rom_ok(1'b1),
		.sound(oki2_snd), .sample()
	);

	assign dbg_fm_l = ym_l;
	assign dbg_fm_r = ym_r;
	assign dbg_oki1 = oki1_snd;
	assign dbg_oki2 = oki2_snd;

	// ------------------------------------------------------------- readback
	always @* begin
		if      (sel_mon)   iEdb = mon_data;   // the park monitor's overlay
		else if (sel_rom)   iEdb = rom_data;
		else if (sel_ram)   iEdb = sram[ram_i];
		else if (sel_latch) iEdb = latch_from_main;
		else if (sel_ym)    iEdb = {8'h00, ym_dout};
		// MAME's oki_status_r returns 0 unless m_ignore_oki_status is cleared
		else if (sel_oki1)  iEdb = oki_status_real ? {8'h00, oki1_dout} : 16'h0000;
		else if (sel_oki2)  iEdb = oki_status_real ? {8'h00, oki2_dout} : 16'h0000;
		else                iEdb = 16'h0000;
	end

	// ---- savestate readback and scalar state
	reg [15:0] ss_smisc_rdata;
	always @* begin
		case (ss_addr[3:0])
			4'd0: ss_smisc_rdata = latch_from_main;
			4'd1: ss_smisc_rdata = latch_to_main;
			4'd2: ss_smisc_rdata = {13'd0, irq4_h, irq2_h, ym_irq_d};
			4'd3: ss_smisc_rdata = {8'd0, chip_din};
			4'd4: ss_smisc_rdata = {8'd0, ym_reg_sel};
			4'd5: ss_smisc_rdata = {9'd0, chip_a0, ymdiv, okidiv};
			4'd6: ss_smisc_rdata = cpu_acc[15:0];
			4'd7: ss_smisc_rdata = {4'd0, cpu_ph, cpu_acc[26:16]};
			default: ss_smisc_rdata = 16'h0000;
		endcase
	end
	// Every scalar below is restored INSIDE the block that owns it. A
	// separate restore block is a multiple driver: Verilator accepts it
	// silently, Quartus refuses to elaborate. See MS1-34.
	always @(posedge clk) begin
		if      (ss_sram)  ss_rdata <= sram[ss_addr[14:0]];
		else if (ss_ymsh)  ss_rdata <= {8'd0, ymsh[ss_addr[7:0]]};
		else if (ss_spark) ss_rdata <= ss_spark_rdata;
		else if (ss_smisc) ss_rdata <= ss_smisc_rdata;
		else               ss_rdata <= 16'h0000;
	end

	// ----------------------------------------------------------- interrupts
	// HOLD_LINE, retired one per acknowledge CYCLE -- see MS1-23, which cost a
	// day on the main CPU for exactly this reason.
	wire iack = ~ASn & (FC0 & FC1 & FC2);
	reg iack_d;
	always @(posedge clk) iack_d <= iack;
	wire iack_edge = iack & ~iack_d;

	wire is_c = (mode == 2'd1);
	reg irq4_h, irq2_h, ym_irq_d;
	always @(posedge clk) begin
		ym_irq_d <= ~ym_irq_n;
		if (snd_rst) begin
			irq4_h <= 1'b0; irq2_h <= 1'b0;
			dbg_ymirq <= 32'd0; dbg_iack <= 32'd0;
		end
		else if (ss_w & ss_smisc & (ss_addr[3:0] == 4'd2)) begin
			irq4_h <= ss_wdata[2]; irq2_h <= ss_wdata[1]; ym_irq_d <= ss_wdata[0];
		end
		else begin
			if (~ym_irq_n & ~ym_irq_d) dbg_ymirq <= dbg_ymirq + 1;
			if (iack_edge)             dbg_iack  <= dbg_iack + 1;
			if (~ym_irq_n & ~ym_irq_d)      irq4_h <= 1'b1;   // YM2151 IRQ
			if (latch_we && !is_c)          irq4_h <= 1'b1;   // System B latch
			if (latch_we &&  is_c)          irq2_h <= 1'b1;   // System C latch
			if (iack_edge) begin
				if      (irq4_h) irq4_h <= 1'b0;
				else if (irq2_h) irq2_h <= 1'b0;
			end
		end
	end
	// ---- savestate: park the sound 68000. 0x020000-0x03FFFF is unmapped in
	// the sound map (ROM ends at 0x01FFFF, the latch starts at 0x040000).
	wire  [2:0] ipl_park;
	wire        sel_mon;
	wire [15:0] mon_data, ss_spark_rdata;
	ss_m68k_park #(.MON_BASE(15'h100)) u_spark (
		.clk(clk), .reset(reset), .phi(enPhi2),
		.park_req(ss_freeze), .parked(ss_parked), .resume(ss_resume),
		.eab(eab), .ASn(ASn), .eRWn(eRWn), .FC0(FC0), .FC1(FC1), .FC2(FC2),
		.oEdb(oEdb),
		.ipl_park(ipl_park), .sel_mon(sel_mon), .mon_data(mon_data),
		.ss_sel(ss_addr[1:0]), .ss_wr(ss_w & ss_spark), .ss_wdata(ss_wdata),
		.ss_rdata(ss_spark_rdata)
	);

	wire [2:0] ipl_game = irq4_h ? 3'd4 : irq2_h ? 3'd2 : 3'd0;
	wire [2:0] ipl = (ipl_park != 3'd0) ? ipl_park : ipl_game;

	// ---------------------------------------------------------------- mix
	// MAME: YM2151 routed at 0.80 to both channels, each OKI at 0.30.
	// 0.80 ~ 13/16 and 0.30 ~ 5/16; the OKI is 14-bit so it is shifted up two
	// places first to sit on the same scale as the FM.
	wire signed [21:0] fm_l   = $signed(ym_l) * 22'sd13;
	wire signed [21:0] fm_r   = $signed(ym_r) * 22'sd13;
	wire signed [21:0] pcm1   = ($signed(oki1_snd) <<< 2) * 22'sd5;
	wire signed [21:0] pcm2   = ($signed(oki2_snd) <<< 2) * 22'sd5;
	wire signed [21:0] mix_l  = (fm_l + pcm1 + pcm2) >>> 4;
	wire signed [21:0] mix_r  = (fm_r + pcm1 + pcm2) >>> 4;
	assign snd_l = (mix_l >  22'sd32767) ?  16'sd32767 :
	               (mix_l < -22'sd32768) ? -16'sd32768 : mix_l[15:0];
	assign snd_r = (mix_r >  22'sd32767) ?  16'sd32767 :
	               (mix_r < -22'sd32768) ? -16'sd32768 : mix_r[15:0];

	fx68k u_scpu (
		.clk(clk), .HALTn(1'b1), .extReset(snd_rst), .pwrUp(snd_rst),
		.enPhi1(enPhi1), .enPhi2(enPhi2),
		.eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn), .E(), .VMAn(VMAn),
		.FC0(FC0), .FC1(FC1), .FC2(FC2), .BGn(BGn),
		.oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
		.DTACKn(~(as_active & ~iack & ~srom_stall)), .VPAn(~iack),
		.BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
		.IPL0n(~ipl[0]), .IPL1n(~ipl[1]), .IPL2n(~ipl[2]),
		.iEdb(iEdb), .oEdb(oEdb), .eab(eab)
	);
endmodule
