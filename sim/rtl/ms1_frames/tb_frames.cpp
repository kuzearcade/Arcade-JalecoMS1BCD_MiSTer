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

static std::vector<uint8_t> slurp(const std::string &p, bool req = true) {
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) { if (req) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(1); } return {}; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n);
	if (n && fread(v.data(), 1, n, f) != (size_t)n) exit(1);
	fclose(f); return v;
}
static uint8_t rd8(const std::vector<uint8_t> &v, size_t i) { return i < v.size() ? v[i] : 0; }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 9) { fprintf(stderr, "usage: %s dir mode frames p1 p2 dsw1 dsw2 sys\n", argv[0]); return 1; }
	std::string d = argv[1];
	int mode = atoi(argv[2]);
	int nframes = atoi(argv[3]);

	auto rom  = slurp(d + "/maincpu.bin");
	auto mrom = slurp(d + "/iomcu.bin");
	auto g0 = slurp(d + "/gfx0.bin"), g1 = slurp(d + "/gfx1.bin"), g2 = slurp(d + "/gfx2.bin", false);
	auto srom = slurp(d + "/sprites.bin");
	auto prom = slurp(d + "/prom.bin");

	Vms1bcd_core *top = new Vms1bcd_core;
	top->mode = mode;
	top->in_p1     = strtol(argv[4], nullptr, 16) & 0xFF;
	top->in_p2     = strtol(argv[5], nullptr, 16) & 0xFF;
	top->in_dsw1   = strtol(argv[6], nullptr, 16) & 0xFF;
	top->in_dsw2   = strtol(argv[7], nullptr, 16) & 0xFF;
	top->in_system = strtol(argv[8], nullptr, 16) & 0xFF;
	top->reset = 1; top->clk = 0; top->mcu_rom_we = 0;

	auto serve = [&]() {
		unsigned ra = top->rom_addr * 2;
		top->rom_data   = (ra + 1 < rom.size()) ? (rom[ra] << 8) | rom[ra + 1] : 0;
		top->l0_rom_data = rd8(g0, top->l0_rom_addr);
		top->l1_rom_data = rd8(g1, top->l1_rom_addr);
		top->l2_rom_data = rd8(g2, top->l2_rom_addr);
		top->spr_rom_data = rd8(srom, top->spr_rom_addr);
		top->prom_data    = rd8(prom, top->prom_addr);
		top->eval();
	};
	auto tick = [&]() {
		top->clk = 0; top->eval(); serve();
		top->clk = 1; top->eval(); serve();
	};

	for (int i = 0; i < (int)mrom.size(); i++) {
		top->mcu_rom_we = 1; top->mcu_rom_addr = i; top->mcu_rom_data = mrom[i];
		tick();
	}
	top->mcu_rom_we = 0;
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
			fprintf(stderr, "   scf=%04X palnz=%u opq0=%u opq2=%u\n", top->dbg_scf, top->dbg_palnz, top->dbg_opaque0, top->dbg_opaque2);
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
