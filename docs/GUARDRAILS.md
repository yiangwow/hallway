# GUARDRAILS - read whole every tick. Rules, not prose. Caps in bytes. Numbers: REF Specs.

## 1. What
LIGHTFAST: 15-20 min first-person horror; the last caretaker closes a test house by clipboard while something sits in the sun. Godot 4.5, greyscale, ASCII on Tab.

## 2. Pillars
1. Light is real light; ASCII only quantises it (an invented cell = screensaver).
2. The building is the clock: chores and wall-time step the sun; light never returns (a timer is UI).
3. One thing, one rule, told by the floor (statable after one death).
4. Small and finished: 5 spaces, 7 chores, 6 discoveries, 2 endings, no new systems.
5. Its vocabulary grows in order: DIM (C2) -> BLACK (M3) -> COLOUR (after C5). Each is a surprise once.

## 3. The thing - "the Shortfall"
Fiction: light delivered but never read; thirty years of exposure spent at once on whatever it stands against. Never explained in-game.
1. Seat = the lit patch of one of the 18 A/B panes, floor or wall (office pane, keyhole: never), by `pick_seat` (pure, tested): reachable open pane nearest the player, else the lamp disc edge if on, else any open pane, else none. Its light = its pane's beam (`in_beam`, any capsule point) or the lamp disc while riding. Shade is always safe (ADR-002). Body on the floor under the patch.
2. DIM: a negative shadowed `OmniLight3D` eats part of its patch, a hole with no caster; kept through a death (the floor says that patch kills). After C4 it may sit on an interactable: the crank reads ` ` and still works by feel (geometry never lies, only the reading).
3. Eyes fail near it: auto-exposure OFF; `exposure(zone)`, ramps >= 2 s; within 6 m it is felt (<= 5%); in its light it breathes with dose (period >= 2 s).
4. Bounce lag is real (M2.2 measures it); never fake or fight it; the lamp's trail is expected.
5. Riding = the disc edge 2 m ahead, the one seat allowed in view: no cut; aura and body ramp in over >= 2 s; it knuckle-walks (arm plants, mass drags, >= 2 s a step).
6. BLACK: body = the gaunt faceted drape in creature.gd as the owner directed it (hump, low head, one arm hung to a clawed hand) - black unshaded, layer 2, only while ASCII is on (`set_ascii()`), no shadow, never more detail. In ASCII it is a hole (` `) whose edge is the lit wall behind it.
7. Aura inside `thing_r`: the grid pulls in, coarsens <= 2x and swirls <= 0.55 rad (owner-approved 2026-09-02 on trial5 shots); the rest of the frame is a stable grid; every cell shows real pixels; `--ab=thing` proves nothing changes outside r.
8. Uniforms `thing_px, thing_r, thing_on, t, hue_mix` only; `t` = game clock (fixed-step under `--shot`/`--sim`). `thing_on` = 0 when the cam->centre ray hits geometry or the centre leaves the frustum; ramps 0<->1 over >= 2 s as a pure function of `t` and `--seed`; position lags.
9. Absent until C2. Then rest -> light change (shutter, sheet, lamp, sun step; within 1 s = one) -> re-pick -> cut (teleport) only while origin and destination are both unseen (out of frustum or occluded), else wait: stare and it never moves; nothing ever hides a cut.
10. Sun step = max(chores done, 3-min periods), told only by light. Dose: in its light (its pane open) +0.5/s (riding, still, lamp lit +0.33/s; moving -0.25/s), outside -0.25/s; at 3.0 bleach: exposure to max and a flood from the eye over 1 s (all `@` but the body; hue: 3.14), frozen 2 s, blank, pale Decal (they accumulate); restart at hall z=0 facing the room of the chore in progress (the last chore's room when all are done), lamp as it was, world unchanged.
11. Player verb: MOVE THE LIGHT (cranks, sheets, lamp: take, hang, off); shade is refuge. Tab reads, never acts: graphics shows the bite, ASCII the body.
12. After C2 every chore has an interactable in an open pane's beam at its step, or needs the lamp (`TEST forced_crossing`).
13. Text: clipboard (the only text that changes), prompts <= 3 words, found text <= 25 words on layer 11 while E is held, start line, credits; never about the thing, the rule or the player's state; no Label3D.
14. COLOUR: one hue (REF Q4, default pale violet), never varied, never red, nowhere else in the game. Order: (a) after C5 one word on the clipboard takes the hue; (b) while riding the aura tints (`hue_mix`) - colour bleeding round a doorway before any shape; (c) the bleach is the hue, not white: the floor at your own feet. Never before C5. Gate: 5 done AND the clipboard shown since (`colour_unlocked`); omni colour (1 - hue) at hue_mix > 0. Under the hue: eyes at base, flood 6%, both to white over the hold.
15. Symmetry: A and B identical, a promise broken exactly once (D3).
16. Never: jumpscare, stinger, chase, a face, death without the breathing tell, entering shade, a second thing, a meter on screen.

## 4. Scope
IN: hall (constants fixed; end-wall doorways 1.0x2.4 and wall props allowed), rooms A (x<0), B (x>0), office (+Z, 4x4, 1x1 pane), plant room (-Z, 4x5, keyhole yard door); props = primitives.
OUT: more rooms, inventory, Tab cost, save file, navmesh, combat, markers, colour beyond 3.14, music, voice, files from outside the repo (SystemFont Consolas allowed).

## 5. Visual & audio law
- Greyscale everywhere but 3.14. No store/web assets: primitives, `SurfaceTool`, runtime decals, synthesized audio, the PIL atlas.
- Owner-only constants: cell 8x16, ramp ` .:-=+*#%@`, gamma 1.5, atlas, hall constants, `sdfgi_*`, `scaling_3d_scale`.
- Audio: footsteps, one sub-drone with the breath (gain from dose, attack 2 s, release tau 2.8 s - no edge to pace out), crank/valve/lamp clicks, the clipboard pencil, else silence. Every sound is also rendered to a WAV in Downloads/hallway-trial/audio/ (headless cannot hear; the owner can).
- All light via `lighting.gd`. No light period in the 10-100 frame band; cuts instant, ramps >= 2 s (3.10 bleach: 1 s); <= 2 shadowed positional lights.

## 6. Process law (OVERNIGHT: owner away until 2026-09-03 08:00 or later; volume and ideas expected; the loop does not stop for decisions)
- One tick = one ROADMAP item = one commit on `loop/e2e`; no commit, no tick. Feedback non-empty => it IS the tick: copy it verbatim to LOG.md, act, clear.
- Item = `awk '/^- \[ \]/{print NR": "$0; exit}' docs/ROADMAP.md` (grep is hooked). Not a `- [ ]` line => broken instrument. Never read ROADMAP whole; REF.md whole.
- `(OWNER)` item => take the stated default, log `awaiting owner: ID (default taken)`, tick it `- [d]`, continue. Fork => decide, log, continue. A guardrail must change => amend it, log, continue. Big item (> ~100 lines) => dispatch to a sonnet Agent with file list + verify command; review here.
- Visual claim => a `tools/shot.sh` PNG LOOKED at this tick (`shots/tNN_item_view_mode.png`; dark: `--t=0.5` and `3`). <= 2 PNG reads per tick; a `cells.py --sheet` (<= 8 shots) is one. Numbers => `cells.py` or a `TEST/SIM name PASS` line whose assertion the item spells out.
- Milestone gate (last item of each M): re-export the exe to Downloads/hallway/, run a Workflow of 3 adversarial critics (correctness, fear, feasibility) on what was built, fold findings into the next M as items, one LOG line "GATE Mx".
- Dirty tree at tick start => commit it as `WIP: aborted tick N`, note in State. Stage by list. Author yiangwow, no AI attribution, no push/remote/reset/amend/force/clean.
- ROADMAP hygiene: a done M = its heading + one `[x]` line <= 300 B; a gate folds <= 14 items of <= 640 B each.
- STATE.md <= 2048 (the /loop paste line lives in docs/LOOP.md): State rewritten whole, last 3 decisions; Decisions/Deferred append to docs/LOG.md (never read). Caps: GUARDRAILS 8192, ROADMAP 16384 (never read whole), REF 6144; `wc -c` each tick.
- 3 ticks on one item without a verified commit => mark it `- [~] blocked: why`, LOG it, next item. STOP only for a broken instrument: no `SHOT` line, `^ERROR`, `timeout`, black PNG, Windows down. Write why in State, ScheduleWakeup stop.

## 7. Anti-patterns
Glyph noise, `ERR0R`, "SYSTEM COMPROMISED"; lore that explains it; found notes that warn; a blank line for your name; sanity meter, vignette, VHS; mannequins, music boxes, whispers; flicker with no rule; "you were the monster"; symmetric rooms kept empty; a signal a tester can pace out; red; a floating ghost.
