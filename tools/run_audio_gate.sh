#!/usr/bin/env bash
# M2 gate (4): band correlation per SOURCE, core against MAME.
#
# Needs, per game:
#   MAME  -- /tmp/mamewav/<game>_{fm,oki1,oki2,mix}.wav, rendered with
#            tools/mame-patches/megasys1-sound-isolation.patch applied and
#            MS1_SND_ISO set. NOTE: -wavwrite with -sound none writes a
#            silent WAV and says nothing, so sound must stay enabled.
#   core  -- /tmp/rtl_<game>_{fm,oki1,oki2,mix}.raw from sim/rtl/ms1_snd
#            with MS1_WAV set.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for g in "$@"; do
  for src in fm oki1 oki2 mix; do
    m=/tmp/mamewav/${g}_${src}.wav
    c=/tmp/rtl_${g}_${src}.raw
    echo "===== $g / $src ====="
    if [ ! -s "$c" ]; then echo "  (core dump missing)"; continue; fi
    python3 tools/audio_compare.py "$m" "$c" --offset-search 2.0 | tail -4
  done
done
