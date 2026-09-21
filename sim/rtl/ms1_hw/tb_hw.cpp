// M3 gate: the golden-byte audit.
//
// Streams a real ioctl_download into the real rtl/sdram.sv, then walks every
// byte of every region back out THROUGH THE REAL CACHE and compares it with
// the image the reference sim uses. That is the measurement that separates
// "the cache never fills" from "the cache fills with the wrong bytes", and it
// is the only thing that can catch a region base that lost a bit -- the class
// of error that once had a second OKI playing tile graphics for a week.
//
//   TB_STREAM     ioctl byte stream (index 0)
//   TB_PROM       priority PROM image (index 1)
//   TB_IMGDIR     directory of per-region reference images
//   TB_MODE       0 = B, 1 = C, 2 = D
//   TB_STEP       address stride (default 1 = every byte)
//   TB_MAX        stop printing after this many mismatches per region
#include "Vms1_hw_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static unsigned long envu(const char *n, unsigned long d) {
	const char *v = getenv(n); return v ? strtoul(v, nullptr, 0) : d;
}
static std::vector<uint8_t> slurp(const std::string &p, bool req = true) {
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) { if (req) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(1); } return {}; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n);
	if (n && fread(v.data(), 1, n, f) != (size_t)n) exit(1);
	fclose(f); return v;
}

struct Region { const char *name; int sel; const char *img; bool word; };

int main(int argc, char **argv) {
	VerilatedContext ctx; ctx.commandArgs(argc, argv);
	Vms1_hw_top top{&ctx};

	const std::string stream = getenv("TB_STREAM") ? getenv("TB_STREAM") : "roms/avspirit_ioctl.bin";
	const std::string promp  = getenv("TB_PROM")   ? getenv("TB_PROM")   : "roms/avspirit_prom.bin";
	const std::string imgdir = getenv("TB_IMGDIR") ? getenv("TB_IMGDIR") : "/tmp/gen_avspirit";
	const long step = envu("TB_STEP", 1);
	const long maxp = envu("TB_MAX", 8);

	auto rom  = slurp(stream);
	auto prom = slurp(promp, false);

	// clk_sys 48 MHz, clk_ram 96 MHz: two ram edges per sys edge.
	auto tick = [&]() {
		top.clk_ram = 0; top.eval();
		top.clk_sys = 0; top.eval();
		top.clk_ram = 1; top.eval();
		top.clk_ram = 0; top.eval();
		top.clk_sys = 1; top.eval();
		top.clk_ram = 1; top.eval();
	};

	top.mode = envu("TB_MODE", 0);
	top.ioctl_download = 0; top.ioctl_wr = 0; top.ioctl_addr = 0;
	top.ioctl_dout = 0; top.ioctl_index = 0;
	top.audit_en = 0; top.audit_sel = 0; top.audit_addr = 0;
	top.reset = 1;
	for (int i = 0; i < 400; i++) tick();
	top.reset = 0;
	long guard = 0;
	while (!top.sdram_ready && guard++ < 2000000) tick();
	if (!top.sdram_ready) { printf("FAIL: sdram never became ready\n"); return 1; }
	printf("sdram ready after %ld ticks\n", guard);

	// ---- index 0: the ROM image, honouring ioctl_wait exactly as the real
	// loader does. Offering the next byte before the previous write lands
	// throws it away silently.
	top.ioctl_download = 1; top.ioctl_index = 0;
	for (size_t i = 0; i < rom.size(); i++) {
		top.ioctl_addr = i; top.ioctl_dout = rom[i]; top.ioctl_wr = 1;
		tick();
		top.ioctl_wr = 0;
		long w = 0;
		while (top.ioctl_wait && w++ < 10000) tick();
	}
	// ---- index 1: the priority PROM
	top.ioctl_index = 1;
	for (size_t i = 0; i < prom.size(); i++) {
		top.ioctl_addr = i; top.ioctl_dout = prom[i]; top.ioctl_wr = 1;
		tick(); top.ioctl_wr = 0;
	}
	top.ioctl_download = 0; top.ioctl_index = 0;
	for (int i = 0; i < 100; i++) tick();
	printf("download: %u bytes to SDRAM, %u to the PROM RAM (stream %zu, prom %zu)\n",
	       top.dbg_dl_bytes, top.dbg_prom_bytes, rom.size(), prom.size());

	static const Region regs[] = {
		{"maincpu",  0, "maincpu.bin",  true },
		{"audiocpu", 1, "audiocpu.bin", true },
		{"iomcu",    2, "iomcu.bin",    false},
		{"scroll1",  3, "gfx0.bin",     false},
		{"scroll2",  4, "gfx1.bin",     false},
		{"scroll3",  5, "gfx2.bin",     false},
		{"sprites",  6, "sprites.bin",  false},
		{"oki1",     7, "oki1.bin",     false},
		{"oki2",     8, "oki2.bin",     false},
		{"proms",    9, "prom.bin",     false},
	};

	top.audit_en = 1;
	for (int i = 0; i < 20; i++) tick();

	long grand_bad = 0, grand_checked = 0;
	printf("\n%-10s %10s %10s %s\n", "region", "checked", "wrong", "verdict");
	for (const Region &r : regs) {
		auto img = slurp(imgdir + "/" + std::string(r.img), false);
		if (img.empty()) { printf("%-10s %10s %10s (no image)\n", r.name, "-", "-"); continue; }
		top.audit_sel = r.sel;
		long bad = 0, checked = 0, printed = 0;
		// A word region is addressed by WORD here, a byte region by BYTE.
		long n = r.word ? (long)img.size() / 2 : (long)img.size();
		for (long a = 0; a < n; a += step) {
			top.audit_addr = a;
			tick();
			long w = 0;
			while (!top.audit_ready && w++ < 2000) tick();
			unsigned got = top.audit_data;
			unsigned want = r.word ? ((img[2 * a] << 8) | img[2 * a + 1]) : img[a];
			checked++;
			if (got != want) {
				bad++;
				if (printed++ < maxp)
					printf("   %s: addr 0x%06lX got 0x%04X want 0x%04X\n", r.name, a, got, want);
			}
		}
		grand_bad += bad; grand_checked += checked;
		printf("%-10s %10ld %10ld %s\n", r.name, checked, bad, bad ? "WRONG" : "ok");
	}
	printf("\nTOTAL %ld bytes/words checked, %ld wrong -- %s\n",
	       grand_checked, grand_bad, grand_bad ? "GATE FAILED" : "GATE MET");
	return grand_bad ? 1 : 0;
}
