#!/usr/bin/env bash
# usage: tools/shot.sh NAME [--ascii=0|1] [--pos=x,y,z] [--yaw=deg] [--pitch=deg]
cd "$(dirname "$0")/.." || exit 1
timeout 120 ./run.sh -- --shot="$1" "${@:2}" 2>&1 | grep -E '^SHOT|SCRIPT ERROR|^ERROR' | grep -v '\.NET'
