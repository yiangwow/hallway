#!/usr/bin/env bash
# Every sim in one command (M7.0e): reads tests/SIMS.md - the generated index of
# cases and their args - runs each with tools/sim.sh, prints its SIM line, and ends
# with `SIMS n/N PASS` or `SIMS n/N FAIL: name name ...`. Exit 1 if any case failed.
# One engine at a time on purpose: two Godot runs at once starve each other and read
# as failures (T120). SIM_TIMEOUT defaults to 240 here - the route needs ~90 s.
#   tools/sims.sh            every case
#   tools/sims.sh route ride  only cases whose name contains one of these
cd "$(dirname "$0")/.." || exit 1
export SIM_TIMEOUT="${SIM_TIMEOUT:-240}"
mapfile -t rows < <(python3 - "$@" <<'PY'
import re, sys
want = sys.argv[1:]
for line in open('tests/SIMS.md'):
    m = re.match(r'^\|\s*([A-Za-z0-9_]+)\s*\|\s*(.*?)\s*\|\s*$', line)
    if not m or m.group(1) == 'sim':
        continue
    name, args = m.group(1), m.group(2).strip('`')
    args = re.sub(r'\([^)]*\)', '', args).strip()       # drop notes like (SIM_TIMEOUT=240) and (none)
    if want and not any(w in name for w in want):
        continue
    print("%s\t%s" % (name, args))
PY
)
pass=0; fail=0; failed=""
for row in "${rows[@]}"; do
  name="${row%%$'\t'*}"; args="${row#*$'\t'}"
  out=$(tools/sim.sh "$name" $args 2>&1 | grep -E "^SIM " | tail -1)
  [ -z "$out" ] && out="SIM $name FAIL no line"
  echo "$out" | cut -c1-140
  case "$out" in *" PASS"*) pass=$((pass+1));; *) fail=$((fail+1)); failed="$failed $name";; esac
done
total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "SIMS $pass/$total PASS"; exit 0; fi
echo "SIMS $pass/$total FAIL:$failed"; exit 1
