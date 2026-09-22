RTL := ../../../rtl
V := verilator --cc --exe --build -O3 -CFLAGS -O3 --x-assign fast --x-initial fast \
	-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTH -Wno-PINCONNECTEMPTY \
	-Wno-EOFNEWLINE -Wno-TIMESCALEMOD -Wno-VARHIDDEN -Wno-CASEINCOMPLETE \
	-Wno-GENUNNAMED -Wno-BLKANDNBLK -Wno-SYNCASYNCNET -Wno-UNOPTFLAT -Wno-MULTIDRIVEN
all: obj_dir/Vms1_sound
obj_dir/Vms1_sound: $(RTL)/ms1bcd/ms1_sound.sv tb_snd.cpp
	$(V) --top-module ms1_sound \
		-y $(RTL)/ms1bcd -y $(RTL)/savestate -y $(RTL)/third_party/fx68k \
		-y $(RTL)/third_party/jt51/hdl -y $(RTL)/third_party/jt6295/hdl \
		$(RTL)/ms1bcd/ms1_sound.sv \
		$(RTL)/third_party/fx68k/fx68k.sv $(RTL)/third_party/fx68k/fx68kAlu.sv \
		$(RTL)/third_party/fx68k/uaddrPla.sv \
		tb_snd.cpp -o Vms1_sound
