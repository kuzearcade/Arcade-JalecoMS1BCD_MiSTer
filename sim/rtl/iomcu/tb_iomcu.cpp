// ms1_iomcu against MAME's own protection trace, command by command.
//
// docs/PLAN.md M2 gate (5) asks for "the protection handshake verified command
// by command against MAME's MCU trace, not merely 'the game boots'". This is
// that check: the MCU runs its REAL 16 KB ROM, is fed exactly the bytes the
// 68000 wrote in MAME, and every byte it hands back is compared with what the
// 68000 read there.
//
//   ./obj_dir/Vms1_iomcu <iomcu.bin> <prot.log> <p1> <p2> <dsw1> <dsw2> <system>
//
// prot.log comes from sim/oracle/ms1_bustrace.lua and interleaves
//   w <seq> <pc> <data>     the 68000 wrote this to the protection port
//   r <seq> <pc> <data>     the 68000 read this back
// The sequence numbers are 68000 bus accesses, which is how long the MCU had
// to answer; the harness converts that gap into MCU cycles rather than
// guessing a fixed settling time, because a reply that is merely LATE would
// otherwise look identical to a reply that is WRONG.
#include "Vms1_iomcu.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct Ev { char kind; long seq; unsigned val; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 8) {
		fprintf(stderr, "usage: %s <iomcu.bin> <prot.log> p1 p2 dsw1 dsw2 system\n", argv[0]);
		return 1;
	}
	std::vector<uint8_t> rom;
	{
		FILE *f = fopen(argv[1], "rb");
		if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
		fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
		rom.resize(n);
		if (n && fread(rom.data(), 1, n, f) != (size_t)n) return 1;
		fclose(f);
	}
	if (rom.size() != 16384) {
		fprintf(stderr, "iomcu rom is %zu bytes, expected 16384\n", rom.size());
		return 1;
	}

	std::vector<Ev> ev;
	{
		FILE *f = fopen(argv[2], "r");
		if (!f) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
		char k[8]; long seq; unsigned pc, val;
		while (fscanf(f, "%7s %ld %x %x", k, &seq, &pc, &val) == 4)
			ev.push_back({k[0], seq, val & 0xFF});
		fclose(f);
	}
	printf("%zu protection events\n", ev.size());

	Vms1_iomcu *top = new Vms1_iomcu;
	top->in_p1     = strtol(argv[3], nullptr, 16) & 0xFF;
	top->in_p2     = strtol(argv[4], nullptr, 16) & 0xFF;
	top->in_dsw1   = strtol(argv[5], nullptr, 16) & 0xFF;
	top->in_dsw2   = strtol(argv[6], nullptr, 16) & 0xFF;
	top->in_system = strtol(argv[7], nullptr, 16) & 0xFF;
	top->cen = 1; top->reset = 1; top->host_we = 0; top->host_data = 0;
	top->rom_we = 0; top->clk = 0;

	// INT1 is display enable: high from scanline 16 to 239 of a 278-line
	// frame. The MCU runs at the main CPU's 8 MHz and the frame is 384x278
	// pixels at 6 MHz, so one scanline is 384/6e6 s = 512 MCU cycles.
	// MCU cycles per scanline = 384 pixels / 6 MHz pixel clock x the MCU
	// clock. System B runs the MCU at 8 MHz (512), System C at 12 MHz (768).
	const long LINE_CYC = getenv("MS1_LINE") ? atol(getenv("MS1_LINE")) : 512;
	const long LINES = 278, INT1_ON = 16, INT1_OFF = 240;
	// The phase of the video frame at MCU reset is not knowable from the MCU
	// alone, and it decides when the first INT1 lands relative to the MCU's
	// initialisation. MS1_PHASE sweeps it.
	long fcyc = getenv("MS1_PHASE") ? atol(getenv("MS1_PHASE")) : 0;
	auto tick = [&]() {
		long line = fcyc / LINE_CYC;
		top->int1 = (line >= INT1_ON && line < INT1_OFF) ? 1 : 0;
		fcyc = (fcyc + 1) % (LINE_CYC * LINES);
		top->clk = 0; top->eval(); top->clk = 1; top->eval();
	};

	// load the internal ROM
	for (int i = 0; i < 16384; i++) {
		top->rom_we = 1; top->rom_addr = i; top->rom_data = rom[i];
		tick();
	}
	top->rom_we = 0;
	for (int i = 0; i < 16; i++) tick();
	// Phase is measured from RESET RELEASE, not from the start of the run:
	// the ROM load above burns 16k ticks and would otherwise smear it.
	fcyc = getenv("MS1_PHASE") ? atol(getenv("MS1_PHASE")) : 0;
	top->reset = 0;

	if (getenv("MCU_TRACE")) {
		int n = atoi(getenv("MCU_TRACE"));
		for (int i = 0; i < n; i++) {
			tick();
			if (top->dbg_rd || top->dbg_wr)
				printf("%c %01X:%04X %02X\n", top->dbg_wr ? 'W' : 'R',
				       top->dbg_bank, top->dbg_addr, top->dbg_din);
		}
		return 0;
	}

	// let the MCU reach its command loop before the first host write
	for (int i = 0; i < 200000; i++) tick();

	// One 68000 bus access is roughly four CPU cycles, and the MCU runs at
	// the same 8 MHz, so a gap of N accesses is about 4N MCU cycles. Clamped:
	// enough to answer, bounded so a hung MCU is reported rather than hangs.
	const long CYC_PER_ACC = 4, MAXRUN = 400000;
	long prev_seq = ev.empty() ? 0 : ev[0].seq;
	int checked = 0, bad = 0, firstbad = -1;
	unsigned last_written = 0;

	for (size_t i = 0; i < ev.size(); i++) {
		long gap = ev[i].seq - prev_seq; prev_seq = ev[i].seq;
		long run = gap * CYC_PER_ACC;
		if (run < 64) run = 64;
		if (run > MAXRUN) run = MAXRUN;
		for (long c = 0; c < run; c++) tick();

		if (ev[i].kind == 'w') {
			last_written = ev[i].val;
			top->host_data = ev[i].val; top->host_we = 1; tick(); top->host_we = 0;
		} else {
			unsigned got = top->mcu_data & 0xFF;
			checked++;
			if (got != ev[i].val) {
				bad++;
				if (firstbad < 0) {
					firstbad = (int)i;
					printf("first mismatch at event %zu (seq %ld): after write %02X, "
					       "MAME read %02X, mcu gave %02X\n",
					       i, ev[i].seq, last_written, ev[i].val, got);
				}
			}
		}
	}
	printf("replies checked %d, mismatches %d  %s\n",
	       checked, bad, bad == 0 ? "MATCH" : "DIFFERS");
	delete top;
	return bad == 0 ? 0 : 2;
}
