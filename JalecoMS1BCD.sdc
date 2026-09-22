# Jaleco Mega System 1 B/C/D timing constraints.
#
# sys/sys_top.sdc is the MiSTer framework's own base file: the root 50 MHz
# clock definitions, the HPS/SPI/HDMI-I2C virtual clocks, the exclusive
# clock-group partitioning that keeps unrelated domains from being timed
# against each other, and a long list of false paths for OSD and scaler
# configuration signals. The Template.sdc scaffold never sources it, which
# leaves derive_pll_clocks with no properly defined root clocks and makes
# Quartus try to relate every domain to every other one -- the whole content
# of the "Design is not fully constrained" warnings and the bogus
# negative-slack paths seen on the sibling NMK16 and SandScrp projects.
source sys/sys_top.sdc

derive_pll_clocks
derive_clock_uncertainty

# ------------------------------------------------------------------
# Core clock groups
# ------------------------------------------------------------------
# The game logic (both 68000s, the TMP91640, the YM2151, both OKIs and the
# video) runs on clk_sys at 48 MHz and rtl/sdram.sv on clk_ram at 96 MHz, both
# outputs of rtl/pll.v. That file is a hand-written altpll instance rather
# than MegaWizard altera_pll IP, so its hierarchical clock names do not match
# the (*|pll|pll_inst|altera_pll_i|...) wildcard sys/sys_top.sdc uses, and
# without the loop below neither output lands in any exclusive group.
#
# Each PLL output must be its OWN group, not one shared group. They come from
# a single VCO, so one group would make Quartus time every clk_sys/clk_ram
# path synchronously against the worst-case edge pair of a 20.8 ns and a
# 10.4 ns clock, and fail on the address and data paths that the toggle-style
# req/ack protocol in rtl/sdram.sv makes deliberately irrelevant: the payload
# is held from the toggle until ack, and is only sampled after a two-flop
# synchroniser has seen the toggle. The foreach gives every matching output
# its own group, whatever Quartus decides to name the counters this compile.
set core_pll_groups {}
foreach_in_collection c [get_clocks {emu|pll*|altpll_component|*PLL_OUTPUT_COUNTER|divclk}] {
	lappend core_pll_groups -group [get_clock_info -name $c]
}
# There is no third PLL: CLK_VIDEO is clk_ram, the same 96 MHz output the
# SDRAM controller uses, so the loop above already covers the video chain.
set_clock_groups -exclusive \
	{*}$core_pll_groups \
	-group [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
	-group [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
	-group [get_clocks {spi_sck}] \
	-group [get_clocks {hdmi_sck}] \
	-group [get_clocks {*|h2f_user0_clk}] \
	-group [get_clocks {FPGA_CLK1_50}] \
	-group [get_clocks {FPGA_CLK2_50}] \
	-group [get_clocks {FPGA_CLK3_50}]

# ------------------------------------------------------------------
# CRT Adjust multicycle
# ------------------------------------------------------------------
# crt_vsize writes o_active_cyc on the second clock of an output line and
# consumes it in the DE-window clamp on the fourth, a 22-bit add and compare
# that is the worst path on the video clock. Two clocks are always available
# between the two, so it is a legitimate two-cycle path. Only that source is
# excepted; the clamp's other inputs can change on any clock and stay
# single-cycle.
set vsz_ac [get_registers {*|crt_chain:crt_chain|crt_vsize:u_vsize|o_active_cyc[*]}]
set vsz_ds [get_registers {*|crt_chain:crt_chain|crt_vsize:u_vsize|o_de_start[*]}]
set_multicycle_path -setup 2 -from $vsz_ac -to $vsz_ds
set_multicycle_path -hold  1 -from $vsz_ac -to $vsz_ds

# ------------------------------------------------------------------
# The protection MCU is a multicycle island
# ------------------------------------------------------------------
# rtl/tlcs90/tlcs90.sv holds its ENTIRE datapath in one
#
#     always @(posedge clk) ... else if (cen) begin ... end
#
# so every register in it advances only on `cen`, and ms1_main.sv drives that
# from mdiv: once every 4 clk_sys cycles on System C (12 MHz) and once every 6
# on System B and D (8 MHz). The minimum spacing is therefore 4 clk_sys, and
# nothing makes it shorter -- mdiv holds during a savestate park, which only
# makes cens rarer, and mdiv_max only changes while the core is in reset for
# the ROM download.
#
# Unconstrained, TimeQuest times that datapath at the full 48 MHz and the
# whole design fails on it: the first fit reported -13.703 ns on
# tlcs90|val2[0] -> tlcs90|hl[8] (TNS -178.678), and every one of the twelve
# worst paths was that same pair. The path itself is ~34.5 ns, which is fine
# against the 83.3 ns four cen periods actually give it.
#
# BOTH endpoints must be inside u_cpu. A path INTO the CPU from a register
# that is not cen-gated (the ROM cache's din, for one) still has only a single
# clk_sys period to settle before the cen edge samples it, so those must stay
# single-cycle -- hence -from as well as -to, not -to alone.
set tlcs_regs [get_registers {*|tlcs90:u_cpu|*}]
set_multicycle_path -setup 4 -from $tlcs_regs -to $tlcs_regs
set_multicycle_path -hold  3 -from $tlcs_regs -to $tlcs_regs

# ------------------------------------------------------------------
# The .mra <switches> bytes are configuration, not data
# ------------------------------------------------------------------
# dip_sw holds the two DIP banks and the game-mode byte. Every write to it is
# gated on ioctl_download, and MS1BCD.sv's `reset` covers ioctl_download plus a
# 255-cycle settling tail, so no core register can sample a dip_sw bit until it
# has been stable for 5.3 us. Changing a DIP in the OSD re-sends index 254 and
# therefore resets the game, which is how the sibling cores behave too.
#
# This matters because `mode` (dip_sw[2][1:0]) fans out further than any other
# signal here: it picks the System B/C memory map, the main CPU and MCU
# dividers, the layer geometry and the input layout. Timed as a single-cycle
# 48 MHz path it lands on the protection MCU's datapath and fails at -1.6 ns,
# behind only the MCU's own multicycle island above.
set_false_path -from [get_registers {*|dip_sw[*][*]}]
