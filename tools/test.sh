#!/usr/bin/env bash
# Run tests/run.gd headless. Prints the TEST lines; exit 1 on any FAIL, ERROR or timeout.
# Extra args pass through as user args, e.g.  tools/test.sh --fail=1
cd "$(dirname "$0")/.." || exit 1
out=$(timeout 120 ./run.sh --headless -s tests/run.gd -- "$@" 2>&1); code=$?
echo "$out" | grep -E '^TEST|SCRIPT ERROR|^ERROR: [^.]'
if [ $code -eq 124 ]; then echo "TEST runner FAIL timeout"; exit 1; fi
if echo "$out" | grep -qE 'SCRIPT ERROR|^ERROR: [^.]'; then exit 1; fi
if echo "$out" | grep -qE '^TEST .* FAIL'; then exit 1; fi
if ! echo "$out" | grep -qE '^TEST .* PASS'; then echo "TEST runner FAIL no output"; exit 1; fi
exit 0
