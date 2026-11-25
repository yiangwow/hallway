(the /loop paste line lives in docs/LOOP.md - T80)

## Feedback (owner types here; the loop copies it to LOG.md, acts on it, then clears it)

## State
Tick 128, 2026-09-03 21:20. M7.0f: three endgame/interaction slips closed. (1) Both endings now set creature.rise=1.0 and cf_t0=-1.0 - _process returns once ended, so a bolt held inside colour_first's fade left the body frozen part-risen; SIM endA_unlit rise=1.000. (2) Esc no longer quits: it only frees the mouse, E is the only quit (SIM endA esc_armed=true still_A=true) - a reflex Esc at the credits used to close the game. (3) The sign's box shared a centre with the log's and swallowed the ray, so D1 was unreadable once "sign" was offered; it moves 0.22 m up and c6c7 now sweeps the pitch and reads it at -39.0. Control: with the old y no pitch reads it. 33 TESTs pass, SIMS 12/12 on end/c6c7/ride/bolt.
Next: M7.0g, neither ending ends on the mass.
Blockers: none. Ticks without commit: 0. Last verified shot: t127_off (M7.0f touched no visible geometry - an Interactable is a collision box, no mesh). Owner defaults taken: M1.5, M2.0g, M3.2, M6.0m-bleach, M6.0n; M7.0k next. Open findings: M7.0o (D6's placement).
Last 3 decisions: prove an interaction fix by sweeping the aim, not by guessing one pitch; every fix gets its negative control on the old code; a key that frees the mouse must never also quit.
