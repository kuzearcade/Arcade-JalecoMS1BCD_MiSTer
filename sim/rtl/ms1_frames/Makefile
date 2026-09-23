RTL := ../../../rtl
V := verilator --cc --exe --build -O3 -CFLAGS -O3 --x-assign fast --x-initial fast -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED \
	-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN \
	-Wno-CASEINCOMPLETE -Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET \
	-Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-LATCH --public-flat-rw
# EVERY .sv the -y search paths can pull in, not just the handful named on
# the command line. Verilator finds ms1_video.sv, ms1_tilemap.sv, ms1_main.sv
# and the rest through -y, and make cannot see that: a fix in one of them left
# the old binary in place and the next run measured the bug that had just been
# fixed. Same failure class as MS1-48, one layer down. MS1-58.
RTLSRC := $(wildcard $(RTL)/*.sv $(RTL)/*.v $(RTL)/ms1bcd/*.sv $(RTL)/ms1bcd/*.vh \
                     $(RTL)/jaleco/*.sv $(RTL)/tlcs90/*.sv $(RTL)/savestate/*.sv)
all: obj_dir/Vms1bcd_core
obj_dir/Vms1bcd_core: tb_frames.cpp $(RTLSRC)
	$(V) --top-module ms1bcd_core \
		-y $(RTL)/ms1bcd -y $(RTL)/jaleco -y $(RTL)/tlcs90 -y $(RTL)/savestate -y $(RTL)/third_party/fx68k \
		-y $(RTL)/third_party/jt51/hdl -y $(RTL)/third_party/jt6295/hdl \
		$(RTL)/ms1bcd/ms1bcd_core.sv $(RTL)/ms1bcd/ms1_main.sv $(RTL)/ms1bcd/ms1_sound.sv \
		$(RTL)/jaleco/ms1_video.sv $(RTL)/jaleco/ms1_tilemap.sv \
		$(RTL)/jaleco/ms1_sprites.sv $(RTL)/jaleco/ms1_prio.sv $(RTL)/jaleco/ms1_iomcu.sv \
		$(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv $(RTL)/savestate/ss_m68k_park.sv \
		$(RTL)/third_party/fx68k/fx68k.sv $(RTL)/third_party/fx68k/fx68kAlu.sv \
		$(RTL)/third_party/fx68k/uaddrPla.sv \
		tb_frames.cpp -o Vms1bcd_core
