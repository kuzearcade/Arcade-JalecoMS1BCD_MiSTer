// video_state harness: drive rtl/jaleco/ms1_video.sv from a captured MAME
// state dump and compare its frame with MAME's own, pixel for pixel.
//
// This is the M1 gate's instrument. docs/PLAN.md M1 asks for the three tilemap
// layers, the sprite engine, the priority resolver and the palette "driven
// from a MAME RAM dump through a video_state harness", pixel-exact.
//
//   ./obj_dir/Vms1_video <state_dir> [out.ppm]
//
// <state_dir> comes from tools/dump_video_state.py, which has already applied
// the three different frame offsets of docs/known-issues.md MS1-11, so
// everything here is simply "the state that produced this frame".
//
// Memories live on this side and are served combinationally: the RTL
// registers its addresses, so after a posedge we read the new address, put the
// data on the input, and eval again. That is the same bus convention the rest
// of this project's sims use.
#include "Vms1_video.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static std::vector<uint8_t> slurp(const std::string &p, bool required = true) {
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) {
		if (required) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(1); }
		return {};
	}
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n);
	if (n && fread(v.data(), 1, n, f) != (size_t)n) { fprintf(stderr, "short read %s\n", p.c_str()); exit(1); }
	fclose(f); return v;
}

static uint16_t rd16(const std::vector<uint8_t> &v, size_t word) {
	size_t b = word * 2;
	if (b + 1 >= v.size()) return 0;
	return (uint16_t)(v[b] | (v[b + 1] << 8));
}
static uint8_t rd8(const std::vector<uint8_t> &v, size_t b) {
	return b < v.size() ? v[b] : 0;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 2) { fprintf(stderr, "usage: %s <state_dir> [out.ppm]\n", argv[0]); return 1; }
	std::string d = argv[1];

	auto l0v = slurp(d + "/l0.vram"), l1v = slurp(d + "/l1.vram"), l2v = slurp(d + "/l2.vram");
	auto g0 = slurp(d + "/gfx0.bin"), g1 = slurp(d + "/gfx1.bin"), g2 = slurp(d + "/gfx2.bin", false);
	auto obj = slurp(d + "/objram.bin"), spr = slurp(d + "/spriteram.bin");
	auto srom = slurp(d + "/sprites.bin");
	auto pal = slurp(d + "/palette.bin"), prom = slurp(d + "/prom.bin");
	auto expected = slurp(d + "/expected.raw");

	// registers
	int mode = 0, nlayers = 3;
	uint16_t reg[16] = {0};
	const char *names[] = {"active_layers","sprite_flag","sprite_bank","screen_flag",
	                       "t0_sx","t0_sy","t0_ctrl","t1_sx","t1_sy","t1_ctrl",
	                       "t2_sx","t2_sy","t2_ctrl"};
	{
		FILE *f = fopen((d + "/regs.txt").c_str(), "r");
		if (!f) { fprintf(stderr, "no regs.txt\n"); return 1; }
		char k[64], v[64];
		while (fscanf(f, "%63s %63s", k, v) == 2) {
			if (!strcmp(k, "mode")) mode = atoi(v);
			else if (!strcmp(k, "nlayers")) nlayers = atoi(v);
			else for (int i = 0; i < 13; i++)
				if (!strcmp(k, names[i])) reg[i] = (uint16_t)strtol(v, nullptr, 16);
		}
		fclose(f);
	}

	Vms1_video *top = new Vms1_video;
	top->mode = mode; top->nlayers = nlayers;
	top->active_layers = reg[0]; top->sprite_flag = reg[1];
	top->sprite_bank  = reg[2]; top->screen_flag = reg[3];
	top->t0_sx = reg[4]; top->t0_sy = reg[5]; top->t0_ctrl = reg[6];
	top->t1_sx = reg[7]; top->t1_sy = reg[8]; top->t1_ctrl = reg[9];
	top->t2_sx = reg[10]; top->t2_sy = reg[11]; top->t2_ctrl = reg[12];
	top->vx = 0; top->vy = 0; top->vvalid = 0;
	top->ce = 1; top->reset = 1; top->spr_start = 0; top->clk = 0;

	auto serve = [&]() {
		top->l0_vram_data = rd16(l0v, top->l0_vram_addr);
		top->l1_vram_data = rd16(l1v, top->l1_vram_addr);
		top->l2_vram_data = rd16(l2v, top->l2_vram_addr);
		top->l0_rom_data  = rd8(g0, top->l0_rom_addr);
		top->l1_rom_data  = rd8(g1, top->l1_rom_addr);
		top->l2_rom_data  = rd8(g2, top->l2_rom_addr);
		top->obj_data     = rd16(obj, top->obj_addr);
		top->spr_ram_data = rd16(spr, top->spr_ram_addr);
		top->spr_rom_data = rd8(srom, top->spr_rom_addr);
		top->prom_data    = rd8(prom, top->prom_addr);
		top->pal_data     = rd16(pal, top->pal_addr);
		top->eval();
	};
	auto tick = [&]() {
		top->clk = 0; top->eval(); serve();
		top->clk = 1; top->eval(); serve();
	};

	for (int i = 0; i < 4; i++) tick();
	top->reset = 0;
	for (int i = 0; i < 4; i++) tick();

	// ---- sprite pass
	top->spr_start = 1; tick(); top->spr_start = 0;
	long guard = 0;
	while (top->spr_busy && guard < 200000000L) { tick(); guard++; }
	if (top->spr_busy) { fprintf(stderr, "sprite pass did not finish\n"); return 1; }
	printf("sprite pass: %ld clocks\n", guard);

	// ---- sweep the visible window. ms1_video's latency is FOUR ticks, so
	// pixel i fed at tick i emerges after tick i+4.
	const int W = 256, H = 224, LAT = 4;
	std::vector<uint32_t> got(W * H, 0);
	long total = (long)W * H + LAT;
	for (long i = 0; i < total; i++) {
		long fi = i;                      // index being fed
		if (fi < (long)W * H) {
			top->vx = fi % W; top->vy = fi / W; top->vvalid = 1;
		} else { top->vvalid = 0; }
		tick();
		long oi = i - LAT;                // index whose pixel is emerging
		if (oi >= 0 && oi < (long)W * H && top->rgb_valid)
			got[oi] = top->rgb & 0xFFFFFF;
	}

	// ---- compare
	int diff = 0, nb = 0;
	const uint32_t *exp32 = (const uint32_t *)expected.data();
	for (int i = 0; i < W * H; i++) {
		uint32_t e = exp32[i] & 0xFFFFFF;
		if (e) nb++;
		if (e != got[i]) diff++;
	}
	printf("frame: %d non-blank (MAME), %d differing pixels  %s\n",
	       nb, diff, diff == 0 ? "MATCH" : "DIFFERS");

	if (argc > 2) {
		FILE *f = fopen(argv[2], "wb");
		fprintf(f, "P6\n%d %d\n255\n", W, H);
		for (int i = 0; i < W * H; i++) {
			uint8_t px[3] = {(uint8_t)(got[i] >> 16), (uint8_t)(got[i] >> 8), (uint8_t)got[i]};
			fwrite(px, 1, 3, f);
		}
		fclose(f);
		printf("wrote %s\n", argv[2]);
	}
	delete top;
	return diff == 0 ? 0 : 2;
}
