#!/usr/bin/env bash
# The scripted route: seven ASCII shots along the caretaker's path, tiled into one
# sheet. usage: tools/walk.sh TAG [extra shot args, e.g. --chores=7 --t=1]
# -> shots/walk_TAG_<view>.png and shots/walk_TAG.png. Re-run after any change
# that touches the world; LOOK at the sheet.
cd "$(dirname "$0")/.." || exit 1
tag="${1:?tag}"; shift
ok=0
tools/shot.sh "walk_${tag}_v1"     --ascii=1 --pos=0,0.95,10   --yaw=0   --pitch=-5  "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_v2"     --ascii=1 --pos=-2.4,0.95,0 --yaw=90              "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_v3"     --ascii=1 --pos=-4,0.95,0   --yaw=90  --pitch=-30 "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_v4"     --ascii=1 --pos=2.4,0.95,0  --yaw=-90             "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_v5"     --ascii=1 --pos=6.3,0.95,3.5  --yaw=0               "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_office" --ascii=1 --pos=-1.5,0.95,15.8 --yaw=-45 --pitch=-20 "$@" | grep -q '^SHOT' && ok=$((ok+1))
tools/shot.sh "walk_${tag}_plant"  --ascii=1 --pos=0,0.95,-11  --yaw=0               "$@" | grep -q '^SHOT' && ok=$((ok+1))
[ "$ok" -eq 7 ] || { echo "WALK $tag FAIL $ok/7 shots"; exit 1; }
flat=0
# plant is dark by design (no skylight; the keyhole is its only light until the lamp, M4.2): exempt from FLAT
for v in v1 v2 v3 v4 v5 office; do
  python3 tools/cells.py --glyph "shots/walk_${tag}_${v}.png" | head -1 | grep -q ' FLAT' && { echo "WALK $tag FLAT tile $v"; flat=1; }
done
[ "$flat" -eq 0 ] || { echo "WALK $tag FAIL flat tile (unconverged or empty frame)"; exit 1; }
python3 tools/cells.py --sheet "shots/walk_${tag}.png" \
  "shots/walk_${tag}_v1.png" "shots/walk_${tag}_v2.png" "shots/walk_${tag}_v3.png" \
  "shots/walk_${tag}_v4.png" "shots/walk_${tag}_v5.png" "shots/walk_${tag}_office.png" "shots/walk_${tag}_plant.png" \
  && echo "WALK $tag OK shots/walk_${tag}.png"
