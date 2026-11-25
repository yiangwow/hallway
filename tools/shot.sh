#!/usr/bin/env bash
# usage: tools/shot.sh NAME [--ascii=0|1] [--pos=x,y,z] [--yaw=deg] [--pitch=deg] [--t=SEC] [--seq=N:DT] ...
# SHOT lines carry step= exp= pos= SEAT aura=px,py,r,on wall= fps= (M3.0a); the
# in-engine watchdog is frame-based (settle + 60 x (t + 30))
cd "$(dirname "$0")/.." || exit 1
out=$(timeout 120 ./run.sh -- --shot="$1" "${@:2}" 2>&1); code=$?
echo "$out" | grep -E '^ARGS|^SHOT|SCRIPT ERROR|^ERROR: [^.]'
[ $code -eq 124 ] && { echo "SHOT $1 FAIL timeout"; exit 1; }
echo "$out" | grep -qE 'SCRIPT ERROR|^ERROR: [^.]' && exit 1   # an engine error is a broken instrument (M5.0k)
echo "$out" | grep -qE '^SHOT .* OK' || { echo "SHOT $1 FAIL no SHOT line"; exit 1; }
# --seq=N:DT -> tile NAME_0..N-1 into shots/NAME_seq.png (one PNG read covers the motion)
for a in "${@:2}"; do case "$a" in --seq=*) n="${a#--seq=}"; n="${n%%:*}"; files=(); for ((i=0;i<n;i++)); do files+=("shots/$1_$i.png"); done; python3 tools/cells.py --sheet "shots/$1_seq.png" "${files[@]}" && echo "SHEET shots/$1_seq.png";; esac; done
exit 0
