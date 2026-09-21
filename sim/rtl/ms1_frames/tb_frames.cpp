// M2 gate (2): frames pixel-exact over the attract, at a fixed offset,
// for one System B game and one System C game.
//
//   ./obj_dir/Vms1bcd_core <dir> <mode> <frames> <p1> <p2> <dsw1> <dsw2> <sys>
//
// <dir> holds the ROM images and the MAME frames to compare against:
//   maincpu.bin iomcu.bin gfx0.bin gfx1.bin gfx2.bin sprites.bin prom.bin
//   frames/f<N>.raw          MAME's own frames, captured from boot
//
// The sim runs from reset and records every frame it produces. The comparison
// then searches for the FIXED OFFSET k that best aligns the two runs -- the
// board and MAME do not leave reset on the same frame boundary, and the gate
// asks for a fixed offset rather than a coincidence.
#include "Vms1bcd_core.h"
#include "verilated.h"
#include "Vms1bcd_core___024root.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <string>

static std::vector<uint8_t> slurp(const std::string &p, bool req = true) {
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) { if (req) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(1); } return {}; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n);
	if (n && fread(v.data(), 1, n, f) != (size_t)n) exit(1);
	fclose(f); return v;
}
static uint8_t rd8(const std::vector<uint8_t> &v, size_t i) { return i < v.size() ? v[i] : 0; }

static long envl(const char *n, long d) {
	const char *v = getenv(n); return v ? strtol(v, nullptr, 0) : d;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 9) { fprintf(stderr, "usage: %s dir mode frames p1 p2 dsw1 dsw2 sys\n", argv[0]); return 1; }
	std::string d = argv[1];
	int mode = atoi(argv[2]);
	int nframes = atoi(argv[3]);

	auto rom  = slurp(d + "/maincpu.bin");
	auto mcurom = slurp(d + "/iomcu.bin");
	auto g0 = slurp(d + "/gfx0.bin"), g1 = slurp(d + "/gfx1.bin"), g2 = slurp(d + "/gfx2.bin", false);
	auto srom = slurp(d + "/sprites.bin");
	auto prom = slurp(d + "/prom.bin");
	auto sndrom = slurp(d + "/audiocpu.bin");
	auto ok1  = slurp(d + "/oki1.bin", false);
	auto ok2  = slurp(d + "/oki2.bin", false);

	Vms1bcd_core *top = new Vms1bcd_core;
	top->mode = mode;
	top->in_p1     = strtol(argv[4], nullptr, 16) & 0xFF;
	top->in_p2     = strtol(argv[5], nullptr, 16) & 0xFF;
	top->in_dsw1   = strtol(argv[6], nullptr, 16) & 0xFF;
	top->in_dsw2   = strtol(argv[7], nullptr, 16) & 0xFF;
	top->in_system = strtol(argv[8], nullptr, 16) & 0xFF;
	top->reset = 1; top->clk = 0;
	top->oki_status_real = 0;   // MAME's default: oki_status_r returns 0
	// The reference sim serves every ROM from a zero-latency array, so every
	// handshake is permanently satisfied. This is the baseline the hardware
	// path is compared against.
	top->rom_ready = 1; top->srom_ready = 1; top->mcu_rom_ready = 1;
	top->oki1_stall = 0; top->oki2_stall = 0;
	top->spr_rom_ready = 1;
	top->ss_freeze = 0; top->ss_resume = 0; top->ss_active = 0;
	top->ss_addr = 0; top->ss_wr = 0; top->ss_wdata = 0; top->ss_replay = 0;
	top->l0_rom_ready = 1; top->l1_rom_ready = 1; top->l2_rom_ready = 1;

	auto serve = [&]() {
		unsigned ra = top->rom_addr * 2;
		top->rom_data   = (ra + 1 < rom.size()) ? (rom[ra] << 8) | rom[ra + 1] : 0;
		top->l0_rom_data = rd8(g0, top->l0_rom_addr);
		top->l1_rom_data = rd8(g1, top->l1_rom_addr);
		top->l2_rom_data = rd8(g2, top->l2_rom_addr);
		top->spr_rom_data = rd8(srom, top->spr_rom_addr);
		top->prom_data    = rd8(prom, top->prom_addr);
		top->mcu_rom_data = rd8(mcurom, top->mcu_rom_addr);
		unsigned sa = top->srom_addr * 2;
		top->srom_data = (sa + 1 < sndrom.size()) ? (sndrom[sa] << 8) | sndrom[sa + 1] : 0;
		top->oki1_rom_data = rd8(ok1, top->oki1_rom_addr);
		top->oki2_rom_data = rd8(ok2, top->oki2_rom_addr);
		top->eval();
	};
	auto tick = [&]() {
		top->clk = 0; top->eval(); serve();
		top->clk = 1; top->eval(); serve();
	};

	// The MCU's internal ROM is now FETCHED like every other ROM rather than
	// written into a RAM inside the core: 16 KB is eight M10K blocks, and the
	// hardware path reaches it through a cache (docs/PLAN.md 1.5). `mcurom`
	// is served in serve() above.
	for (int i = 0; i < 64; i++) tick();
	top->reset = 0;

	// MS1_PROTLOG records the 68000's side of the protection conversation in
	// the same shape as sim/oracle/ms1_bustrace.lua's prot.log, so the two can
	// be diffed command by command -- M2 gate (5), which explicitly is not
	// satisfied by "the game boots".
	FILE *plog = getenv("MS1_PROTLOG") ? fopen(getenv("MS1_PROTLOG"), "w") : nullptr;
	const unsigned PROT_ADDR = mode ? 0x0D8000 : 0x0E0000;

	const int W = 256, H = 224;
	std::vector<std::vector<uint32_t>> frames;
	std::vector<uint32_t> cur(W * H, 0);
	size_t px = 0;
	long maxclk = getenv("MS1_CLK") ? atol(getenv("MS1_CLK")) : 60000000000L;

	for (long c = 0; c < maxclk && (int)frames.size() < nframes; c++) {
		tick();
		if (plog && top->tr_valid && (top->tr_addr == PROT_ADDR))
			fprintf(plog, "%c %04X\n", top->tr_we ? 'w' : 'r', top->tr_data & 0xFFFF);
		if (getenv("MS1_TRACE") && top->tr_valid)
			fprintf(stderr, "%c %06X %04X\n", top->tr_we ? 'w' : 'r', top->tr_addr, top->tr_data);
		if (top->vblank_rise && getenv("MS1_REGS"))
			fprintf(stderr, "frame regs: act=%04X t0c=%04X t1c=%04X t2c=%04X t0x=%04X t0y=%04X vramw=%u\n",
			        top->dbg_active, top->dbg_t0c, top->dbg_t1c, top->dbg_t2c, top->dbg_t0x, top->dbg_t0y, top->dbg_vramw),
			fprintf(stderr, "   ym=%u oki1=%u oki2=%u\n", top->dbg_ym_writes, top->dbg_oki1_writes, top->dbg_oki2_writes);
		if (top->vblank_rise && getenv("MS1_REGS"))
			fprintf(stderr, "   mcu: irq2=%u int1edges=%u\n", top->dbg_irq2, top->dbg_int1e), fprintf(stderr, "   mcuacc=%u bank!=0=%u\n", top->dbg_mcuacc, top->dbg_mcubank);
		if (top->vblank_rise) {
			if (px && getenv("MS1_PXCOUNT"))
				fprintf(stderr, "frame %zu: %zu pixels collected (expect %d)\n",
				        frames.size(), px, W * H);
			if (px) frames.push_back(cur);
			std::fill(cur.begin(), cur.end(), 0);
			px = 0;
		}
		// Sample ONLY on the pixel enable. rgb_valid is a register updated on
		// ce and therefore HOLDS across all eight clocks of a pixel; collecting
		// per clock advances the write pointer eight times per pixel, fills the
		// frame from the first eighth of the image and caps at exactly the
		// right total -- so even the pixel count looks correct while the frame
		// is nonsense.
		if (top->ce_pix_o && top->rgb_valid && px < cur.size())
			cur[px++] = top->rgb & 0xFFFFFF;
	}
	if (plog) fclose(plog);
	printf("captured %zu frames\n", frames.size());

	// ---- M3 gate: the savestate round trip.
	// Save the whole core at a frame boundary, run on, restore, run the same
	// span again and compare. Done inside one process so the two spans start
	// from provably identical state -- the only thing under test is whether
	// the image carries everything.
	if (getenv("MS1_SS")) {
		const size_t SS_WORDS = 0x30000;
		const long span = envl("MS1_SS_SPAN", 4);
		std::vector<uint16_t> img(SS_WORDS, 0);

		auto park = [&]() {
			top->ss_freeze = 1;
            long g = 0;
			while (!top->ss_frozen && g++ < 20000000) tick();
			return top->ss_frozen != 0;
		};
		auto release = [&]() {
			top->ss_resume = 1;
			for (int i = 0; i < 64; i++) tick();
			top->ss_freeze = 0;
			for (int i = 0; i < 64; i++) tick();
			top->ss_resume = 0;
		};
		auto stream_out = [&]() {
			top->ss_active = 1;
			for (size_t i = 0; i < SS_WORDS; i++) {
				top->ss_addr = i;
				tick(); tick(); tick();
				img[i] = top->ss_rdata;
			}
			top->ss_active = 0;
		};
		auto stream_in = [&]() {
			top->ss_active = 1;
			for (size_t i = 0; i < SS_WORDS; i++) {
				top->ss_addr = i; top->ss_wdata = img[i]; top->ss_wr = 1;
				tick();
				top->ss_wr = 0;
				tick();
			}
			top->ss_active = 0;
			top->ss_replay = 1;
			long g = 0;
			while (!top->ss_replay_done && g++ < 5000000) tick();
			top->ss_replay = 0;
			printf("  replay %s after %ld ticks\n",
			       top->ss_replay_done ? "done" : "TIMED OUT", g);
		};
		auto run_span = [&](std::vector<std::vector<uint32_t>> &out) {
			out.clear();
			std::vector<uint32_t> c(W * H, 0);
			size_t p = 0;
			uint64_t g = 0;
			while ((long)out.size() < span && g++ < 200000000ULL) {
				tick();
				if (top->vblank_rise) {
					if (p) out.push_back(c);
					std::fill(c.begin(), c.end(), 0);
					p = 0;
				}
				if (top->ce_pix_o && top->rgb_valid && p < c.size())
					c[p++] = top->rgb & 0xFFFFFF;
			}
		};

		// Loopback: park, stream the image out, stream the SAME image back in
		// without letting the core run, then stream out again and compare.
		// Nothing executes in between, so any word that comes back different
		// is a region whose restore path does not match its capture path --
		// which separates "the image is incomplete" from "the image is not
		// being written where it is read".
		if (getenv("MS1_SS_LOOPBACK")) {
			printf("loopback: parking...\n");
			if (!park()) { printf("  FAIL: never parked\n"); return 1; }
			stream_out();
			std::vector<uint16_t> first = img;
			top->ss_active = 1;
			for (size_t i = 0; i < SS_WORDS; i++) {
				top->ss_addr = i; top->ss_wdata = first[i]; top->ss_wr = 1;
				tick(); top->ss_wr = 0; tick();
			}
			top->ss_active = 0;
			stream_out();
			size_t bad = 0;
			std::map<std::string, size_t> byregion;
			auto region = [](size_t a) -> const char * {
				if (a < 0x08000) return "wram";
				if (a < 0x0A000) return "vram0";
				if (a < 0x0C000) return "vram1";
				if (a < 0x0E000) return "vram2";
				if (a < 0x0E400) return "palette";
				if (a < 0x0E600) return "vreg";
				if (a >= 0x0F000 && a < 0x10000) return "objram";
				if (a >= 0x10000 && a < 0x18000) return "sndram";
				if (a >= 0x18000 && a < 0x1C000) return "obj/spr buffers";
				if (a >= 0x1C000 && a < 0x1D000) return "mcu";
				if (a >= 0x1D000 && a < 0x1D010) return "main misc";
				if (a >= 0x1D010 && a < 0x1D020) return "main park";
				if (a >= 0x1D020 && a < 0x1D030) return "sound misc";
				if (a >= 0x1D030 && a < 0x1D040) return "sound park";
				if (a >= 0x1D040 && a < 0x1D050) return "raster";
				if (a >= 0x1D060 && a < 0x1D080) return "sprite fsm";
				if (a >= 0x1E000 && a < 0x1E100) return "ym shadow";
				if (a >= 0x20000) return "sprite plane";
				return "unmapped";
			};
			for (size_t i = 0; i < SS_WORDS; i++)
				if (first[i] != img[i]) { bad++; byregion[region(i)]++; }
			printf("  loopback: %zu of %zu words differ\n", bad, SS_WORDS);
			for (auto &kv : byregion)
				printf("    %-16s %zu words\n", kv.first.c_str(), kv.second);
			if (!bad) printf("  every region reads back exactly what was written\n");
			return bad ? 1 : 0;
		}

		// MS1_SS_DIVERGE=K: run K frames from the save point, snapshot the
		// state; restore, run the same K frames, snapshot again, and diff the
		// two images BY REGION. Pixels say the picture is wrong; this says
		// which piece of state made it wrong.
		if (const char *dv = getenv("MS1_SS_DIVERGE")) {
			long K = strtol(dv, nullptr, 0);
			auto span_n = [&](long n) {
				std::vector<std::vector<uint32_t>> tmp;
				std::vector<uint32_t> c(W * H, 0); size_t p2 = 0; uint64_t g = 0;
				while ((long)tmp.size() < n && g++ < 200000000ULL) {
					tick();
					if (top->vblank_rise) { if (p2) tmp.push_back(c); p2 = 0; }
					if (top->ce_pix_o && top->rgb_valid && p2 < c.size()) c[p2++] = top->rgb;
				}
			};
			if (!park()) { printf("FAIL: never parked\n"); return 1; }
			stream_out();
			std::vector<uint16_t> img0 = img;
			release();
			span_n(K);
			if (!park()) { printf("FAIL: never parked (A)\n"); return 1; }
			stream_out();
			std::vector<uint16_t> imgA = img;
			release();

			if (!park()) { printf("FAIL: never parked (restore)\n"); return 1; }
			img = img0; stream_in(); release();
			span_n(K);
			if (!park()) { printf("FAIL: never parked (B)\n"); return 1; }
			stream_out();

			auto region = [](size_t a) -> const char * {
				if (a < 0x08000) return "wram";
				if (a < 0x0A000) return "vram0";
				if (a < 0x0C000) return "vram1";
				if (a < 0x0E000) return "vram2";
				if (a < 0x0E400) return "palette";
				if (a < 0x0E600) return "vreg";
				if (a >= 0x0F000 && a < 0x10000) return "objram";
				if (a >= 0x10000 && a < 0x18000) return "sndram";
				if (a >= 0x18000 && a < 0x1A000) return "obj buffers";
				if (a >= 0x1A000 && a < 0x1C000) return "spr buffers";
				if (a >= 0x1C000 && a < 0x1C100) return "mcu iram";
				if (a >= 0x1C100 && a < 0x1C120) return "mcu cpu";
				if (a >= 0x1C120 && a < 0x1C140) return "mcu periph";
				if (a >= 0x1C140 && a < 0x1C150) return "mcu misc";
				if (a >= 0x1D000 && a < 0x1D010) return "main misc";
                if (a >= 0x1D010 && a < 0x1D020) return "main park";
				if (a >= 0x1D020 && a < 0x1D040) return "sound misc/park";
				if (a >= 0x1D040 && a < 0x1D050) return "raster";
				if (a >= 0x1D060 && a < 0x1D080) return "sprite fsm";
				if (a >= 0x1E000 && a < 0x1E100) return "ym shadow";
				if (a >= 0x20000) return "sprite plane";
				return "unmapped";
			};
			std::map<std::string, size_t> byr;
			std::map<std::string, size_t> firsta;
			size_t bad = 0;
			for (size_t i = 0; i < SS_WORDS; i++)
				if (imgA[i] != img[i]) {
					bad++; const char *r = region(i);
					if (!byr.count(r)) firsta[r] = i;
					byr[r]++;
				}
			printf("\nstate divergence after %ld frames: %zu of %zu words\n",
			       K, bad, SS_WORDS);
			for (auto &kv : byr)
				printf("    %-16s %6zu words   first at 0x%05zX\n",
				       kv.first.c_str(), kv.second, firsta[kv.first]);
			if (!bad) printf("    none -- the two runs are in identical state\n");
			return 0;
		}

		// MS1_SS_PEEK=K: the same divergence question, but read straight out of
		// the model instead of parking to stream an image. Parking pushes
		// registers on the game's own stack and takes a variable number of
		// cycles to get there, so a probe that parks reports stack tops and
		// clock phases differing and cannot tell that from real divergence --
		// it measures itself. This touches nothing.
		if (const char *pk = getenv("MS1_SS_PEEK")) {
			long K = strtol(pk, nullptr, 0);
			auto *R = top->rootp;
			struct Snap {
				std::vector<uint16_t> wram, v0, v1, v2, pal, obj, spr;
			};
			auto grab = [&](Snap &sn) {
				auto cp = [](auto &src, size_t n) {
					std::vector<uint16_t> v(n);
					for (size_t i = 0; i < n; i++) v[i] = (uint16_t)src[i];
					return v;
				};
				sn.wram = cp(R->ms1bcd_core__DOT__u_main__DOT__wram, 32768);
				sn.v0   = cp(R->ms1bcd_core__DOT__u_main__DOT__vr0, 8192);
				sn.v1   = cp(R->ms1bcd_core__DOT__u_main__DOT__vr1, 8192);
				sn.v2   = cp(R->ms1bcd_core__DOT__u_main__DOT__vr2, 8192);
				sn.pal  = cp(R->ms1bcd_core__DOT__u_main__DOT__pal, 1024);
				sn.obj  = cp(R->ms1bcd_core__DOT__u_main__DOT__obj, 4096);
				sn.spr  = cp(R->ms1bcd_core__DOT__u_main__DOT__spr_b2, 4096);
			};
			auto runf = [&](long n) {
				long got = 0; uint64_t g = 0;
				while (got < n && g++ < 200000000ULL) {
					tick();
					if (top->vblank_rise) got++;
				}
			};
			if (!park()) { printf("FAIL: never parked\n"); return 1; }
			stream_out();
			std::vector<uint16_t> img0 = img;
			release();
			runf(K);
			Snap A; grab(A);

			if (!park()) { printf("FAIL: never parked (restore)\n"); return 1; }
			img = img0; stream_in(); release();
			runf(K);
			Snap B; grab(B);

			auto cmp = [&](const char *nm, std::vector<uint16_t> &a,
			               std::vector<uint16_t> &b) {
				size_t n = 0, first = 0;
				for (size_t i = 0; i < a.size(); i++)
					if (a[i] != b[i]) { if (!n) first = i; n++; }
				if (n) printf("    %-10s %6zu words   first at 0x%05zX  (A=%04X B=%04X)\n",
				              nm, n, first, a[first], b[first]);
				return n;
			};
			printf("\nnon-invasive divergence after %ld frames:\n", K);
			size_t t = 0;
			t += cmp("wram", A.wram, B.wram);
			t += cmp("vram0", A.v0, B.v0);
			t += cmp("vram1", A.v1, B.v1);
			t += cmp("vram2", A.v2, B.v2);
			t += cmp("palette", A.pal, B.pal);
			t += cmp("objram", A.obj, B.obj);
			t += cmp("sprram", A.spr, B.spr);
			if (!t) printf("    none -- game state is identical\n");
			return 0;
		}

		printf("savestate: parking...\n");
		if (!park()) { printf("  FAIL: the core never parked\n"); return 1; }
		printf("  parked; streaming %zu words out\n", SS_WORDS);
		stream_out();
		size_t nz = 0; for (auto w : img) if (w) nz++;
		printf("  image has %zu non-zero words of %zu\n", nz, SS_WORDS);
		release();

		std::vector<std::vector<uint32_t>> A, B;
		run_span(A);
		printf("  span A: %zu frames\n", A.size());

		printf("savestate: parking to restore...\n");
		if (!park()) { printf("  FAIL: the core never parked for the load\n"); return 1; }
		stream_in();
		release();
		run_span(B);
		printf("  span B: %zu frames\n", B.size());

		// docs/PLAN.md M3 asks for the round trip to be "pixel-exact AFTER
		// frame 0": the frame in which the restore lands carries pipeline
		// state a snapshot cannot reasonably hold (the tilemap and sprite
		// read pipelines, a few pixels deep). Frame 0 is reported, and
		// judged separately from the gate.
		size_t same = 0, diffn = 0, f0 = 0;
		for (size_t i = 0; i < A.size() && i < B.size(); i++) {
			size_t d = 0, lit = 0;
			for (size_t k = 0; k < A[i].size(); k++) {
				if (A[i][k] != B[i][k]) d++;
				if (A[i][k]) lit++;
			}
			printf("  frame %zu after restore: %zu of %zu lit pixels differ%s\n",
			       i, d, lit, i ? "" : "   (frame 0, outside the gate)");
			if (const char *dd = getenv("MS1_SS_DUMP")) {
				char pa[512];
				snprintf(pa, sizeof pa, "mkdir -p %s", dd); if (system(pa)) {}
				snprintf(pa, sizeof pa, "%s/a%zu.raw", dd, i);
				FILE *fa = fopen(pa, "wb");
				if (fa) { fwrite(A[i].data(), 4, A[i].size(), fa); fclose(fa); }
				snprintf(pa, sizeof pa, "%s/b%zu.raw", dd, i);
				FILE *fb = fopen(pa, "wb");
				if (fb) { fwrite(B[i].data(), 4, B[i].size(), fb); fclose(fb); }
			}
			if (i == 0) { f0 = d; continue; }
			if (d == 0) same++; else diffn++;
		}
		bool met = (diffn == 0) && (same > 0);
		printf("\nROUND TRIP after frame 0: %zu identical, %zu differing -- %s\n",
		       same, diffn, met ? "GATE MET" : "GATE FAILED");
		printf("(frame 0 itself differed in %zu pixels)\n", f0);
		return met ? 0 : 1;
	}

	// MS1_STATEDIR dumps the sim's own video memories in exactly the layout
	// tools/dump_video_state.py produces, so tools/ms1_video_model.py -- which
	// is pixel-exact against MAME -- can be pointed at the RTL's state. That
	// separates "the video is rendering wrong" from "the video is faithfully
	// rendering the wrong state".
	if (const char *sd = getenv("MS1_STATEDIR")) {
		char cmd[512]; snprintf(cmd, sizeof cmd, "mkdir -p %s", sd);
		if (system(cmd)) {}
		auto *R = top->rootp;
		auto wr = [&](const char *name, const void *p, size_t n) {
			char path[512]; snprintf(path, sizeof path, "%s/%s", sd, name);
			FILE *f = fopen(path, "wb"); if (f) { fwrite(p, 1, n, f); fclose(f); }
		};
		static uint16_t buf[32768];
		#define DUMPARR(dst, arr, count) \
			for (size_t i = 0; i < (count); i++) buf[i] = (uint16_t)(arr)[i]; \
			wr(dst, buf, (count) * 2);
		DUMPARR("l0.vram", R->ms1bcd_core__DOT__u_main__DOT__vr0, 8192)
		DUMPARR("l1.vram", R->ms1bcd_core__DOT__u_main__DOT__vr1, 8192)
		DUMPARR("l2.vram", R->ms1bcd_core__DOT__u_main__DOT__vr2, 8192)
		DUMPARR("palette.bin", R->ms1bcd_core__DOT__u_main__DOT__pal, 1024)
		DUMPARR("objram.bin", R->ms1bcd_core__DOT__u_main__DOT__obj_b2, 4096)
		DUMPARR("spriteram.bin", R->ms1bcd_core__DOT__u_main__DOT__spr_b2, 4096)
		char rp[512]; snprintf(rp, sizeof rp, "%s/regs.txt", sd);
		FILE *rf = fopen(rp, "w");
		if (rf) {
			fprintf(rf, "set rtl\nmode %d\nnlayers 3\nframe 0\n", mode);
			fprintf(rf, "active_layers %04X\n", top->dbg_active);
			fprintf(rf, "sprite_flag %04X\n", top->dbg_sf);
			fprintf(rf, "sprite_bank %04X\n", top->dbg_sb);
			fprintf(rf, "screen_flag %04X\n", top->dbg_scf);
			fprintf(rf, "t0_sx %04X\nt0_sy %04X\nt0_ctrl %04X\n", top->dbg_t0x, top->dbg_t0y, top->dbg_t0c);
			fprintf(rf, "t1_sx %04X\nt1_sy %04X\nt1_ctrl %04X\n", top->dbg_t1x, top->dbg_t1y, top->dbg_t1c);
			fprintf(rf, "t2_sx %04X\nt2_sy %04X\nt2_ctrl %04X\n", top->dbg_t2x, top->dbg_t2y, top->dbg_t2c);
			fclose(rf);
		}
		printf("dumped video state to %s\n", sd);
	}

	// MS1_FRAMEDIR dumps every captured frame so the offset search and the
	// comparison can be redone in seconds instead of re-running the sim.
	if (const char *fd = getenv("MS1_FRAMEDIR")) {
		char path[512];
		snprintf(path, sizeof path, "mkdir -p %s", fd);
		if (system(path)) {}
		for (size_t i = 0; i < frames.size(); i++) {
			snprintf(path, sizeof path, "%s/f%zu.raw", fd, i);
			FILE *f = fopen(path, "wb");
			if (f) { fwrite(frames[i].data(), 4, frames[i].size(), f); fclose(f); }
		}
		printf("dumped %zu frames to %s\n", frames.size(), fd);
	}

	// ---- find the fixed offset that aligns the two runs
	int best_k = 0; long best_score = -1;
	std::vector<std::vector<uint32_t>> ref;
	for (int i = 0; ; i++) {
		auto v = slurp(d + "/frames/f" + std::to_string(i) + ".raw", false);
		if (v.size() != (size_t)W * H * 4) break;
		ref.emplace_back((uint32_t *)v.data(), (uint32_t *)v.data() + W * H);
	}
	printf("reference frames: %zu\n", ref.size());
	if (ref.empty() || frames.empty()) { delete top; return 1; }

	int probe = 8;
	for (int k = 0; k + (int)frames.size() <= (int)ref.size() + 8 && k < 400; k++) {
		long score = 0, used = 0;
		for (int i = 0; i < (int)frames.size() && i < probe * 12; i += 12) {
			if (i + k >= (int)ref.size()) break;
			long same = 0;
			for (int p = 0; p < W * H; p++)
				if ((ref[i + k][p] & 0xFFFFFF) == frames[i][p]) same++;
			score += same; used++;
		}
		if (used && score > best_score) { best_score = score; best_k = k; }
	}
	printf("best fixed offset k = %d\n", best_k);

	int exact = 0, cmp = 0; long worst = 0;
	for (int i = 0; i < (int)frames.size(); i++) {
		if (i + best_k >= (int)ref.size()) break;
		long diff = 0, nb = 0;
		for (int p = 0; p < W * H; p++) {
			uint32_t e = ref[i + best_k][p] & 0xFFFFFF;
			if (e) nb++;
			if (e != frames[i][p]) diff++;
		}
		cmp++; if (!diff) exact++; if (diff > worst) worst = diff;
		if (getenv("MS1_PERFRAME"))
			printf("  frame %3d (mame %3d): nonblank %6ld  diff %6ld\n", i, i + best_k, nb, diff);
	}
	printf("compared %d frames at offset %d: %d exact, worst %ld differing pixels\n",
	       cmp, best_k, exact, worst);
	delete top;
	return exact == cmp ? 0 : 2;
}
