RTL := ../../../rtl
all: obj_dir/Vms1_iomcu
obj_dir/Vms1_iomcu: $(RTL)/jaleco/ms1_iomcu.sv $(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv tb_iomcu.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --top-module ms1_iomcu \
		-y $(RTL)/jaleco -y $(RTL)/tlcs90 \
		$(RTL)/jaleco/ms1_iomcu.sv $(RTL)/tlcs90/tlcs90.sv $(RTL)/tlcs90/tlcs90_periph_ref.sv \
		tb_iomcu.cpp -o Vms1_iomcu
