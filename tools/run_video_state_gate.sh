#!/usr/bin/env bash
# The M1 gate, through the RTL: every scene docs/PLAN.md names, dumped from a
# MAME capture and pushed through sim/rtl/video_state against MAME's frame.
set -u
HARNESS=sim/rtl/video_state/obj_dir/Vms1_video
TMP=${TMP:-/tmp/vsgate}
mkdir -p "$TMP"
pass=0; fail=0
run() {  # label capture frames...
	local label="$1" cap="$2"; shift 2
	for F in "$@"; do
		local dir="$TMP/$(basename $cap)_$F"
		[ -d "$dir" ] || python3 tools/dump_video_state.py "sim/oracle/traces/$cap" "$F" "$dir" >/dev/null
		local out; out=$("$HARNESS" "$dir" 2>&1 | tail -1)
		local nb diff
		nb=$(echo "$out" | sed -n 's/.*frame: \([0-9]*\) non-blank.*/\1/p')
		diff=$(echo "$out" | sed -n 's/.*(MAME), \([0-9]*\) differing.*/\1/p')
		if [ "${diff:-x}" = "0" ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
		printf '| %-38s | %-14s | %4s | %8s | %6s |\n' "$label" "$cap" "$F" "$nb" "${diff:-ERR}"
		label=''
	done
}
printf '| %-38s | %-14s | %4s | %8s | %6s |\n' "gate item" "capture" "F" "nonblank" "diff"
printf '|%s|%s|%s|%s|%s|\n' "----------------------------------------" "----------------" "-----:" "---------:" "-------:"
run "a 16x16-tile scene"                 avspirit_demo  22 242 302
run "an 8x8-tile scene"                  edf_pages      5 55 105
run "a non-default page layout (N=2)"    edf_pages      13 111 193
run "a non-default page layout (N=3)"    hayaosi1_pages 5 55 130
run "3 layers + sprites over and under"  bigstrik_split 157 200 240
run "a sprite-split scene (bit 8)"       bigstrik_split 180 220
run "a flipped frame"                    avspirit_flip  5 55 105
run "mode C"                             64street_demo  34 154 184
run "sprites, no split (bit 8 clear)"    avspirit_demo  242 302
run "mode D (2 layers, inverted)"        peekaboo_demo  34 154 214
echo
echo "pass $pass, fail $fail"
[ "$fail" -eq 0 ]
