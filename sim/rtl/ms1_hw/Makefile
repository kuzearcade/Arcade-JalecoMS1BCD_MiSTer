RTL := ../../../rtl
MODELS := ../../models
V := verilator --cc --exe --build -O2 -CFLAGS -O2 --x-assign fast --x-initial fast +define+SIMULATION \
	-Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTH -Wno-PINCONNECTEMPTY \
	-Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN -Wno-CASEINCOMPLETE \
	-Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET -Wno-UNOPTFLAT \
	-Wno-MULTIDRIVEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-BLKSEQ -Wno-PINMISSING
all: obj_dir/Vms1_hw_top
obj_dir/Vms1_hw_top: ms1_hw_top.sv tb_hw.cpp $(RTL)/ms1bcd/ms1bcd_rom_hw.sv $(RTL)/ms1bcd/ms1bcd_rom_map.vh
	$(V) --top-module ms1_hw_top +incdir+$(RTL)/ms1bcd \
		-y $(RTL) -y $(RTL)/ms1bcd -y $(MODELS) \
		ms1_hw_top.sv tb_hw.cpp -o Vms1_hw_top
