// Jaleco Mega System 1 main-CPU subsystem: the 68000, the board decode, the
// scanline interrupt timer and the protection MCU.
//
// Built to be compared against MAME's own main-CPU bus trace
// (sim/oracle/ms1_bustrace.lua), which is docs/PLAN.md M2 gate (1).
//
// Decode, System B (megasys1B_map, global_mask 0xFFFFF):
//   000000-03FFFF  ROM
//   044000         active_layers (w)
//   044008-04400D  layer 2 scroll
//   044100         sprite_flag
//   044200-044205  layer 0 scroll
//   044208-04420D  layer 1 scroll
//   044300         screen_flag (w)
//   044308         sound latch (w)
//   048000-0487FF  palette
//   04E000-04FFFF  object RAM
//   050000-053FFF  scroll 0 VRAM
//   054000-057FFF  scroll 1 VRAM
//   058000-05BFFF  scroll 2 VRAM
//   060000-06FFFF  work RAM, MIRRORED at 070000 -- and the mirror is what
//                  the games actually use: 340k of avspirit's first 1.5M
//                  accesses are at 07xxxx and none at 06xxxx.
//   080000-0BFFFF  ROM (maincpu + 0x40000)
//   0E0000         protection port
//
// System C moves everything (0C2000 video regs, 0F8000 palette, 0D2000
// object RAM, 0E0000/0E8000/0F0000 VRAM with +0x4000 mirrors, 1C0000 work RAM
// mirrored +0x30000, 0D8000 protection) and masks to 21 bits.
//
// Decode, System D (megasys1D_map). It is a DIFFERENT BOARD, not a variant:
// one 68000 and no sound CPU, no YM at all, ONE OKIM6295 the main CPU drives
// itself, TWO scroll layers instead of three, and a protection port of its
// own at 0x100000 that doubles as the sample-bank latch.
//   000000-03FFFF  ROM (one bank; there is no second one)
//   0C2000-0C2005  layer 0 scroll     0C2008-0C200D  layer 1 scroll
//   0C2108         sprite bank -- MAME maps this .nopw(), so it is DECODED
//                  AND DISCARDED, not left to fall through
//   0C2200         sprite_flag        0C2208         active_layers (w)
//   0C2308         screen_flag (w)
//   0CA000-0CBFFF  object RAM
//   0D0000-0D3FFF  scroll 1 VRAM  ("scroll2")
//   0D8000-0D87FF  palette, MIRRORED over 0x3000 (so 0D9000, 0DA000, 0DB000
//                  are the same 2 KB; 0D8800-0D8FFF is NOT -- bit 11 is not
//                  in the mirror mask and is therefore unmapped)
//   0E0000         DSW   (read, 16 bits: one port, not two 8-bit ones)
//   0E8000-0EBFFF  scroll 0 VRAM  ("scroll1")
//   0F0000         SYSTEM (read, 16 bits -- the six buttons are in the HIGH
//                  byte, which is why in_sys_hi exists; MS1-42)
//   0F8001         OKIM6295, low byte only
//   100000         protection (installed by init_peekaboo, not in the map)
//   1F0000-1FFFFF  work RAM; sprite RAM is still work RAM + 0x8000 bytes
// The two scroll windows are INVERTED with respect to their addresses: the
// LOWER one (0D0000) is MAME's m_tmap[1], the HIGHER one (0E8000) is
// m_tmap[0]. Wiring them by address order silently swaps the two layers.
//
// System D declares NO global_mask, so unlike B and C the full 24-bit
// address is decoded.
//
// WORK RAM BYTE WRITES MIRROR INTO BOTH HALVES. MAME's ram_w says so in
// capitals -- "DON'T use COMBINE_DATA ... 64th Street and Chimera Beast rely
// on this for attract inputs" -- so a byte write puts the same byte in both
// lanes rather than leaving the other alone. This is a real hardware quirk
// and not an emulator shortcut.
//
// Interrupts, System B and C with the MCU: scanline 96 raises level 1,
// scanline 240 raises level 4, and the MCU raises level 2 when it reads
// bank 7 of its own space. All are HOLD_LINE in MAME, i.e. asserted until
// the CPU acknowledges.

module ms1_main (
	input               clk,
	input               reset,
	input        [1:0]  mode,          // 0 = B, 1 = C
	// Protection, from the .mra's game-mode byte bits 6:5:
	//   0 real MCU, 1 simulated (iosim), 2 none, 3 System D's own.
	input        [1:0]  prot,

	// program ROM, served by the caller (512 KB, word addressed)
	output      [18:0]  rom_addr,
	input       [15:0]  rom_data,
	// HW_ROMS: high when rom_data reflects rom_addr. The reference sim ties it
	// high and the timing is unchanged; on the SDRAM path a miss withholds
	// DTACK, which is the stall the M3 `romwait` gate measures.
	input               rom_ready,

	// MCU internal ROM load
	output      [13:0]  mcu_rom_addr,
	input        [7:0]  mcu_rom_data,
	input               mcu_rom_ready,

	// board inputs. in_dsw2:in_dsw1 is also System D's single 16-bit DSW
	// port, and in_sys_hi is the high half of its 16-bit SYSTEM port --
	// unused, and expected to be zero, on every B and C set.
	input        [7:0]  in_p1, in_p2, in_dsw1, in_dsw2, in_system,
	input        [7:0]  in_sys_hi,

	// System D's OKIM6295, driven by THIS CPU (there is no sound CPU on that
	// board). oki_we is one pulse per write at 0F8001; oki_bank is the sample
	// bank the protection latch selects; oki_status is the chip's own read
	// data, which System D reads for real -- the ignore-status hack in
	// ms1_sound applies to the B/C sound CPU's ports, not to this one.
	output reg          oki_we,
	output reg   [7:0]  oki_wdata,
	output reg   [2:0]  oki_bank,
	input        [7:0]  oki_status,

	// video timing in, so the interrupt timer and the MCU's INT1 are real
	input        [8:0]  vcount,
	input               vtick,         // one pulse per scanline

	// bus trace
	output reg  [23:0]  tr_addr,
	output reg  [15:0]  tr_data,
	output reg          tr_we,
	output reg          tr_valid,

	// ---- video-side read ports (the CPU owns these memories; the video
	// only ever reads them, so one extra read port each is enough)
	input       [12:0]  v0_rd_addr, v1_rd_addr, v2_rd_addr,
	output reg  [15:0]  v0_rd_data, v1_rd_data, v2_rd_data,
	input        [9:0]  pal_rd_addr,
	output reg  [15:0]  pal_rd_data,

	// Object and sprite RAM as the VIDEO sees them: TWO frames behind the
	// CPU. megasys1_v.cpp's screen_vblank does buffer2 <- buffer <- live
	// every vblank and draw_sprites reads buffer2, so the sprites on screen
	// are those the CPU wrote two frames ago. Sprite RAM is not a named
	// region at all -- it is work RAM + 0x8000 (&m_ram[0x8000/2]).
	input               vbl_rise,      // one pulse at the start of vblank
	input       [11:0]  obj_rd_addr,
	output reg  [15:0]  obj_rd_data,
	input       [11:0]  spr_rd_addr,
	output reg  [15:0]  spr_rd_data,

	// video registers, decoded for the video block
	output      [15:0]  reg_active_layers, reg_sprite_flag,
	output      [15:0]  reg_sprite_bank,   reg_screen_flag,
	output      [15:0]  reg_t0_sx, reg_t0_sy, reg_t0_ctrl,
	output      [15:0]  reg_t1_sx, reg_t1_sy, reg_t1_ctrl,
	output      [15:0]  reg_t2_sx, reg_t2_sy, reg_t2_ctrl,

	// probes
	output reg  [23:0]  dbg_ramw_addr,
	output reg  [15:0]  dbg_ramw_data,
	output reg          dbg_ramw,
	// sound latch out: one pulse per main-CPU write to the sound latch
	// (044308 on System B, 0C8000 on System C), carrying the command.
	output reg          slatch_we,
	output reg  [15:0]  slatch_data,

	output reg  [31:0]  dbg_acc, dbg_vregw, dbg_vramw,
	// ---- savestate snapshot bus (docs/m3-gate4.md has the image map).
	// Only meaningful while every CPU is parked: ss_active hands the RAM
	// ports to the engine.
	input               ss_active,
	input       [19:0]  ss_addr,
	input               ss_wr,
	input       [15:0]  ss_wdata,
	output reg  [15:0]  ss_rdata,
	input               ss_freeze,
	input               ss_resume,
	input        [1:0]  ss_rst_dbg,   // bit 0 (of this slice) = MCU
	input               ss_hold,      // the whole savestate window
	output              ss_m68k_parked,
	output              ss_mcu_frozen,

	output reg  [31:0]  dbg_irq2, dbg_int1e,
	output reg  [31:0]  dbg_romwait, dbg_romacc,
	output reg  [31:0]  dbg_mcuacc, dbg_mcubank,
	output      [15:0]  dbg_mcu_pc,
	output              dbg_mcu_halt, dbg_mcu_if,
	output      [10:0]  dbg_mcu_irqp, dbg_mcu_mask
);
	// ------------------------------------------------------- 68000 clocking
	// enPhi1/enPhi2 must strictly alternate; fx68k wedges mid-cycle otherwise.
	reg [2:0] phdiv;
	wire [2:0] phdiv_max = (mode == 2'd1) ? 3'd1 : 3'd2;   // 12 MHz : 8 MHz
	reg enPhi1, enPhi2, phase;
	always @(posedge clk) begin
		if (reset) begin phdiv <= 3'd0; phase <= 1'b0; enPhi1 <= 1'b0; enPhi2 <= 1'b0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd4)) phdiv <= ss_wdata[2:0];
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd5)) phase <= ss_wdata[1];
		else if (ss_active) begin enPhi1 <= 1'b0; enPhi2 <= 1'b0; end
		else begin
			enPhi1 <= 1'b0; enPhi2 <= 1'b0;
			if (phdiv == phdiv_max) begin
				phdiv <= 3'd0;
				phase <= ~phase;
				if (phase) enPhi2 <= 1'b1; else enPhi1 <= 1'b1;
			end else phdiv <= phdiv + 3'd1;
		end
	end

	wire        eRWn, ASn, LDSn, UDSn, VMAn, FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
	wire [15:0] oEdb;
	wire [23:1] eab;
	reg  [15:0] iEdb;

	wire [23:0] byte_addr = {eab, 1'b0};
	wire        as_active = ~ASn & (~LDSn | ~UDSn);

	// ------------------------------------------------------------- decode
	// `mode` idles at 3 until the .mra's <switches> block arrives (MS1-53),
	// so these are written as exact compares: an undecoded mode selects no
	// region at all rather than falling into a neighbour's map.
	wire is_b = (mode == 2'd0);
	wire is_c = (mode == 2'd1);
	wire is_d = (mode == 2'd2);

	// ---- simulated protection (prot == 1): state and the per-game command
	// table. The responder itself is further down, with the rest of the
	// protection logic; these are up here because the savestate readback and
	// the CPU read mux both need them. See that block for what the table is.
	wire       use_iosim  = (prot == 2'd1);
	// monkelf is the only shipped set with prot == 2 (edfbl is excluded).
	wire       is_monkelf = (prot == 2'd2);
	wire [7:0] io_c0 = is_c ? 8'h56 : 8'h51;
	wire [7:0] io_c3 = is_c ? 8'h55 : 8'h54;
	wire [7:0] io_c4 = is_c ? 8'h54 : 8'h55;
	wire [7:0] io_c5 = is_c ? 8'hFA : 8'hFC;
	reg  [7:0] io_latched;
	reg        io_irq2;
	reg        io_int1_d;

	// ---- System D's protection (prot == 3): the latch and its read
	// decode. Declared here for the same reason as the block above -- the
	// CPU read mux and the savestate readback are both upstream of the
	// responder, which is down with the rest of the protection logic.
	reg  [15:0] pk_latch;
	reg         pk_irq4;
	reg         oki_we_d;
	wire [15:0] pk_rd = (pk_latch == 16'h0002) ? 16'h0003
	                  : (pk_latch == 16'h0051) ? {8'h00, in_p1}
	                  : (pk_latch == 16'h0052) ? {8'h00, in_p2}
	                                           : pk_latch;

	// THE GLOBAL ADDRESS MASK IS PART OF THE DECODE. MAME's maps open with
	// map.global_mask(0xfffff) on System B and 0x1fffff on System C, and the
	// board really does ignore the high address lines. It matters from the
	// very first instruction: 64street's reset stack pointer is 0, so its
	// first push is to 0xFFFFFC, which is nothing at all unmasked and is
	// work RAM at 0x1FFFFC once masked. Decoding the raw 24-bit address
	// silently dropped every one of those writes -- and because the harness
	// masked the address only on its way into the TRACE, the trace looked
	// correct while the memory behind it was not being written.
	// System D declares no global_mask at all, so it decodes all 24 bits.
	wire [23:0] amask = is_d ? 24'hFFFFFF : is_c ? 24'h1FFFFF : 24'h0FFFFF;
	wire [23:0] a = byte_addr & amask;

	// System B
	wire b_rom0 = is_b   & (a < 24'h040000);
	wire b_rom1 = is_b   & (a >= 24'h080000) & (a < 24'h0C0000);
	wire b_vreg = is_b   & (a >= 24'h044000) & (a < 24'h044400);
	wire b_pal  = is_b   & (a >= 24'h048000) & (a < 24'h048800);
	wire b_obj  = is_b   & (a >= 24'h04E000) & (a < 24'h050000);
	wire b_v0   = is_b   & (a >= 24'h050000) & (a < 24'h054000);
	wire b_v1   = is_b   & (a >= 24'h054000) & (a < 24'h058000);
	wire b_v2   = is_b   & (a >= 24'h058000) & (a < 24'h05C000);
	wire b_ram  = is_b   & (a >= 24'h060000) & (a < 24'h080000);   // + mirror
	wire b_prot = is_b   & (a >= 24'h0E0000) & (a < 24'h0E0002);
	// monkelf has no protection device: the bootleg reads the five input
	// ports DIRECTLY, at their own addresses just above the port the
	// protected boards use (MAME's megasys1B_monkelf_map). MS1-55.
	//   0E0002 P1   0E0004 P2   0E0006 DSW1   0E0008 DSW2   0E000A SYSTEM
	wire b_mkin = is_b   & is_monkelf & (a >= 24'h0E0002) & (a < 24'h0E000C);
	reg [7:0] mkin_q;
	always @(*) case (a[3:1])
		3'd1:    mkin_q = in_p1;
		3'd2:    mkin_q = in_p2;
		3'd3:    mkin_q = in_dsw1;
		3'd4:    mkin_q = in_dsw2;
		default: mkin_q = in_system;      // 3'd5
	endcase

	// System C
	wire c_rom0 = is_c & (a < 24'h080000);
	wire c_vreg = is_c & (a >= 24'h0C2000) & (a < 24'h0C2400);
	wire c_pal  = is_c & (a >= 24'h0F8000) & (a < 24'h0F8800);
	wire c_obj  = is_c & (a >= 24'h0D2000) & (a < 24'h0D4000);
	wire c_v0   = is_c & (a >= 24'h0E0000) & (a < 24'h0E8000);
	wire c_v1   = is_c & (a >= 24'h0E8000) & (a < 24'h0F0000);
	wire c_v2   = is_c & (a >= 24'h0F0000) & (a < 24'h0F8000);
	wire c_ram  = is_c & (a >= 24'h1C0000) & (a < 24'h200000);
	wire c_prot = is_c & (a >= 24'h0D8000) & (a < 24'h0D8002);

	// System D. See the map in the header; the two things that are easy to
	// get wrong are the palette mirror (0x3000, which does NOT include bit
	// 11) and the layer order (0D0000 is layer 1, 0E8000 is layer 0).
	wire d_rom0 = is_d & (a < 24'h040000);
	wire d_vreg = is_d & (a >= 24'h0C2000) & (a < 24'h0C2400);
	wire d_obj  = is_d & (a >= 24'h0CA000) & (a < 24'h0CC000);
	wire d_v1   = is_d & (a >= 24'h0D0000) & (a < 24'h0D4000);
	wire d_pal  = is_d & (a >= 24'h0D8000) & (a < 24'h0DC000) & ~a[11];
	wire d_dsw  = is_d & (a >= 24'h0E0000) & (a < 24'h0E0002);
	wire d_v0   = is_d & (a >= 24'h0E8000) & (a < 24'h0EC000);
	wire d_sys  = is_d & (a >= 24'h0F0000) & (a < 24'h0F0002);
	wire d_oki  = is_d & (a >= 24'h0F8000) & (a < 24'h0F8002);
	wire d_prot = is_d & (a >= 24'h100000) & (a < 24'h100002);
	wire d_ram  = is_d & (a >= 24'h1F0000) & (a < 24'h200000);

	wire sel_rom  = b_rom0 | b_rom1 | c_rom0 | d_rom0;
	wire sel_vreg = b_vreg | c_vreg | d_vreg;
	wire sel_pal  = b_pal  | c_pal  | d_pal;
	wire sel_obj  = b_obj  | c_obj  | d_obj;
	wire sel_v0   = b_v0   | c_v0   | d_v0;
	wire sel_v1   = b_v1   | c_v1   | d_v1;
	wire sel_v2   = b_v2   | c_v2;          // System D has no layer 2
	wire sel_ram  = b_ram  | c_ram  | d_ram;
	wire sel_prot = b_prot | c_prot | d_prot;

	// ROM word index: B's second bank continues the same region at +0x40000.
	//
	// HELD while the bus is not selecting ROM. rom_cache_n refetches on any
	// address change, so handing it the raw bus address makes every RAM, VRAM,
	// palette or I/O access start a speculative SDRAM read whose fill can land
	// between the 68000's DTACK sample and its data latch, corrupting the word
	// the CPU is in the middle of reading.
	//
	// This is invisible to every simulation here -- the reference sim indexes
	// an array, and the SDRAM model has no refresh -- and fatal on silicon:
	// the first board test had both CPUs executing garbage, the main one
	// wandering to 0x0FFFxx with vregw = 0 and vramw = 0, on a ROM image the
	// golden-byte path had already proven correct. Sand Scorpion's SS-12 and
	// NMK16's NMK-21 are the same bug, found the same way and fixed like this.
	// B's second bank (CPU 0x080000-0x0BFFFF) continues the same SDRAM region
	// straight after bank 0, at BYTE +0x40000 -- and rom_addr is a WORD index,
	// so that is word +0x20000, i.e. {2'b01, ...}. {2'b10, ...} is word
	// 0x40000 = byte 0x80000: one whole bank too far, at or past the end of
	// MAIN_SIZE_B, where every fetch reads zero.
	//
	// avspirit survives ~309 frames on that, because nothing dereferences the
	// bank-1 pointer table until a scene transition. Then ROM 0x0030C6 does
	// MOVEA.L ($080000).L,A0, gets 0x00000000 where MAME gets 0x0008000C,
	// indexes off the null base, and copies low-ROM opcodes (0x4E75 RTS,
	// 0x4DF9 LEA) into work RAM and on into the video registers -- which is
	// the 0x4E7F that lands in the layer-enable register. MS1-51.
	//
	// The golden-byte audit could not see this: it drives audit_addr straight
	// into rom_hw's a_main mux, bypassing rom_addr entirely, so it proves the
	// SDRAM and the cache and says nothing about the CPU's address arithmetic.
	wire [18:0] rom_addr_live = b_rom1 ? {2'b01, a[17:1]} : a[19:1];
	reg  [18:0] rom_addr_held;
	always @(posedge clk) if (sel_rom) rom_addr_held <= rom_addr_live;
	assign rom_addr = sel_rom ? rom_addr_live : rom_addr_held;

	// Hold the bus cycle until the program byte is actually there.
	wire rom_stall = as_active & sel_rom & ~rom_ready;

	// A registered array read is valid one clock after the address settles, so
	// DTACK is held for that clock. The 68000's bus cycle here is about 24
	// clk_sys (8 MHz from 48), so this does not lengthen it.
	reg  as_d1;
	always @(posedge clk) as_d1 <= as_active;
	wire arr_wait = as_active & eRWn & (sel_ram | sel_pal | sel_vreg | sel_obj
	                                  | sel_v0 | sel_v1 | sel_v2) & ~as_d1;
	always @(posedge clk) begin
		if (reset) begin dbg_romwait <= 32'd0; dbg_romacc <= 32'd0; end
		else begin
			if (rom_stall)                     dbg_romwait <= dbg_romwait + 32'd1;
			if (as_active & sel_rom & ~as_d_r) dbg_romacc  <= dbg_romacc  + 32'd1;
		end
	end
	reg as_d_r;
	always @(posedge clk) as_d_r <= as_active;

	// ------------------------------------------------------------ memories
	// TWO COPIES of work RAM, written identically on the same clock.
	// An M10K has two ports and one of them is the write (docs/PLAN.md 4.C.2),
	// and work RAM has two concurrent readers: the CPU, and the sprite-RAM
	// buffer copy -- sprite RAM lives at work-RAM word 0x4000, and the copy
	// runs during vblank while the CPU is still executing. Quartus reported
	// this as "uninferred due to asynchronous read logic" even though both
	// reads are synchronous; the real objection is the port count.
	reg [15:0] wram  [0:32767];   // read by the CPU and the savestate
	reg [15:0] wram_s[0:32767];   // read by the sprite buffer copy only
	// TWO COPIES of the palette (docs/m4-video-array-plan.md).
	// pal_v serves the video read, pal_c the CPU and the savestate -- which
	// are mutually exclusive, since the core is parked while an image streams.
	// One read and one write each, which is what an M10K can do.
	reg [15:0] pal_v [0:1023];
	reg [15:0] pal_c [0:1023];
	// TWO COPIES of object RAM: obj_v is read by the buffer copy, obj_c by the
	// CPU and the savestate. The copy sweep and the CPU run at the same time,
	// so these two readers are genuinely concurrent.
	reg [15:0] obj_v [0:4095];
	reg [15:0] obj_c [0:4095];
	reg [15:0] vr0  [0:8191];
	reg [15:0] vr1  [0:8191];
	reg [15:0] vr2  [0:8191];
	reg [15:0] vreg [0:511];

	wire [14:0] wram_i = is_c ? a[15:1] : a[15:1];
	wire  [9:0] pal_i  = a[10:1];
	wire [11:0] obj_i  = a[12:1];
	wire [12:0] v_i    = a[13:1];
	wire  [8:0] vreg_i = a[9:1];

	wire we = as_active & ~eRWn;
	wire [15:0] wdat = oEdb;
	// the work-RAM byte-write quirk (see header)
	wire [15:0] ram_wdat = (~LDSn & ~UDSn) ? wdat
	                     : (~UDSn) ? {wdat[15:8], wdat[15:8]}
	                               : {wdat[7:0],  wdat[7:0]};

	// ---- savestate region decode. Word addresses in the image; every base
	// is aligned to its own size so each select is a prefix compare.
	wire ss_wram = ss_active & (ss_addr[19:15] == 5'h00);   // 0x00000 32768
	wire ss_vr0  = ss_active & (ss_addr[19:13] == 7'h04);   // 0x08000  8192
	wire ss_vr1  = ss_active & (ss_addr[19:13] == 7'h05);   // 0x0A000  8192
	wire ss_vr2  = ss_active & (ss_addr[19:13] == 7'h06);   // 0x0C000  8192
	wire ss_pal  = ss_active & (ss_addr[19:10] == 10'h38);  // 0x0E000  1024
	wire ss_vreg = ss_active & (ss_addr[19:9]  == 11'h72);  // 0x0E400   512
	wire ss_obj  = ss_active & (ss_addr[19:12] == 8'h0F);   // 0x0F000  4096
	wire ss_ob1  = ss_active & (ss_addr[19:12] == 8'h18);   // 0x18000  4096
	wire ss_ob2  = ss_active & (ss_addr[19:12] == 8'h19);
	wire ss_sb1  = ss_active & (ss_addr[19:12] == 8'h1A);
	wire ss_sb2  = ss_active & (ss_addr[19:12] == 8'h1B);
	wire ss_misc = ss_active & (ss_addr[19:4] == 16'h1D00);  // 0x1D000 scalars
	wire ss_mcu  = ss_active & (ss_addr[19:12] == 8'h1C);   // 0x1C000 the MCU
	wire [15:0] ss_mcu_rdata;
	wire ss_w    = ss_active & ss_wr;

	reg [15:0] rdat;
	always @(posedge clk) begin
		dbg_ramw <= we & sel_ram;
		dbg_ramw_data <= ram_wdat;
		dbg_ramw_addr <= a;
		dbg_ramw_data <= ram_wdat;
		if (ss_w) begin
			// The engine owns the ports while it is streaming an image down.
			if (ss_wram) begin
				wram  [ss_addr[14:0]] <= ss_wdata;
				wram_s[ss_addr[14:0]] <= ss_wdata;
			end
			if (ss_pal) begin
				pal_v[ss_addr[9:0]] <= ss_wdata;
				pal_c[ss_addr[9:0]] <= ss_wdata;
			end
			if (ss_vreg) vreg[ss_addr[8:0]]  <= ss_wdata;
			if (ss_obj) begin
				obj_v[ss_addr[11:0]] <= ss_wdata;
				obj_c[ss_addr[11:0]] <= ss_wdata;
			end
		end else if (we) begin
			if (sel_ram) begin
				wram  [wram_i] <= ram_wdat;
				wram_s[wram_i] <= ram_wdat;
			end
			if (sel_pal) begin
				pal_v[pal_i] <= wdat;
				pal_c[pal_i] <= wdat;
			end
			if (sel_obj) begin
				obj_v[obj_i] <= wdat;
				obj_c[obj_i] <= wdat;
			end
			if (sel_vreg) vreg[vreg_i] <= wdat;
		end
	end

	// ---- the scalar state: everything that is neither a RAM nor inside a
	// CPU. A savestate that restores every array and forgets these comes back
	// with the right picture and the wrong interrupt timing.
	reg [15:0] ss_misc_rdata;
	always @* begin
		case (ss_addr[3:0])
			4'd0: ss_misc_rdata = {2'd0, bufi, buf_busy};
			4'd1: ss_misc_rdata = {12'd0, irq1_h, irq2_h, irq4_h, iack_d};
			4'd2: ss_misc_rdata = {12'd0, oki_we_d, int1_dd, slatch_d, prot_we_pulse};
			4'd3: ss_misc_rdata = {13'd0, mdiv};
			4'd4: ss_misc_rdata = {13'd0, phdiv};
			4'd5: ss_misc_rdata = {14'd0, phase, as_d};
			4'd6: ss_misc_rdata = {7'd0, io_int1_d, io_latched};
			// System D's protection latch, and its OKI bank + last byte
			4'd7: ss_misc_rdata = pk_latch;
			4'd8: ss_misc_rdata = {oki_wdata, 5'd0, oki_bank};
			default: ss_misc_rdata = 16'h0000;
		endcase
	end
	// NOTE: every scalar above is restored INSIDE the block that owns it.
	// A separate restore block would be a second driver, and the owning
	// block wins on the next clock -- the restore then does nothing at all,
	// silently. The image loopback is what exposed this: 4 words of this
	// region did not read back what had just been written to them.

	// ---- savestate readback, registered once here (the core registers it
	// again, which is still inside the engine's RD_LAT).
	always @(posedge clk) begin
		if      (ss_wram) ss_rdata <= wram_q;
		else if (ss_vr0)  ss_rdata <= vr0_q;
		else if (ss_vr1)  ss_rdata <= vr1_q;
		else if (ss_vr2)  ss_rdata <= vr2_q;
		else if (ss_pal)  ss_rdata <= pal_q;
		else if (ss_vreg) ss_rdata <= vreg_q;
		else if (ss_obj)  ss_rdata <= objc_q;
		else if (ss_ob1)  ss_rdata <= ob1_q;
		else if (ss_ob2)  ss_rdata <= ob2_q;
		else if (ss_sb1)  ss_rdata <= sb1_q;
		else if (ss_sb2)  ss_rdata <= sb2_q;
		else if (ss_mcu)  ss_rdata <= ss_mcu_rdata;
		else if (ss_park) ss_rdata <= ss_park_rdata;
		else if (ss_misc) ss_rdata <= ss_misc_rdata;
		else              ss_rdata <= 16'h0000;
	end

	// ---- work RAM read port.
	// A single REGISTERED read, address muxed between the CPU and the
	// savestate engine, which never run at the same time (the core is parked
	// while an image streams). An asynchronous read would leave all 512 Kbit
	// of this as flip-flops -- MS1-37, docs/PLAN.md 4.C.1.
	wire [14:0] wram_rd_i = ss_active ? ss_addr[14:0] : wram_i;
	reg  [15:0] wram_q;
	always @(posedge clk) wram_q <= wram[wram_rd_i];

	wire  [9:0] pal_rd_i = ss_active ? ss_addr[9:0] : pal_i;
	reg  [15:0] pal_q;
	always @(posedge clk) pal_q <= pal_c[pal_rd_i];

	wire  [8:0] vreg_rd_i = ss_active ? ss_addr[8:0] : vreg_i;
	reg  [15:0] vreg_q;
	always @(posedge clk) vreg_q <= vreg[vreg_rd_i];

	wire [11:0] objc_rd_i = ss_active ? ss_addr[11:0] : obj_i;
	reg  [15:0] objc_q;
	always @(posedge clk) objc_q <= obj_c[objc_rd_i];

	// ---- the object/sprite buffer chain.
	// Each of these arrays had TWO readers, the copy sweep and the savestate
	// readback, so registering the copy read alone made three ports -- which
	// is exactly why the first attempt at this cost four arrays their
	// inference. One registered read each, address muxed, REPLACING both.
	wire [11:0] cp_i   = bufi[11:0];
	wire [11:0] ob1_ri = ss_active ? ss_addr[11:0] : cp_i;
	wire [11:0] ob2_ri = ss_active ? ss_addr[11:0] : cp_i;
	wire [11:0] sb1_ri = ss_active ? ss_addr[11:0] : cp_i;
	wire [11:0] sb2_ri = ss_active ? ss_addr[11:0] : cp_i;
	reg  [15:0] ob1_q, ob2_q, sb1_q, sb2_q, obj_q, wrms_q;
	reg  [11:0] cp_i_d;
	reg         cp_run;
	always @(posedge clk) begin
		ob1_q  <= obj_b1[ob1_ri];
		ob2_q  <= obj_b2[ob2_ri];
		sb1_q  <= spr_b1[sb1_ri];
		sb2_q  <= spr_b2[sb2_ri];
		obj_q  <= obj_v[cp_i];
		wrms_q <= wram_s[15'h4000 + {3'd0, cp_i}];
		cp_i_d <= cp_i;
		cp_run <= buf_busy;
	end

	// ---- scroll VRAM: one true-dual-port set each (NMK16 NMK-10's v3 shape).
	// Port A is the CPU and the savestate, coded as read-or-write with a
	// new-data read. Port B is the tilemap's read. Coding the CPU read as a
	// plain registered read instead makes the read old-data on a same-address
	// write, which Quartus 17 can only meet with a second full copy.
	wire        v0_we = (ss_w & ss_vr0) | (we & sel_v0);
	wire        v1_we = (ss_w & ss_vr1) | (we & sel_v1);
	wire        v2_we = (ss_w & ss_vr2) | (we & sel_v2);
	wire [12:0] v_ai  = ss_active ? ss_addr[12:0] : v_i;
	wire [15:0] v_ad  = ss_active ? ss_wdata      : wdat;
	reg  [15:0] vr0_q, vr1_q, vr2_q;
	always @(posedge clk) begin
		if (v0_we) begin vr0[v_ai] <= v_ad; vr0_q <= v_ad; end
		else       vr0_q <= vr0[v_ai];
		if (v1_we) begin vr1[v_ai] <= v_ad; vr1_q <= v_ad; end
		else       vr1_q <= vr1[v_ai];
		if (v2_we) begin vr2[v_ai] <= v_ad; vr2_q <= v_ad; end
		else       vr2_q <= vr2[v_ai];
	end

	// ---- video read ports.
	// COMBINATIONAL on purpose: ms1_tilemap and ms1_sprites register their
	// ADDRESS and expect the data in the following cycle, which is the bus
	// convention the whole video block was verified against in
	// sim/rtl/video_state. Making these registered instead would insert a
	// second cycle of latency and quietly shift every fetch by one.
	// (On hardware these become M10K reads with the same one-cycle shape.)
	always @(posedge clk) begin
		v0_rd_data <= vr0[v0_rd_addr];
		v1_rd_data <= vr1[v1_rd_addr];
		v2_rd_data <= vr2[v2_rd_addr];
	end

	// The palette read is REGISTERED, and on clk rather than on ce. The
	// address only changes on a pixel enable, so the data is valid one clock
	// later -- seven clocks before the next ce consumes it. No re-timing is
	// needed; registering it on ce WOULD have cost a pixel.
	always @(posedge clk) pal_rd_data <= pal_v[pal_rd_addr];

	// ---- the two-deep object/sprite buffers
	reg [15:0] obj_b1 [0:4095];
	reg [15:0] obj_b2 [0:4095];
	reg [15:0] spr_b1 [0:4095];
	reg [15:0] spr_b2 [0:4095];
	reg [12:0] bufi;
	reg        buf_busy;
	always @(posedge clk) begin
		if (reset) begin buf_busy <= 1'b0; bufi <= 13'd0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd0)) begin
			bufi <= ss_wdata[13:1]; buf_busy <= ss_wdata[0];
		end
		else if (vbl_rise) begin buf_busy <= 1'b1; bufi <= 13'd0; end
		else if (ss_w & (ss_ob1 | ss_ob2 | ss_sb1 | ss_sb2)) begin
			if (ss_ob1) obj_b1[ss_addr[11:0]] <= ss_wdata;
			if (ss_ob2) obj_b2[ss_addr[11:0]] <= ss_wdata;
			if (ss_sb1) spr_b1[ss_addr[11:0]] <= ss_wdata;
			if (ss_sb2) spr_b2[ss_addr[11:0]] <= ss_wdata;
		end
		else if (buf_busy) begin
			// The copy stays in THIS block: obj_b1 and spr_b1 are also written
			// by the savestate restore above, and a copy in a block of its own
			// would be a second driver.
			//
			// It was briefly pipelined -- each source registered on one clock,
			// written on the next -- to stop wram_s reading as an asynchronous
			// read. That worked for wram_s and COST inference on obj_b1,
			// obj_b2, spr_b1 and spr_b2, taking the total from six inferred
			// arrays to two, because registering obj_b1/spr_b1 here gave each
			// of them a second reader. One uninferred array is cheaper than
			// four, so it is reverted. See MS1-37.
			// written from the registered reads above, one index behind, so
			// every array here has exactly one read and one write
			if (cp_run) begin
				obj_b2[cp_i_d] <= ob1_q;
				obj_b1[cp_i_d] <= obj_q;
				spr_b2[cp_i_d] <= sb1_q;
				// sprite RAM is work RAM + 0x8000 BYTES, i.e. word 0x4000 up
				spr_b1[cp_i_d] <= wrms_q;
			end
			if (bufi == 13'd4095) buf_busy <= 1'b0;
			else bufi <= bufi + 13'd1;
		end
	end
	always @* begin
		obj_rd_data = obj_b2[obj_rd_addr];
		spr_rd_data = spr_b2[spr_rd_addr];
	end

	// ---- video registers, at their System B offsets (the harness feeds
	// System C's addresses through the same array, since vreg is indexed by
	// the low bits of whichever window the mode decoded)
	// VIDEO REGISTER SHADOWS.
	// These used to index `vreg` directly -- 26 constant-index reads across the
	// two modes. No M10K can serve that, so the array never inferred and its
	// 8 Kbit became flip-flops (MS1-37). They are discrete video registers, not
	// really a RAM, so each live one is shadowed here on write. That leaves
	// `vreg` itself with a single reader and costs 14 x 16 = 224 flip-flops.
	//
	// The shadow must follow BOTH writers of the array: the CPU and the
	// savestate restore, or a loaded state would show the previous scroll.
	reg [15:0] sh_active, sh_sflag, sh_sbank, sh_scrf;
	reg [15:0] sh_t0x, sh_t0y, sh_t0c, sh_t1x, sh_t1y, sh_t1c,
	           sh_t2x, sh_t2y, sh_t2c;
	wire [8:0] vw_i  = ss_w & ss_vreg ? ss_addr[8:0] : vreg_i;
	wire [15:0] vw_d = ss_w & ss_vreg ? ss_wdata     : wdat;
	wire        vw_e = (ss_w & ss_vreg) | (we & sel_vreg);
	// System D's register WORD indices are System C's, one for one: its
	// 0C2000 window has scroll 0 at words 0-2, scroll 1 at 4-6, sprite_flag
	// at 0x100, active_layers at 0x104 and screen_flag at 0x184. The only
	// differences are that word 0x84 (sprite bank) is mapped .nopw() and
	// that there is no layer 2 to write at all, so the same case serves
	// both and reg_sprite_bank stays zero below.
	always @(posedge clk) if (vw_e) begin
		if (is_c | is_d) begin
			case (vw_i)
				9'h104: sh_active <= vw_d;  9'h100: sh_sflag <= vw_d;
				9'h084: sh_sbank  <= vw_d;  9'h184: sh_scrf  <= vw_d;
				9'h000: begin sh_t0x <= vw_d; end
				9'h001: sh_t0y <= vw_d;     9'h002: sh_t0c <= vw_d;
				9'h004: sh_t1x <= vw_d;     9'h005: sh_t1y <= vw_d;
				9'h006: sh_t1c <= vw_d;     9'h080: sh_t2x <= vw_d;
				9'h081: sh_t2y <= vw_d;     9'h082: sh_t2c <= vw_d;
				default: ;
			endcase
		end else begin
			case (vw_i)
				9'h000: sh_active <= vw_d;  9'h080: sh_sflag <= vw_d;
				9'h180: sh_scrf   <= vw_d;
				// monkelf adjusts both X scrolls on the way in. MAME:
				//   scroll0: data -= ((data & 0x0f) > 0x0d) ? 0x10 : 0
				//   scroll1: data -= ((data & 0x0f) > 0x0b) ? 0x10 : 0
				// with the comment "code in routine $280 does this.
				// protection?" -- the bootleg's own fixup for whatever the
				// removed device used to do. MS1-55.
				9'h100: sh_t0x <= vw_d - ((is_monkelf && vw_d[3:0] > 4'hD) ? 16'h10 : 16'h0);
				9'h101: sh_t0y <= vw_d;
				9'h102: sh_t0c <= vw_d;
				9'h104: sh_t1x <= vw_d - ((is_monkelf && vw_d[3:0] > 4'hB) ? 16'h10 : 16'h0);
				9'h105: sh_t1y <= vw_d;     9'h106: sh_t1c <= vw_d;
				9'h004: sh_t2x <= vw_d;     9'h005: sh_t2y <= vw_d;
				9'h006: sh_t2c <= vw_d;
				default: ;
			endcase
		end
	end
	// System C's 0x104 is layer-1 X in B and active-layers in C, and 0x000 is
	// the reverse; the case above is split by mode for exactly that reason.
	assign reg_active_layers = sh_active;
	assign reg_sprite_flag   = sh_sflag;
	assign reg_sprite_bank   = is_c ? sh_sbank : 16'h0000;
	assign reg_screen_flag   = sh_scrf;
	assign reg_t0_sx         = sh_t0x;
	assign reg_t0_sy         = sh_t0y;
	assign reg_t0_ctrl       = sh_t0c;
	assign reg_t1_sx         = sh_t1x;
	assign reg_t1_sy         = sh_t1y;
	assign reg_t1_ctrl       = sh_t1c;
	assign reg_t2_sx         = sh_t2x;
	assign reg_t2_sy         = sh_t2y;
	assign reg_t2_ctrl       = sh_t2c;


	wire [7:0] mcu_prot_rd;
	// prot == 2 (none) reads back 0, which is what MAME's iosim state does
	// with no command table installed: the latch is never written.
	wire [7:0] prot_rd = (prot == 2'd1) ? io_latched
	                   : (prot == 2'd0) ? mcu_prot_rd : 8'h00;
	// System D's port is a full word (see pk_rd, below); B and C's is a byte
	// in the low half.
	wire [15:0] prot_rd16 = is_d ? pk_rd : {8'h00, prot_rd};
	always @* begin
		if      (sel_mon)  rdat = mon_data;   // the park monitor's overlay
		else if (sel_rom)  rdat = rom_data;
		else if (sel_ram)  rdat = wram_q;
		else if (sel_pal)  rdat = pal_q;
		else if (sel_obj)  rdat = objc_q;
		else if (sel_v0)   rdat = vr0_q;
		else if (sel_v1)   rdat = vr1_q;
		else if (sel_v2)   rdat = vr2_q;
		else if (sel_vreg) rdat = vreg_q;
		else if (b_mkin)   rdat = {8'hFF, mkin_q};   // MS1-55, high byte undeclared
		else if (sel_prot) rdat = prot_rd16;
		// System D reads its ports directly, and both are SIXTEEN bits: one
		// DSW port rather than B/C's two, and a SYSTEM port whose high byte
		// carries the six buttons.
		else if (d_dsw)    rdat = {in_dsw2, in_dsw1};
		else if (d_sys)    rdat = {in_sys_hi, in_system};
		// The OKI is on the low byte at the ODD address, so the word read
		// puts the status in [7:0] and leaves the high byte undriven.
		else if (d_oki)    rdat = {8'h00, oki_status};
		else               rdat = 16'h0000;
	end
	always @* iEdb = rdat;

	// --------------------------------------------------------- protection
	// The MCU runs at the MAIN CPU's clock: 8 MHz on System B, 12 MHz on
	// System C. From 48 MHz that is a divide by 6 and by 4 -- NOT the same
	// count as the 68000's phi divider, which is half a CPU cycle. Getting
	// this wrong by 2x does not break anything visibly: the MCU simply
	// answers the protection handshake twice as fast, and the IRQ 2 it
	// raises lands tens of accesses early.
	wire [2:0] mdiv_max = is_c ? 3'd3 : 3'd5;
	reg  [2:0] mdiv;
	always @(posedge clk) begin
		if (reset) mdiv <= 3'd0;
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd3)) mdiv <= ss_wdata[2:0];
		// NOT ss_hold: the MCU has to keep running through the park phase to
		// reach an instruction boundary, or ss_mcu_frozen never asserts and
		// the park deadlocks. Only things that do not gate parking may be held
		// for the whole window. Its position is restored from the image
		// anyway, so what it advances during a park is undone.
		else if (ss_active) mdiv <= mdiv;
		else mdiv <= (mdiv == mdiv_max) ? 3'd0 : mdiv + 3'd1;
	end
	wire mcu_cen_tick = (mdiv == mdiv_max);

	wire mcu_irq2;
	// Only the source the .mra selected may raise it. mcu_irq2 is quiet while
	// the MCU is held in reset, but naming the condition costs nothing and
	// keeps mode D from depending on that.
	wire prot_irq2 = (prot == 2'd1) ? io_irq2
	               : (prot == 2'd0) ? mcu_irq2 : 1'b0;
	wire [3:0] mcu_dbg_bank;
	wire mcu_dbg_rd;
	// INT1 is display enable: high over the visible rows (MS1-19)
	wire int1 = (vcount >= 9'd16) && (vcount < 9'd240);

	reg prot_we_pulse;
	always @(posedge clk)
		if (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) prot_we_pulse <= ss_wdata[0];
		else prot_we_pulse <= we & sel_prot;
	wire prot_we_edge = (we & sel_prot) & ~prot_we_pulse;

	// ---- simulated protection (prot == 1), MAME's ip_select_w()
	//
	// A per-game table of seven command bytes. Writing one of them latches the
	// input it names, or a fixed reply, and raises IRQ2. Anything else latches
	// NOTHING and raises NOTHING -- MAME returns early, and a game that polls
	// with a junk command must see no answer and no interrupt.
	//
	//   index      0       1    2    3     4     5      6
	//              SYSTEM  P1   P2   DSW1  DSW2  0x0d   0x06
	//   hayaosi1   51      52   53   54    55    FC     06     (System B)
	//   chimeraba  56      52   53   55    54    FA     06     (System C)
	//
	// hayaosi1 is the only System B set that uses iosim and chimeraba the only
	// System C one, so `is_c` picks the table exactly -- no extra .mra field.
	// Indices 5 and 6 answer with CONSTANTS 0x0d and 0x06; it is the COMMAND
	// that differs per game, not the reply.
	wire [7:0] io_cmd = oEdb[7:0];         // MAME masks the word to its low byte

	// IRQ2 has TWO sources on a simulated board, and MAME models both:
	//
	//  * the RASTER, at scanline 16. megasys1BC_scanline (the non-MCU
	//    callback) does `if (scanline == 0 + 16) set_input_line(2, HOLD_LINE)`.
	//    On an MCU board the very same edge is routed to the MCU's INT1
	//    instead -- megasys1BC_iomcu_scanline -- which is why this source
	//    exists only here. Without it hayaosi1 never leaves its boot loop:
	//    it sits in STOP #$2100 at 0x0018EA waiting for IRQ2, takes the
	//    level-4 vector instead, and the protection command at 0x001902 is
	//    never reached, so no command ever arrives to raise IRQ2 the other
	//    way. Found by diffing the bus against MAME: identical for 79
	//    accesses, then MAME fetches vector 0x68 and this core fetched 0x70.
	//
	//  * a VALID command write, from ip_select_w, below.
	always @(posedge clk) begin
		io_int1_d <= int1;
		io_irq2 <= 1'b0;
		// 0x06, not 0. MAME's device_reset does the same, with the reason:
		// "reset protection - some games expect this initial read without
		// sending anything". hayaosi1 is one of them: its first protection
		// access is a READ, before any command, and it compares the result
		// against 6.
		if (reset) io_latched <= 8'h06;
		// Restored HERE, in the block that owns it (MS1-34).
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd6)) begin
			io_latched <= ss_wdata[7:0];
			io_int1_d  <= ss_wdata[8];
		end
		else if (use_iosim & int1 & ~io_int1_d) io_irq2 <= 1'b1;
		else if (use_iosim & prot_we_edge) begin
			if      (io_cmd == io_c0)  begin io_latched <= in_system; io_irq2 <= 1'b1; end
			else if (io_cmd == 8'h52)  begin io_latched <= in_p1;     io_irq2 <= 1'b1; end
			else if (io_cmd == 8'h53)  begin io_latched <= in_p2;     io_irq2 <= 1'b1; end
			else if (io_cmd == io_c3)  begin io_latched <= in_dsw1;   io_irq2 <= 1'b1; end
			else if (io_cmd == io_c4)  begin io_latched <= in_dsw2;   io_irq2 <= 1'b1; end
			else if (io_cmd == io_c5)  begin io_latched <= 8'h0D;     io_irq2 <= 1'b1; end
			else if (io_cmd == 8'h06)  begin io_latched <= 8'h06;     io_irq2 <= 1'b1; end
		end
	end

	// ---- System D's protection (prot == 3), MAME's protection_peekaboo_r/w.
	//
	// Nothing like the B/C command table: there is no MCU device in system_D
	// at all (peekaboo ships a dumped TMP91640 that MAME does not run), and
	// the port is a plain 16-bit latch with three special read values.
	//
	//   write  COMBINE_DATA the latch, then
	//            if ((val & 0x90) == 0x90) okibank = val & 7
	//          and raise IRQ **4** -- not 2. This is the ONLY interrupt the
	//          board has besides vblank, and it is how the game clocks its
	//          paddle reads.
	//   read   0x0002 -> 0x0003, 0x0051 -> P1, 0x0052 -> P2, anything else
	//          echoes the latch back. The compares are against the WHOLE
	//          word, so a write with a non-zero high byte matches none of
	//          them and reads back as itself.
	//
	// The bank is part of the same latch: bit 7 and bit 4 both set means the
	// low three bits are a sample-bank number. Entry 7 is configured to the
	// same block as entry 0 (init_peekaboo does configure_entry(7, ROM+0x20000)
	// and then configure_entries(0, 7, ROM+0x20000, 0x20000), which fills
	// 0..6), so bank 7 is NOT ROM+0x100000 -- that would run off the end of
	// a 1 MB sample ROM. ms1_sound folds that in.
	wire [15:0] pk_next = {(~UDSn) ? wdat[15:8] : pk_latch[15:8],
	                       (~LDSn) ? wdat[7:0]  : pk_latch[7:0]};
	always @(posedge clk) begin
		pk_irq4 <= 1'b0;
		oki_we  <= 1'b0;
		if (reset) begin
			pk_latch <= 16'h0000; oki_bank <= 3'd0;
			oki_wdata <= 8'h00;
		end
		// Restored HERE, in the block that owns it (MS1-34).
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd7)) begin
			pk_latch <= ss_wdata;
		end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd8)) begin
			oki_bank <= ss_wdata[2:0]; oki_wdata <= ss_wdata[15:8];
		end
		else begin
			if (is_d & prot_we_edge) begin
				pk_latch <= pk_next;
				if ((pk_next[7:0] & 8'h90) == 8'h90) oki_bank <= pk_next[2:0];
				pk_irq4  <= 1'b1;
			end
			// 0F8001 is an ODD byte address: the chip is on the LOW data
			// lane and the access is an LDS one. A word write hits it too,
			// which is why this keys on the strobe rather than on a[0].
			if (is_d & (we & d_oki) & ~oki_we_d) begin
				oki_we    <= 1'b1;
				oki_wdata <= wdat[7:0];
			end
		end
	end
	always @(posedge clk)
		if (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) oki_we_d <= ss_wdata[3];
		else oki_we_d <= we & d_oki;

	ms1_iomcu u_mcu (
		// Held in reset unless it IS the protection: on an iosim or a
		// bootleg set the .mra ships a zero-filled MCU region, and 0x00 is
		// NOP, so letting it run just burns cycles and answers nothing.
		.clk(clk), .cen(mcu_cen_tick), .reset(reset | ss_rst_dbg[0] | (prot != 2'd0)),
		.host_we(prot_we_edge), .host_data(oEdb[7:0]),
		.mcu_data(mcu_prot_rd), .main_irq2(mcu_irq2),
		.int1(int1),
		.in_p1(in_p1), .in_p2(in_p2), .in_dsw1(in_dsw1),
		.in_dsw2(in_dsw2), .in_system(in_system),
				.rom_addr(mcu_rom_addr), .rom_data(mcu_rom_data), .rom_ready(mcu_rom_ready),
		.ss_active(ss_active), .ss_addr(ss_addr), .ss_wr(ss_wr),
		.ss_wdata(ss_wdata), .ss_rdata(ss_mcu_rdata),
		.ss_freeze(ss_freeze), .ss_frozen(ss_mcu_frozen),
		.dbg_addr(), .dbg_bank(mcu_dbg_bank), .dbg_rd(mcu_dbg_rd), .dbg_wr(), .dbg_din(),
		.dbg_mcu_pc(dbg_mcu_pc), .dbg_mcu_halt(dbg_mcu_halt), .dbg_mcu_if(dbg_mcu_if),
		.dbg_mcu_irqp(dbg_mcu_irqp), .dbg_mcu_mask(dbg_mcu_mask)
	);

	always @(posedge clk) begin
		if (reset) begin dbg_mcuacc <= 0; dbg_mcubank <= 0; end
		else if (mcu_cen_tick) begin
			if (mcu_dbg_rd) dbg_mcuacc <= dbg_mcuacc + 1;
			if (mcu_dbg_rd && mcu_dbg_bank != 4'd0) dbg_mcubank <= dbg_mcubank + 1;
		end
	end

	// System D has no sound CPU and therefore no latch.
	wire sel_slatch = is_d ? 1'b0
	                : is_c ? (a >= 24'h0C8000 && a < 24'h0C8002)
	                       : (a >= 24'h044308 && a < 24'h04430A);
	reg slatch_d;
	always @(posedge clk) begin
		slatch_d  <= (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) ? ss_wdata[1] : (we & sel_slatch);
		slatch_we <= (we & sel_slatch) & ~slatch_d;
		if ((we & sel_slatch) & ~slatch_d) slatch_data <= wdat;
	end

	// --------------------------------------------------- interrupt timer
	// HOLD_LINE: the level stays asserted until the CPU acknowledges it.
	reg irq1_h, irq2_h, irq4_h;
	wire iack = ~ASn & (FC0 & FC1 & FC2);
	// ONE clear per acknowledge CYCLE, not per clock. iack is a level that
	// stays asserted for the whole ack bus cycle; clearing on the level
	// walks down the priority chain and retires every pending interrupt at
	// once. The symptom is that only the highest-priority source is ever
	// seen: IRQ 4 fired every frame while IRQ 1 and the protection's IRQ 2
	// were raised and silently discarded, and the game sat in its STOP loop
	// waiting for a handler that never ran.
	reg int1_dd;
	always @(posedge clk) begin
		if (reset) begin dbg_irq2 <= 0; dbg_int1e <= 0; int1_dd <= 0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd2)) int1_dd <= ss_wdata[2];
		else begin
			if (prot_irq2) dbg_irq2 <= dbg_irq2 + 1;
			int1_dd <= int1;
			if (int1 & ~int1_dd) dbg_int1e <= dbg_int1e + 1;
		end
	end

	reg iack_d;
	always @(posedge clk)
		if (ss_w & ss_misc & (ss_addr[3:0] == 4'd1)) iack_d <= ss_wdata[0];
		else iack_d <= iack;
	wire iack_edge = iack & ~iack_d;
	wire [2:0] iack_level = eab[3:1];
	always @(posedge clk) begin
		if (reset) begin irq1_h <= 1'b0; irq2_h <= 1'b0; irq4_h <= 1'b0; end
		else if (ss_w & ss_misc & (ss_addr[3:0] == 4'd1)) begin
			irq1_h <= ss_wdata[3]; irq2_h <= ss_wdata[2]; irq4_h <= ss_wdata[1];
		end
		else begin
			// System B and C take their level 1 and level 4 from the
			// raster (megasys1BC_scanline, lines 96 and 240) and level 2
			// from the protection.
			//
			// System D has NO scanline callback at all: system_D uses
			// set_vblank_int(megasys1D_irq), which is one level **2** per
			// frame at the start of vblank, and its only other interrupt is
			// the level 4 its protection port raises. Leaving B/C's timer
			// running under mode D gives the game a level 1 and a level 4 it
			// has no handler for and never the level 2 it waits on.
			if (vtick && vcount == 9'd96  && ~is_d) irq1_h <= 1'b1;
			if (vtick && vcount == 9'd240)
				if (is_d) irq2_h <= 1'b1; else irq4_h <= 1'b1;
			if (prot_irq2)                 irq2_h <= 1'b1;
			if (pk_irq4)                   irq4_h <= 1'b1;
			// MS1-23 says one acknowledge CYCLE retires exactly one interrupt.
			// It must also retire one of the GAME's interrupts only. The
			// savestate park raises level 7 and is acknowledged like any
			// other, and this chain would then clear whatever the game had
			// pending -- so taking a savestate silently ate an interrupt, and
			// the run that had been saved was no longer the run that resumed.
			// The 68000 puts the acknowledged level on A3:A1; the board uses
			// only 1, 2 and 4, so level 7 is the park's and nothing else.
			if (iack_edge && iack_level != 3'd7) begin
				if      (irq4_h) irq4_h <= 1'b0;
				else if (irq2_h) irq2_h <= 1'b0;
				else if (irq1_h) irq1_h <= 1'b0;
			end
		end
	end
	// ---- savestate: park the 68000 at an instruction boundary.
	// MON_BASE must be unmapped on every board this core serves. 0x0C0000 is
	// free on System B (above rom1's 0x80000-0xBFFFF, below the protection
	// port at 0xE0000) and on System C (below c_vreg at 0xC2000).
	wire [2:0] ipl_park;
	wire       sel_mon;
	wire [15:0] mon_data;
	ss_m68k_park #(.MON_BASE(15'h600)) u_park (
		.clk(clk), .reset(reset), .phi(enPhi2),
		.park_req(ss_freeze), .parked(ss_m68k_parked), .resume(ss_resume),
		.eab(eab), .ASn(ASn), .eRWn(eRWn), .FC0(FC0), .FC1(FC1), .FC2(FC2),
		.oEdb(oEdb),
		.ipl_park(ipl_park), .sel_mon(sel_mon), .mon_data(mon_data),
		.ss_sel(ss_addr[1:0]), .ss_wr(ss_w & ss_park), .ss_wdata(ss_wdata),
		.ss_rdata(ss_park_rdata)
	);
	wire [15:0] ss_park_rdata;
	wire        ss_park = ss_active & (ss_addr[19:4] == 16'h1D01);  // 0x1D010

	wire [2:0] ipl_game = irq4_h ? 3'd4 : irq2_h ? 3'd2 : irq1_h ? 3'd1 : 3'd0;
	// The park request is level 7 and outranks everything the board can raise.
	wire [2:0] ipl = (ipl_park != 3'd0) ? ipl_park : ipl_game;

	// -------------------------------------------------------- bus tracing
	reg as_d;
	always @(posedge clk) begin
		if (reset) begin dbg_acc <= 0; dbg_vregw <= 0; dbg_vramw <= 0; end
		else if (as_active & ~as_d) begin
			dbg_acc <= dbg_acc + 1;
			if (~eRWn & sel_vreg) dbg_vregw <= dbg_vregw + 1;
			if (~eRWn & (sel_v0|sel_v1|sel_v2)) dbg_vramw <= dbg_vramw + 1;
		end
		as_d <= as_active;
		tr_valid <= 1'b0;
		// The interrupt-acknowledge cycle (FC = 111) is a real bus cycle on
		// hardware -- the 68000 drives 0xFFFFFx with the level in A3:A1 -- but
		// MAME services autovectors internally and its memory tap never sees
		// it. Excluding it here keeps the two traces comparable; it is a
		// difference in what is OBSERVABLE, not in what happens.
		if (as_active & ~as_d & ~iack) begin   // one event per bus cycle
			tr_addr  <= a;
			tr_data  <= eRWn ? rdat : oEdb;
			tr_we    <= ~eRWn;
			tr_valid <= 1'b1;
		end
	end

	fx68k u_cpu (
		.clk(clk), .HALTn(1'b1), .extReset(reset), .pwrUp(reset),
		.enPhi1(enPhi1), .enPhi2(enPhi2),
		.eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn), .E(), .VMAn(VMAn),
		.FC0(FC0), .FC1(FC1), .FC2(FC2), .BGn(BGn),
		.oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
		// DTACK must NOT be asserted during an interrupt acknowledge: the
		// 68000 prefers it over VPA, which turns an AUTOVECTORED interrupt
		// into a vectored one and fetches vector 0 off an undriven bus.
		// MAME's set_input_line/HOLD_LINE is autovectored.
		.DTACKn(~(as_active & ~iack & ~rom_stall & ~arr_wait)), .VPAn(~iack), .BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
		.IPL0n(~ipl[0]), .IPL1n(~ipl[1]), .IPL2n(~ipl[2]),
		.iEdb(iEdb), .oEdb(oEdb), .eab(eab)
	);
endmodule
