# REF - read whole every tick; the loop never writes here. Views, args, specs, IDs.
Views: V1 hall `--pos=0,0.95,10 --yaw=0 --pitch=-5`; V2 doorA `--pos=-2.4,0.95,0 --yaw=90`; V3 gridA `--pos=-4,0.95,0 --yaw=90 --pitch=-30`; V4 doorB `--pos=2.4,0.95,0 --yaw=-90`; V5 roomB `--pos=6.3,0.95,3.5 --yaw=0` (the -Z wall and floor: where B's seats land from step 2; mirror of the sun-table view); V6 doorB-left `--pos=2.4,0.95,0 --yaw=0` (gate M2: the first sight - B r2c0's wall seat at x 1.8 is 0.6 m left and 2.6 m ahead; M3 verifies here with `--chores=2`); office `--pos=-1.5,0.95,15.8 --yaw=-45 --pitch=-20` (loop, M2.0e: clear of the furniture). V2/V4 look into the rooms; the hall-side wall is behind the camera.
Shot: `tools/shot.sh NAME --ascii=1 <view> [--sun=N --chores=N (before the settle) --step_at=N --lamp=1 --press=ACTION (after it, at t=0) --shut=A:bits,B:bits --thing=x,y,z --seed=N --t=SEC --res=WxH --settle=N --ab=thing --seq=N:DT --walk=SEC]`; the harness applies the camera args, settles 360 frames (loop, measured M1.0a), applies the t=0 args, steps the clock 1/60 per frame to `--t`, captures; SHOT lines carry `step=` and `pos=` (`--ab=thing`: NAME_off.png then NAME_on.png on consecutive frames). Tests: `tools/test.sh` (headless tests/run.gd, `TEST name PASS|FAIL`). Sims: `tools/sim.sh NAME` -> `SIM NAME PASS|FAIL`. Both `timeout 120`; exit 1 on FAIL, `^ERROR`, `SCRIPT ERROR`.
Tools: `tools/cells.py A.png [B.png]` re-quantises into 8x16 ramp cells (partial last row dropped), prints a 3x3 mean grid; with B: % cells changed, % changed by > 1 ramp step, bbox; `--outside=cx,cy,r` splits inside/outside (+16 px). `tools/cells.py --sheet OUT.png A B ...` tiles <= 8 PNGs into one (PIL 12.1 installed).
Cross-run noise (measured 2026-09-02): ~0.1-0.15% of cells; tolerances: <= 0.3% changed, none by > 1 step = "same"; A/B outside the aura <= 0.2%.

## Specs (numbers the rules refer to)
Sun: rotation (elev, 28, 0); light travels toward -X,-Z; a pane's patch lands 6/tan(elev) m downstream (step 0: 3.2 m, 1: 4.7, 2: 6.7, 3: 9.6, 4: 14.9): on the -Z/far walls from step 2, above head height from step 4. Reachable pane = its beam passes below y 1.7 inside the room.
`pick_seat(sun_step, shut: 18 bits, lamp_on, player_pos) -> {room, pane, surface: floor|wall|lamp} | null`; `in_beam(p, pane, sun_step) -> bool`: p pushed back along the sun ray to y=6 lands inside the pane; player = any point of the capsule (feet to 1.7). Tie among reachable panes: nearest the player's position; hall/office/plant => the room of the last chore.
Negative omni (M3.0k, measured V6): seat centre +0.6 m along the normal, shadowed, fog 0, range 1.1, attenuation 2, energy 4: a 0.92 m disc, patch core ` `, nothing by > 1 step outside the patch box or on the floor.
Breathing: over-gained `exposure_multiplier` loop, period >= 2 s, amplitude 0.05 x proximity (< 6 m) + 0.15 x dose. Bounce lag (loop, measured M2.0e, V3, sun 1 -> step_at 2): direct light moves on the first frame (hold ~0); the frame keeps changing until ~4-6 s (s3 vs s6 ~350 cells, s6 == s10) - drain ~250-350 frames, not ~100. HYSTERESIS: the state reached by stepping 1->2 in play is ~0.3 glyph levels brighter everywhere than a cold boot at step 2 (`--sun=2`), exposure identical; both are stable. The player only ever steps, so post-step looks are verified with `--sun=N-1 --step_at=N --t=6`; `--sun=N` is the cold-boot state.
Aura: `thing_r` = projected 1.2 m radius; swirl <= 0.55 rad, pull <= 0.30, coarsen <= 2x; `thing_on` ramps 0<->1 over >= 2 s, schedule = pure function of `t` and `--seed`, duty 70-90%; screen position lags 0.3 s; `hue_mix` 0..1 tints glyphs toward the hue (M5.4).
Hue (Q4 default): pale violet, Color(0.72, 0.58, 0.92); the omni takes it at `hue_mix` > 0; never red.
Lamp: SpotLight3D on cam, shadowed, 22 deg, e~3; riding seat 2 m ahead, 1.2 m left (the rim, T79). Sun table (M1.4): 0 (-62) e2.2; 1 -52; 2 -42; 3 -32; 4 -22 e1.6; 5 -12 e1.0 (under Q1b: -12 only at End A).

## Spaces and beats
Hall 3x24 as built; A x<0; B x>0; office +Z end; plant room -Z end. Pane rows r0 (-z), r1, r2 (+z), 3 panes each = 18. Sun steps 0-5.
Beats (min): 0-3 normal (C1, Tab is the meter); 3-6 wrongness (C2; a dark pool on a B patch, no caster); 6-10 the rule (C3: cranks in its light; first death); 10-14 pressure (C4 lamp; C5 in A with it riding); 14-18 riding (C6, C7); 18-20 ending.
C1 Read meters: plaque A (ASCII on, E), plaque B, log entry at the desk (E 3 s). Sun 0->1.
C2 Sheets over A's 3 racks (E 2 s each; fast = one change). Sun 1->2. Thing spawns after.
C3 Close B's 3 shutter rows (crank E 3 s each; each crank stands in its row's step-2 light). Sun 2->3.
C4 Take the lamp (hook by the plant-room door), drain the boiler (E 8 s, dark). Sun 3->4.
C5 Close A's 3 rows with it in A (riding if the lamp is on). Sun 4->5. All shut -> riding.
C6 Sample card, A's centre rack (E 3 s). Reveals D4.
C7 Hang the lamp on the desk hook, sign the log (E 6 s). Enables the bolt.
D1 Log: monthly lux delivered / lux read, thirty years, the gap rising. Numbers only.
D2 Note on the plant-room door: "shutters stick - do B in the morning".
D3 B's floor: a second unfaded rectangle where a rack once stood.
D4 Under the sample card: a dark unfaded rectangle, the only dark thing on the rack.
D5 Office chair: sun side albedo 0.9, shadow side 0.3.
D6 A's floor: faint burned 3x3 grid offset from the live grid, one person-shaped absence.
End A: lamp off, walk to the keyhole, bolt 4 s in the dark; the door opens on dusk: 3 s read in ` .:-`, then ` ` (no light). Credits = the clipboard.
End B: bolt held with the lamp on -> bleached at the door; pale decal on the yard door; no restart; credits.

## Owner questions (answer in Feedback at the M1.5 gate; defaults stand if silent)
Q1 Seat on any surface, floor or wall (default) - or floor only with a shallower table (-62/-58/-54/-50/-46, -12 at End A)?
Q2 Wall-time sun step every 3 min (default on) - or chores only?
Q3 RESOLVED 2026-09-02 by the owner: the gaunt faceted drape (trial5), directed by him over five iterations.
Q4 Hue: pale violet (default) - or another single non-red hue?
