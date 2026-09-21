// M2 gate (1): the main-CPU bus trace against MAME's, through boot.
//
//   ./obj_dir/Vms1_main <maincpu.bin> <iomcu.bin> <bus.log> <mode> \
//                       <p1> <p2> <dsw1> <dsw2> <system>
//   mode 0 = System B, 1 = System C
//
// MAME's bus.log comes from sim/oracle/ms1_bustrace.lua and has one line per
// main-CPU access: <r|w> <seq> <pc> <addr> <data> <mask>. The comparison is
// on the SEQUENCE of accesses -- address, direction and data -- not on cycle
// timing, because MAME's 68000 is not cycle-accurate against fx68k and gate
// (1) asks whether the CPU and the board decode agree, not whether two
// different 68000 models tick alike.
#include "Vms1_main.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct Acc { char rw; unsigned addr, data, mask; };

static std::vector<uint8_t> slurp(const char *p) {
	FILE *f = fopen(p, "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", p); exit(1); }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n);
	if (n && fread(v.data(), 1, n, f) != (size_t)n) exit(1);
	fclose(f); return v;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 10) {
		fprintf(stderr, "usage: %s maincpu.bin iomcu.bin bus.log mode p1 p2 dsw1 dsw2 system\n", argv[0]);
		return 1;
	}
	auto rom  = slurp(argv[1]);
	auto mrom = slurp(argv[2]);
	int mode = atoi(argv[4]);

	std::vector<Acc> ref;
	{
		FILE *f = fopen(argv[3], "r");
		if (!f) { fprintf(stderr, "cannot open %s\n", argv[3]); return 1; }
		char k[8]; long seq; unsigned pc, addr, data, mask;
		while (fscanf(f, "%7s %ld %x %x %x %x", k, &seq, &pc, &addr, &data, &mask) == 6)
			ref.push_back({k[0], addr, data & 0xFFFF, mask & 0xFFFF});
		fclose(f);
	}
	long limit = getenv("MS1_CMP") ? atol(getenv("MS1_CMP")) : 200000;
	printf("reference accesses: %zu (comparing up to %ld)\n", ref.size(), limit);

	Vms1_main *top = new Vms1_main;
	top->mode = mode;
	top->in_p1     = strtol(argv[5], nullptr, 16) & 0xFF;
	top->in_p2     = strtol(argv[6], nullptr, 16) & 0xFF;
	top->in_dsw1   = strtol(argv[7], nullptr, 16) & 0xFF;
	top->in_dsw2   = strtol(argv[8], nullptr, 16) & 0xFF;
	top->in_system = strtol(argv[9], nullptr, 16) & 0xFF;
	top->reset = 1; top->clk = 0;
	top->mcu_rom_we = 0; top->vcount = 0; top->vtick = 0;

	// 48 MHz clk_sys; the raster is 384x278 at 6 MHz, so a scanline is 64
	// clk_sys ticks and a frame 278 of them.
	const long LINE_CLK = 384 * 8;
	// The raster phase at reset is a free parameter of the harness and it
	// decides when the first scanline interrupt lands relative to boot.
	long lcnt = 0;
	int vline = getenv("MS1_VPHASE") ? atoi(getenv("MS1_VPHASE")) : 0;
	auto serve = [&]() {
		unsigned ra = top->rom_addr * 2;
		top->rom_data = (ra + 1 < rom.size()) ? (rom[ra] << 8) | rom[ra + 1] : 0;
		top->eval();
	};
	auto tick = [&]() {
		top->vtick = 0;
		if (++lcnt >= LINE_CLK) {
			lcnt = 0;
			vline = (vline + 1) % 278;
			top->vcount = vline;
			top->vtick = 1;
		}
		top->clk = 0; top->eval(); serve();
		top->clk = 1; top->eval(); serve();
	};

	for (int i = 0; i < (int)mrom.size(); i++) {
		top->mcu_rom_we = 1; top->mcu_rom_addr = i; top->mcu_rom_data = mrom[i];
		tick();
	}
	top->mcu_rom_we = 0;
	for (int i = 0; i < 64; i++) tick();
	vline = getenv("MS1_VPHASE") ? atoi(getenv("MS1_VPHASE")) : 0;
	lcnt = 0; top->vcount = vline;
	top->reset = 0;

	FILE *dump = getenv("MS1_DUMP") ? fopen(getenv("MS1_DUMP"), "w") : nullptr;
	size_t got = 0, bad = 0;
	long maxclk = getenv("MS1_CLK") ? atol(getenv("MS1_CLK")) : 400000000L;
	for (long c = 0; c < maxclk && got < (size_t)limit && got < ref.size(); c++) {
		tick();
		if (getenv("MS1_RAMW") && top->dbg_ramw)
			fprintf(stderr, "RAMW %06X <= %04X\n", top->dbg_ramw_addr, top->dbg_ramw_data);
		if (!top->tr_valid) continue;
		unsigned a = top->tr_addr & (mode ? 0x1FFFFF : 0xFFFFF);
		char rw = top->tr_we ? 'w' : 'r';
		if (dump) fprintf(dump, "%c %zu %06X %04X\n", rw, got, a, top->tr_data & 0xFFFF);
		const Acc &e = ref[got];
		bool ok = (rw == e.rw) && (a == e.addr);
		// compare data only when the reference used the whole word: a byte
		// access leaves the other lane undefined on both sides
		if (ok && e.mask == 0xFFFF) ok = ((top->tr_data & 0xFFFF) == e.data);
		if (!ok) {
			if (bad == 0)
				printf("first mismatch at access %zu:\n  mame %c %06X %04X mask %04X\n"
				       "  rtl  %c %06X %04X\n", got, e.rw, e.addr, e.data, e.mask,
				       rw, a, top->tr_data & 0xFFFF);
			bad++;
			// MS1_NOSTOP keeps going past mismatches so tools/bus_compare.py
			// can try to realign the two traces; without it the dump ends at
			// the first divergence and there is nothing to realign.
			if (bad > 8 && !getenv("MS1_NOSTOP")) break;
		}
		got++;
	}
	if (dump) fclose(dump);
	printf("compared %zu accesses, %zu mismatches  %s\n", got, bad,
	       bad == 0 ? "MATCH" : "DIFFERS");
	delete top;
	return bad == 0 ? 0 : 2;
}
