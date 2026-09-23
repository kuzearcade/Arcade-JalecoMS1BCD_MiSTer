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
	const long step  = envu("TB_STEP", 1);
	const long nfr   = envu("TB_FRAMES", 0);       // 0 = audit only
	const char *fdir = getenv("TB_FRAMEDIR");
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
	top.oki_2mhz = envu("TB_OKI2MHZ", top.mode == 2 ? 1 : 0) != 0;
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

	// ---- frames: run the core on the SDRAM path and dump what it paints.
	if (nfr) {
		const int W = 256, H = 224;
		top.prot = envu("TB_PROT", 0);
		top.in_p1 = envu("TB_P1", 0xFF); top.in_p2 = envu("TB_P2", 0xFF);
		// TB_SYS drives the SYSTEM port for the whole run; 0xBE holds coin 1
		// and start 1 on the generic layout, which is enough to coin up and
		// start a game so the sprite engine sees a real scene rather than an
		// attract screen. The sprite pass length scales with the number of
		// sprites drawn, and that is what the MS1-60 budget turns on.
		top.in_system = envu("TB_SYS", 0xFF);
		top.in_sys_hi = envu("TB_SYSHI", 0xFF);
		top.in_dsw1 = envu("TB_DSW1", 0xFF); top.in_dsw2 = envu("TB_DSW2", 0xFD);
		std::vector<std::vector<uint32_t>> frames;
		unsigned prev_mcuacc = 0; size_t froze_at = 0;
		std::vector<uint32_t> cur(W * H, 0);
		size_t px = 0;
		uint64_t guard2 = 0;
		while ((long)frames.size() < nfr && guard2++ < 400000000ULL) {
			tick();
			if (top.vblank_rise) {
				if (getenv("TB_MISSLOG")) {
					static unsigned pl0, pl1, pl2;
					unsigned d0 = top.dbg_l0_miss - pl0, d1 = top.dbg_l1_miss - pl1,
					         d2 = top.dbg_l2_miss - pl2;
					if (d0 || d1 || d2)
						printf("  frame %zu: misses L0 %u L1 %u L2 %u (first L2 miss at v=%u h=%u)\n",
						       frames.size(), d0, d1, d2,
						       top.dbg_l2_first_v, top.dbg_l2_first_h);
					pl0 = top.dbg_l0_miss; pl1 = top.dbg_l1_miss; pl2 = top.dbg_l2_miss;
				}
				if (px) frames.push_back(cur);
				// MS1-51: IRQ2 per frame, the number the reference sim puts at
				// about 15 once the game is running.
				// MS1-51: the first frame at which the MCU's read strobe
				// stops advancing. Everything after that is the freeze.
				if (top.dbg_mcuacc == prev_mcuacc && prev_mcuacc && !froze_at) {
					froze_at = frames.size();
					printf("  *** mcuacc frozen at %u, frame %zu ***\n",
					       top.dbg_mcuacc, froze_at);
				}
				prev_mcuacc = top.dbg_mcuacc;
				if (frames.size() && frames.size() % 20 == 0)
					printf("  frame %3zu: irq2=%u (%.1f/frame)  int1e=%u  mcuacc=%u\n",
					       frames.size(), top.dbg_irq2,
					       top.dbg_int1e ? (double)top.dbg_irq2 / top.dbg_int1e : 0.0,
					       top.dbg_int1e, top.dbg_mcuacc);
				std::fill(cur.begin(), cur.end(), 0);
				px = 0;
			}
			// MS1-27: sample ONLY on the pixel enable.
			if (top.ce_pix_o && top.rgb_valid && px < cur.size())
				cur[px++] = top.rgb & 0xFFFFFF;
		}
		size_t nonblack = 0, lastnb = 0;
		if (froze_at) {
			printf("\n--- port 3 after the freeze (req/ack/addr, mcu_ready, srom_ready) ---\n");
			int shown = 0; unsigned long long g = 0;
			int lastreq = -1, lastack = -1;
			while (shown < 24 && g++ < 4000000ULL) {
				tick();
				if (top.dbg_p3_req != lastreq || top.dbg_p3_ack != lastack) {
					printf("  req=%d ack=%d addr=%06x mcu_rdy=%d srom_rdy=%d\n",
					       top.dbg_p3_req, top.dbg_p3_ack, top.dbg_p3_addr,
					       top.dbg_mcu_ready, top.dbg_srom_ready);
					lastreq = top.dbg_p3_req; lastack = top.dbg_p3_ack; shown++;
				}
			}
			printf("  (after %llu further clocks: req=%d ack=%d mcu_rdy=%d srom_rdy=%d)\n",
			       g, top.dbg_p3_req, top.dbg_p3_ack, top.dbg_mcu_ready, top.dbg_srom_ready);
		}
		for (auto &f : frames) {
			size_t c = 0; for (auto v : f) if (v) c++;
			if (c) nonblack++;
			lastnb = c;
		}
		printf("captured %zu frames, %zu of them non-blank (last has %zu lit pixels)\n",
		       frames.size(), nonblack, lastnb);
		if (fdir) {
			char cmd[512]; snprintf(cmd, sizeof cmd, "mkdir -p %s", fdir);
			if (system(cmd)) {}
			for (size_t i = 0; i < frames.size(); i++) {
				char path[512];
				snprintf(path, sizeof path, "%s/f%zu.raw", fdir, i);
				FILE *f = fopen(path, "wb");
				if (f) { fwrite(frames[i].data(), 4, frames[i].size(), f); fclose(f); }
			}
			printf("dumped %zu frames to %s\n", frames.size(), fdir);
		}
		// The measurements M3's third gate asks for.
		double pixd = top.dbg_pix ? (double)top.dbg_pix : 1.0;
		printf("\nromwait  %u clocks over %u ROM accesses\n", top.dbg_romwait, top.dbg_romacc);
		printf("tile-fetch misses: L0 %u  L1 %u  L2 %u  out of %u displayed pixels\n",
		       top.dbg_l0_miss, top.dbg_l1_miss, top.dbg_l2_miss, top.dbg_pix);
		printf("                  L0 %.5f%%  L1 %.5f%%  L2 %.5f%%\n",
		       100.0 * top.dbg_l0_miss / pixd, 100.0 * top.dbg_l1_miss / pixd,
		       100.0 * top.dbg_l2_miss / pixd);
		printf("sprite pass: longest %u clocks (frame = 854016), late swaps %u\n",
		       top.dbg_spr_pass_cycles, top.dbg_spr_late_swaps);
		printf("sound writes: ym=%u oki1=%u oki2=%u\n",
		       top.dbg_ym_writes, top.dbg_oki1_writes, top.dbg_oki2_writes);
		return 0;
	}

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
