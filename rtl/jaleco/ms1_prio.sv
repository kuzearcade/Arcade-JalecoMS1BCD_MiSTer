// Jaleco Mega System 1 priority resolver.
//
// The board has a 512-byte PROM that decides, for every pixel, which of the
// three layers or the sprites is shown. MAME does NOT use it that way: it
// converts the PROM into sixteen "layer orders" at init (priority_create), by
// repeatedly asking which layer is on top of the remaining set, and then
// composites in that order -- a two-stage algorithm with a documented failure
// case ("the special value 0xfffff means that the order is either unknown or
// no simple stack of layers can account for the values in the PROM", and
// peekaboo's PROM is named as an example it cannot express).
//
// docs/PLAN.md section 1.4 says to measure before choosing between that and a
// per-pixel PROM lookup. Measured: a per-pixel lookup is pixel-exact against
// MAME on all four oracle captures across all three game modes -- avspirit
// (B), 64street (C), bigstrik (C, sprite splitting) and peekaboo (D) -- while
// being one M10K and one read per pixel instead of a conversion pass with a
// case it cannot represent. So this is the direct lookup, and it is closer to
// the hardware than the reference emulator is.
//
// Address, straight from the comment block in megasys1_v.cpp:
//
//   addr = (low-priority sprite AND sprite splitting)  << 0
//        | (layer 0 enabled and opaque here)           << 1
//        | (layer 1 enabled and opaque here)           << 2
//        | (layer 2 enabled and opaque here)           << 3
//        | (a sprite pixel is present here)            << 4
//        | priority code (active_layers bits 11:8)     << 5
//
//   PROM[addr] & 3 = the winning layer, 3 meaning sprites.
//
// The bit-0 polarity WAS unresolved while the only scenes available had no
// sprite pixels. It is now settled by measurement on bigstrik's split scenes:
// the "low priority" group is the one whose sprite attribute bit 3 is SET.
// The wrong polarity costs 25205 of 57344 pixels there and nothing at all
// anywhere else. See docs/known-issues.md MS1-15.

module ms1_prio (
	input        clk,
	input        ce,

	input  [3:0] pri_code,      // active_layers[11:8]
	input        split,         // sprite_flag[8]

	input        l0_opaque,     // already ANDed with the layer's enable bit
	input        l1_opaque,
	input        l2_opaque,
	input        spr_present,
	input        spr_lowpri,    // attribute bit 3 SET = the low group

	// priority PROM, loaded over ioctl index 1 -- never baked into the
	// bitstream (docs/PLAN.md 2.3)
	output [8:0] prom_addr,
	input  [7:0] prom_data,

	output reg [1:0] win        // 0,1,2 = layer; 3 = sprites
);
	assign prom_addr = { pri_code,
	                     spr_present,
	                     l2_opaque,
	                     l1_opaque,
	                     l0_opaque,
	                     (spr_lowpri & split & spr_present) };

	always @(posedge clk) if (ce) win <= prom_data[1:0];
endmodule
