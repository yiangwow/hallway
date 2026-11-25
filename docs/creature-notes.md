# Creature + design decisions from the 2026-09-02 conversation (to merge into ~/hallway/docs/ when the guardrails workflow lands)

## Owner's brief, in his words
- short horror story game; doing chores and discovering things; something hunts you all the while
- the hunter is an ASCII monster that manipulates the ASCII around it; it fucks with the lighting; lighting is very important
- "the creature introduces colour that expands" = the VOCABULARY expands: the player thinks the world is white ASCII; eventually, as a surprise, the creature can introduce colour. Not area-spread.
- "one of them is black too, to make things invisible"
- posture: SAGGING — showed a reference (armoured winged figure sitting hunched, cloak pooling, arm hanging in front). Then: "do you see how his hand is hanging at the front" / "it's more animalistic". Read: ape at rest — weight on the haunches, back higher than the head, head low and forward, one long arm hanging straight down from the front of the shoulder, hand heavy, knuckles near the floor, fingers loose.

## Three powers, in order (subtract → erase → add)
1. DIM (early): kills lights / starves bounce (DirectionalLight3D.light_energy, per-room OmniLight3D, SDFGI reacts with delay). Reading: glyphs thin out, ' ' spreads. Player: keep lights on — which the chores undo.
2. BLACK (mid): absorbs; its body reflects nothing (unshaded black material) → a HOLE in the characters; can blacken objects/doorways/walls (they read as nothing; geometry unchanged — trust the building, not the screen). Player: light BEHIND it — the wall's glyphs draw its silhouette. Dimming is its camouflage prep.
3. COLOUR (late): emits one hue (coloured OmniLight3D child); shader passes chroma through — nothing else in the world has any, so coloured glyphs = it, no position uniform. First colour in the game = one word on the player's own checklist. Then a halo around a hole. Ending: colour on the floor at your own feet. It becomes a source; the rule "light reveals it" inverts.
- Open (owner's call): does colour linger as burn-in, or exist only while present? I lean absent.
- Hue: exactly one, never varied, not red. Recommend pale violet. (OWNER) decision.

## Literary devices adopted as RULES
- Geometry never lies; only the reading does. Every lie must be discoverable by walking into it. (unreliable renderer)
- The only text in the building is the player's own checklist. No notes, no logs. The list is the narrative instrument: items crossed out, an item you didn't write, one word in colour. (House of Leaves' one blue word)
- The thing is never rendered with detail: only a hole, or a halo. (absent centre)
- The two identical rooms are a promise; the game breaks it once, with the black power (a doorway one room has and the other doesn't). (the double)
- Chores are verses: same route, same order, each pass one thing differs. (ritual with variation)
- Compliance as dread: "lights off in B" — you do it because it's the job.
- The false rule: light reveals it (taught, mastered), then it becomes light.
- Early on the game refuses to confirm whether a shape in the glyphs is noise or it. (figure in the pattern)
- Nothing explains what the ASCII is. Ever.

## Anti-patterns (refuse)
found notes, audio logs, a name for it, lore dumps, "you were it all along", asylum/cult/dead children, jumpscare stingers, red as its colour, a floating/gliding ghost.

## Silhouette + motion
- At rest: see silhouette.txt. Hump-backed, head low-forward below the shoulder line, hanging arm with a visible GAP of wall glyphs behind it, heavy hand at the floor.
- Motion: knuckle-walk. The arm plants first, the mass drags after. A pendulum arm is its motion signature, readable even as absence.
- Build: procedural mesh (stack of ellipsoids + arm capsule + hand), black unshaded material, vertex shader for slow sag/breathing. No rig, no assets.

## Trial-run direction (owner, 2026-09-02 late)
- "the ascii needs to deform around the creature" / "the creature is generally not too detailed but making the ascii deform around it makes it weird and difficult to grasp" → body simple; the GRID bends around it (screen shader: pull + slow swirl + coarser cells inside a radius fed from main.gd via unproject_position). The deformation must be AROUND it — a stable grid outside is what makes the bend read.
- "more triangles, more droopy. sharp edges and angles, draping clothes" → faceted drape built with SurfaceTool: jagged hem (even points spike + pool on floor, odd points pull in + lift), ridge ring at shoulders, one hump apex, octahedron head, prism arm, wedge hand with finger spikes. No ellipsoids.

## OVERNIGHT POSTURE (owner, 2026-09-02 23:25, leaving for 7-8+ hours) — MERGE INTO GUARDRAILS "Process law" AND STATE.md
His words: "i expect you to do a LOT of work, and i believe you can come up with great and interesting ideas. leave no stone unturned. check if things make sense after implementing, check if design and systems work, if sound can be added etc. make sure the loop keeps going."
Rules derived (these OVERRIDE the softer stop conditions until he is back):
- Owner absent until at least 2026-09-03 ~08:00, possibly ~18:00. Do NOT stop for design forks or for "a guardrail would change": DECIDE, record one line in STATE.md "Decisions taken by the loop", keep going. If a guardrail genuinely must change, amend it, note the amendment in Decisions, continue.
- "Three ticks without a verified commit" = skip the item (mark it "- [~] blocked: why" in ROADMAP.md, add to Deferred), move to the next. It is NOT a stop.
- The ONLY stop: tools/shot.sh cannot produce a non-black image (verification is broken). Then stop and write why at the top of STATE.md.
- Volume: after the merge tick, ticks are 60s apart. Bigger items: dispatch implementation to a sonnet subagent (Agent tool, model sonnet) with the exact file list + verification command; review in the main loop. Per milestone: run a Workflow with adversarial critics (code correctness, design/fear, feasibility) on what was built; fold findings into ROADMAP as items.
- Verification system, build EARLY (first tick after merge): `--walkthrough` arg in main.gd that scripts the player along the chore route and saves a contact sheet (PIL montage in tools/) to shots/walk_<tick>.png; every later tick that touches the world re-runs it and LOOKS at it.
- Sound: procedural only (AudioStreamGenerator / synthesized in GDScript): room tone, the thing = low pulse that rises with proximity, grid warp = detuned tone, footsteps = filtered clicks, the checklist pencil scratch. Each sound also rendered offline to a WAV in /mnt/c/Users/computer/Downloads/hallway-trial/audio/ so he can listen in the morning (I cannot).
- Night log: append one line per tick to ~/hallway/docs/LOG.md (never read whole). Morning reading: STATE.md then LOG.md then Downloads/hallway-trial/.
- Re-export the exe (./run.sh --headless --export-release "Windows Desktop" dist/hallway.exe → copy to Downloads/hallway/) at the end of every milestone so he can play the latest in the morning.
