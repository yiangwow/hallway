# hallway

Walkable enclosed hallway + two identical skylit rooms in Godot 4.5, real lighting, toggleable ASCII post-process.

## Files
- `project.godot` — Forward+, 1600×900, main scene `main.tscn`
- `main.tscn` — one `Node3D` with `main.gd`; everything else is built in code
- `main.gd` — geometry constants (metres), materials, sun + SDFGI environment, player spawn, ASCII layer, HUD, `--shot` harness
- `player.gd` — `CharacterBody3D` first-person: WASD, mouse, Shift run, Esc mouse toggle
- `creature.gd` — the thing at rest: faceted drape built with SurfaceTool (jagged hem, ridge ring, hump apex), octahedron head, prism arm, wedge hand; unshaded black (reads as ' ' in ASCII); breathing sag + pendulum arm; local +X is its front. Trial placement in `main.gd::_creature()` — left room, turned -0.55 rad
- ASCII warp: `main.gd::_process` feeds `thing_px` / `thing_r` / `thing_on` (screen-space centre, radius, visibility) to the shader every frame; the shader pulls, swirls and coarsens the grid inside that radius
- `ascii/ascii.gdshader` — screen-space cell quantiser; `ascii/atlas.png` — 10 glyphs × 8×16 px, ramp ` .:-=+*#%@` (regenerate with PIL, DejaVu Sans Mono 14)
- `run.sh` — launches the Windows Godot binary against this WSL path
- `export_presets.cfg` — Windows Desktop preset, embedded pck, x86_64, → `dist/hallway.exe`
- `tools/README-friend.txt` — the note that ships next to the exe
- `shots/` — screenshot output (git-ignored)

## Run
```
./run.sh                                   # play
./run.sh -- --pos=-2.4,0.95,0 --yaw=90 --ascii=1   # play, starting at the left doorway facing the thing (any of --pos/--yaw/--pitch/--ascii work without --shot)
./run.sh --headless --import               # (re)import resources after adding assets
./run.sh -- --shot=NAME --ascii=1 --pos=0,0.95,10 --yaw=0 --pitch=-5   # screenshot to shots/NAME.png
```

## Ship
```
./run.sh --headless --export-release "Windows Desktop" dist/hallway.exe   # ~93 MB, templates in %APPDATA%\Godot\export_templates\4.5.stable.mono
cp dist/hallway.exe tools/README-friend.txt /mnt/c/Users/computer/Downloads/hallway/ && zip
```
A .exe on the WSL filesystem won't launch through interop (exit 126) — copy to a Windows path first. In the exe `--shot` writes to `user://` (`%APPDATA%\Godot\app_userdata\hallway\`).
Controls: WASD, mouse look, Shift run, Esc free mouse, **Tab** ASCII ⇄ graphics.

## Layout (Y up, hallway along Z)
Hallway 3 × 24 × 3.2 inner, walls 0.3, dead ends. Doorway 1.6 × 2.4 at z≈0 each side. Rooms 9 × 9 × 6 inner, centred at x = ±6.3. Skylight 6 × 6 with 3×3 mullions. Sun at (-62°, 28°, 0).

## Rules
- Geometry stays in code; do not add an editor-authored scene alongside it.
- Everything greyscale — no coloured albedo, no coloured sky.
- Verify visually with `--shot` before claiming a lighting change works.
