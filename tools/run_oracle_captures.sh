#!/usr/bin/env bash
# MAME needs SDL dummy drivers here: without them it blocks in SDL device
# init at machine start (zero CPU, no output, unkillable by SIGTERM).
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
cd ~/Arcade-JalecoMS1BCD_MiSTer
# Absolute, so the script works from any working directory. A RELATIVE
# -rompath silently becomes "ROM not found" the moment MAME is started
# from anywhere else, which reads like a broken romset and is not one.
ROMS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mame_roms"
run() {  # name set skip frames [extra env]
  local name=$1 set=$2 skip=$3 frames=$4; shift 4
  echo "=== $name ($set) ==="
  env MS1_OUT=sim/oracle/traces/$name MS1_SKIP=$skip MS1_FRAMES=$frames \
      MS1_PIX=1 MS1_STATE=1 "$@" \
      timeout 900 ~/mame/mame -noreadconfig "$set" -rompath "$ROMS" \
      -video none -sound none -nothrottle \
      -autoboot_script sim/oracle/ms1_capture.lua 2>&1 | tail -3
}
run bigstrik_split  bigstrik 350 250
run edf_pages       edf      100 200
run hayaosi1_pages  hayaosi1  60 200
run avspirit_flip   avspirit 1800 150 MS1_DIP="Flip Screen=0"
echo ALLDONE
