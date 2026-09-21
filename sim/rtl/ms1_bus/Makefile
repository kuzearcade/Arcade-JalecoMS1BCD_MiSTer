RTL := ../../../rtl
V := verilator --cc --exe --build -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED \
	-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN \
	-Wno-CASEINCOMPLETE -Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET \
	-Wno-UNOPTFLAT -Wno-MULTIDRIVEN
all: obj_dir/Vms1_main
obj_dir/Vms1_main: $(RTL)/ms1bcd/ms1_main.sv $(RTL)/jaleco/ms1_iomcu.sv tb_ms1_bus.cpp
	$(V) --top-module ms1_main \
		-y $(RTL)/ms1bcd -y $(RTL)/jaleco -y $(RTL)/tlcs90 -y $(RTL)/third_party/fx68k \
		$(RTL)/ms1bcd/ms1_main.sv $(RTL)/jaleco/ms1_iomcu.sv \
		$(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv \
		$(RTL)/third_party/fx68k/fx68k.sv $(RTL)/third_party/fx68k/fx68kAlu.sv \
		$(RTL)/third_party/fx68k/uaddrPla.sv \
		tb_ms1_bus.cpp -o Vms1_main
