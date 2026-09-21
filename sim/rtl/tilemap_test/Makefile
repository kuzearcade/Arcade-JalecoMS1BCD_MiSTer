RTL := ../../../rtl/jaleco
all: obj_dir/Vms1_tilemap
obj_dir/Vms1_tilemap: $(RTL)/ms1_tilemap.sv tb.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --top-module ms1_tilemap -y $(RTL) $(RTL)/ms1_tilemap.sv tb.cpp -o Vms1_tilemap
