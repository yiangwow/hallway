#!/usr/bin/env bash
# Run one in-engine simulation: tools/sim.sh NAME [--args]  ->  `SIM NAME PASS|FAIL`.
# Windowed (sims may read the frame); exit 1 on FAIL, ERROR or timeout.
cd "$(dirname "$0")/.." || exit 1
name="$1"; shift
out=$(timeout "${SIM_TIMEOUT:-120}" ./run.sh -- --sim="$name" "$@" 2>&1); code=$?   # SIM_TIMEOUT=240 for the long ones (M6.0j)
echo "$out" | grep -E "^SIM|^ARGS|SCRIPT ERROR|^ERROR: [^.]"
if [ $code -eq 124 ]; then echo "SIM $name FAIL timeout"; exit 1; fi
if echo "$out" | grep -qE 'SCRIPT ERROR|^ERROR: [^.]'; then exit 1; fi
echo "$out" | grep -qE "^SIM $name PASS" || exit 1
exit 0
