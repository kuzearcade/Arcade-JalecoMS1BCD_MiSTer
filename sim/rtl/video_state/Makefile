# video_state: rtl/jaleco video against a captured MAME frame (M1 gate).
RTL := ../../../rtl/jaleco
OBJ := obj_dir

.PHONY: all run clean
all: $(OBJ)/Vms1_video

$(OBJ)/Vms1_video: $(RTL)/ms1_video.sv $(RTL)/ms1_tilemap.sv $(RTL)/ms1_sprites.sv $(RTL)/ms1_prio.sv tb_video_state.cpp
	verilator --cc --exe --build -Wall -Wno-fatal --top-module ms1_video \
		-y $(RTL) \
		$(RTL)/ms1_video.sv $(RTL)/ms1_tilemap.sv $(RTL)/ms1_sprites.sv $(RTL)/ms1_prio.sv \
		tb_video_state.cpp -o Vms1_video

run: $(OBJ)/Vms1_video
	./$(OBJ)/Vms1_video $(DIR)

clean:
	rm -rf $(OBJ)
