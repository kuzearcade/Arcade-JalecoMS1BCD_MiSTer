RTL := ../../../rtl
MODELS := ../../models
V := verilator --cc --exe --build -O2 -CFLAGS -O2 --x-assign fast --x-initial fast +define+SIMULATION \
	-Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTH -Wno-PINCONNECTEMPTY \
	-Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN -Wno-CASEINCOMPLETE \
	-Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET -Wno-UNOPTFLAT \
	-Wno-MULTIDRIVEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-PINMISSING
all: obj_dir/Vms1_hw_top
obj_dir/Vms1_hw_top: ms1_hw_top.sv $(RTL)/ms1bcd/ms1bcd_core.sv tb_hw.cpp $(RTL)/ms1bcd/ms1bcd_rom_hw.sv $(RTL)/ms1bcd/ms1bcd_rom_map.vh
	$(V) --top-module ms1_hw_top +incdir+$(RTL)/ms1bcd \
		-y $(RTL) -y $(RTL)/ms1bcd -y $(RTL)/jaleco -y $(RTL)/tlcs90 -y $(RTL)/savestate -y $(RTL)/third_party/fx68k -y $(RTL)/third_party/jt51/hdl -y $(RTL)/third_party/jt6295/hdl -y $(MODELS) \
		ms1_hw_top.sv \
		$(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv $(RTL)/savestate/ss_m68k_park.sv \
		$(RTL)/third_party/fx68k/fx68k.sv $(RTL)/third_party/fx68k/fx68kAlu.sv \
		$(RTL)/third_party/fx68k/uaddrPla.sv \
		tb_hw.cpp -o Vms1_hw_top
