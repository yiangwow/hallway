#!/usr/bin/env bash
# Launch the hallway in the Windows Godot 4.5 build from WSL.
# Extra args pass through, e.g.  ./run.sh -- --shot=test --ascii=1
#
# T126 (owner, mid-game): a harness window must NEVER come to the front. Godot
# reads override.cfg at startup, before any script, so no_focus is set from the
# very first frame; the window is also parked off to the right. Both are written
# here and removed again on exit, so playing from source is untouched. Only the
# harness uses this script - the owner plays the exported exe.
G=/mnt/c/Users/computer/Tools/Godot_v4.5-stable_mono_win64/Godot_v4.5-stable_mono_win64_console.exe
P="$(cd "$(dirname "$0")" && pwd)"
cleanup() { rm -f "$P/override.cfg"; }
trap cleanup EXIT INT TERM
# never during an export or a headless run: an override.cfg sitting in the project
# at export time would be packed into the shipped game and the PLAYER's window would
# refuse focus. Headless has no window to steal anyway.
case " $* " in
  *--export*|*--headless*) : ;;
  *) printf '[display]\n\nwindow/size/no_focus=true\n' > "$P/override.cfg" ;;
esac
"$G" --path "//wsl.localhost/$WSL_DISTRO_NAME/home/unix/hallway" --position 6000,4000 "$@"
code=$?
cleanup
exit $code
