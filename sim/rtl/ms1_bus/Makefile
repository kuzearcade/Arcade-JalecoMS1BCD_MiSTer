RTL := ../../../rtl
V := verilator --cc --exe --build -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED \
	-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN \
	-Wno-CASEINCOMPLETE -Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET \
	-Wno-UNOPTFLAT -Wno-MULTIDRIVEN
# EVERY .sv the -y search paths can pull in, not just the handful named on
# the command line. Verilator finds ms1_video.sv, ms1_tilemap.sv, ms1_main.sv
# and the rest through -y, and make cannot see that: a fix in one of them left
# the old binary in place and the next run measured the bug that had just been
# fixed. Same failure class as MS1-48, one layer down. MS1-58.
RTLSRC := $(wildcard $(RTL)/*.sv $(RTL)/*.v $(RTL)/ms1bcd/*.sv $(RTL)/ms1bcd/*.vh \
                     $(RTL)/jaleco/*.sv $(RTL)/tlcs90/*.sv $(RTL)/savestate/*.sv)
all: obj_dir/Vms1_main
obj_dir/Vms1_main: tb_ms1_bus.cpp $(RTLSRC)
	$(V) --top-module ms1_main \
		-y $(RTL)/ms1bcd -y $(RTL)/jaleco -y $(RTL)/tlcs90 -y $(RTL)/third_party/fx68k \
		$(RTL)/ms1bcd/ms1_main.sv $(RTL)/jaleco/ms1_iomcu.sv \
		$(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv \
		$(RTL)/third_party/fx68k/fx68k.sv $(RTL)/third_party/fx68k/fx68kAlu.sv \
		$(RTL)/third_party/fx68k/uaddrPla.sv \
		tb_ms1_bus.cpp -o Vms1_main
