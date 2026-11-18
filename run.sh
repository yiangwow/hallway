#!/usr/bin/env bash
# Launch the hallway in the Windows Godot 4.5 build from WSL.
# Extra args pass through, e.g.  ./run.sh -- --shot=test --ascii=1
G=/mnt/c/Users/computer/Tools/Godot_v4.5-stable_mono_win64/Godot_v4.5-stable_mono_win64_console.exe
exec "$G" --path "//wsl.localhost/$WSL_DISTRO_NAME/home/unix/hallway" "$@"
