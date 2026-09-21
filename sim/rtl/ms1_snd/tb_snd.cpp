// M2 gates (3) and (4): the sound subsystem alone, driven by MAME's own
// sequence of sound-latch commands.
//
//   ./obj_dir/Vms1_sound <dir> <mode> <frames> [latch.log]
//
// The main CPU writes the sound latch only a handful of times in a whole
// attract cycle -- 15 times in 2400 frames on avspirit -- and the sound CPU
// does everything else itself off the YM2151's timer interrupt. So the entire
// input to the sound subsystem is that short list, and replaying it drives the
// sound hardware faithfully without simulating the video, the main CPU or the
// protection MCU. That is what makes it possible to reach frame 1586, where
// avspirit first touches an OKI, in minutes rather than hours.
//
// Outputs: per-frame YM/OKI write counts (gate 3) and, with MS1_WAV, 48 kHz
// signed 16-bit mono of the mix and of each source in isolation (gate 4).
#include "Vms1_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>

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
	if (argc < 4) { fprintf(stderr, "usage: %s dir mode frames [latch.log]\n", argv[0]); return 1; }
	std::string d = argv[1];
	int mode = atoi(argv[2]);
	long frames = atol(argv[3]);

	auto rom = slurp(d + "/audiocpu.bin");
	auto o1  = slurp(d + "/oki1.bin", false);
	auto o2  = slurp(d + "/oki2.bin", false);

	// Each event carries the absolute 48 MHz clock at which MAME performed it,
	// so the replay lands on the same cycle rather than the frame boundary.
	std::vector<std::pair<long, unsigned>> latch;   // absclk -> value
	if (argc > 4) {
		FILE *f = fopen(argv[4], "r");
		if (f) {
			long fr, ck; unsigned v;
			while (fscanf(f, "%ld %x %ld", &fr, &v, &ck) == 3) latch.push_back({ck, v});
			fclose(f);
		}
	}
	printf("latch commands: %zu\n", latch.size());

	// screen_flag bit 4: the main CPU's reset line over the whole sound side.
	std::vector<std::pair<long, int>> sres;
	if (const char *sp = getenv("MS1_SRESET")) {
		FILE *f = fopen(sp, "r");
		if (f) { long fr, ck; int v;
			while (fscanf(f, "%ld %d %ld", &fr, &v, &ck) == 3) sres.push_back({ck, v});
			fclose(f); }
	}
	printf("sreset transitions: %zu\n", sres.size());

	Vms1_sound *top = new Vms1_sound;
	top->mode = mode;
	top->oki_status_real = getenv("MS1_OKI_STATUS_REAL") ? 1 : 0;
	top->reset = 1; top->clk = 0; top->latch_we = 0; top->latch_data = 0;
	top->sreset = 0;

	auto serve = [&]() {
		unsigned ra = top->rom_addr * 2;
		top->rom_data = (ra + 1 < rom.size()) ? (rom[ra] << 8) | rom[ra + 1] : 0;
		top->oki1_rom_data = rd8(o1, top->oki1_rom_addr);
		top->oki2_rom_data = rd8(o2, top->oki2_rom_addr);
		top->eval();
	};
	auto tick = [&]() {
		top->clk = 0; top->eval(); serve();
		top->clk = 1; top->eval(); serve();
	};

	for (int i = 0; i < 64; i++) tick();
	top->reset = 0;

	// 384 x 278 pixels at 6 MHz = 854016 clocks of 48 MHz per frame.
	const long FRAME_CLK = 384L * 278L * 8L;
	const long AUDIO_DIV = 1000;          // 48 MHz / 48 kHz

	FILE *wmix = nullptr, *wfm = nullptr, *wo1 = nullptr, *wo2 = nullptr;
	if (const char *w = getenv("MS1_WAV")) {
		std::string b = w;
		wmix = fopen((b + "_mix.raw").c_str(), "wb");
		wfm  = fopen((b + "_fm.raw").c_str(),  "wb");
		wo1  = fopen((b + "_oki1.raw").c_str(), "wb");
		wo2  = fopen((b + "_oki2.raw").c_str(), "wb");
	}
	FILE *cnt = nullptr;
	if (const char *c = getenv("MS1_COUNTS")) cnt = fopen(c, "w");

	// MS1_TRACE=<n>: histogram of the addresses the sound CPU touches over the
	// first <n> frames, so a spin loop shows up as a handful of hot addresses.
	long trace_frames = getenv("MS1_TRACE") ? atol(getenv("MS1_TRACE")) : 0;
	std::vector<std::pair<unsigned, unsigned>> hot;   // addr -> count (small map)
	FILE *tf = nullptr; long tf_left = 0;
	if (const char *t = getenv("MS1_BUSLOG")) {
		tf = fopen(t, "w");
		tf_left = getenv("MS1_BUSN") ? atol(getenv("MS1_BUSN")) : 20000;
	}

	size_t li = 0, si = 0;
	long acc = 0;
	for (long f = 0; f < frames; f++) {
		for (long c = 0; c < FRAME_CLK; c++) {
			long now = f * FRAME_CLK + c;
			while (si < sres.size() && sres[si].first <= now) {
				top->sreset = sres[si].second; si++;
			}
			if (li < latch.size() && latch[li].first <= now) {
				top->latch_data = latch[li].second;
				top->latch_we = 1; tick(); top->latch_we = 0;
				li++;
			}
			tick();
			if (tf && top->dbg_acc) {
				fprintf(tf, "%ld %06X %c %04X\n", f, top->dbg_addr, top->dbg_rw ? 'R' : 'W', top->dbg_rw ? top->dbg_rdata : top->dbg_wdata);
				if (--tf_left <= 0) { fclose(tf); tf = nullptr; }
			}
			if (f < trace_frames && top->dbg_acc) {
				unsigned ad = top->dbg_addr | (top->dbg_rw ? 0x1000000u : 0u);
				bool found = false;
				for (auto &h : hot) if (h.first == ad) { h.second++; found = true; break; }
				if (!found && hot.size() < 4096) hot.push_back({ad, 1});
			}
			if (++acc >= AUDIO_DIV) {
				acc = 0;
				if (wmix) {
					int16_t s = (int16_t)top->snd_l;              fwrite(&s, 2, 1, wmix);
					int16_t a = (int16_t)top->dbg_fm_l;           fwrite(&a, 2, 1, wfm);
					// the OKI taps are 14-bit; shift to the same scale as the FM
					int16_t b1 = (int16_t)(((int16_t)top->dbg_oki1) << 2); fwrite(&b1, 2, 1, wo1);
					int16_t b2 = (int16_t)(((int16_t)top->dbg_oki2) << 2); fwrite(&b2, 2, 1, wo2);
				}
			}
		}
		if (cnt) fprintf(cnt, "%ld ym=%u oki1=%u oki2=%u\n", f,
		                 top->dbg_ym_writes, top->dbg_oki1_writes, top->dbg_oki2_writes);
	}
	printf("after %ld frames: ym=%u oki1=%u oki2=%u  ymirq=%u iack=%u\n", frames,
	       top->dbg_ym_writes, top->dbg_oki1_writes, top->dbg_oki2_writes,
	       top->dbg_ymirq, top->dbg_iack);
	printf("per frame: phi1=%.0f ym_cen=%.0f ym_cen_p1=%.0f (expect 124544 / 62272 / 31136)\n",
	       (double)top->dbg_phi1 / frames, (double)top->dbg_cen / frames,
	       (double)top->dbg_cenp1 / frames);
	if (trace_frames) {
		std::sort(hot.begin(), hot.end(),
		          [](auto &a, auto &b) { return a.second > b.second; });
		printf("hottest bus addresses over %ld frames (R = read):\n", trace_frames);
		for (size_t i = 0; i < hot.size() && i < 24; i++)
			printf("  %06X %s %u\n", hot[i].first & 0xFFFFFF,
			       (hot[i].first & 0x1000000) ? "R" : "W", hot[i].second);
	}
	if (wmix) { fclose(wmix); fclose(wfm); fclose(wo1); fclose(wo2); }
	if (cnt) fclose(cnt);
	delete top;
	return 0;
}
