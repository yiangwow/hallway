# ADR

## 001 — Godot 4.5, scene built in code, ASCII as a post-process

- **Date:** 2026-09-02
- **Status:** Accepted
- **Context:** A walkable enclosed hallway with two identical skylit rooms, lit by real light physics, viewable either as proper graphics or as ASCII. Godot 4.5 (Windows, mono) already exists at `C:\Users\computer\Tools`; Unity would need Hub + login + a Windows-side project.
- **Decision:** Godot 4.5, Forward+ renderer. Geometry is generated in `main.gd` from a few metre constants rather than authored in the editor, so the layout is reviewable as text and regenerable. Lighting is a `DirectionalLight3D` sun with shadows plus SDFGI for bounce and thin volumetric fog so shafts are visible. The ASCII look is a `CanvasLayer` screen shader that quantises the *finished* frame into 8×16 cells and stamps a glyph by measured luminance — it never invents shading. "Windows at the top" are read as square skylights so both rooms stay identical under one sun. All albedo and the sky are greyscale.
- **Consequences:** No editor-authored scene to maintain; layout changes are constant edits. SDFGI is Forward+-only (no Compatibility renderer). The project lives on the WSL filesystem and is run by the Windows binary through `//wsl.localhost/...` — `run.sh` encodes this. Screenshot verification uses `--shot=NAME` user args and briefly opens a window on the Windows desktop.

## 002 — The thing lives in the light; shade is always safe

- **Date:** 2026-09-03
- **Status:** Accepted
- **Context:** A hunter the player cannot reason about is a jumpscare machine. The building is a test house whose only variable is light: a sun through skylights, shutters, sheets, a lamp. The ASCII reading quantises real light and nothing else.
- **Decision:** The thing's seat is always a lit patch (sun through an open pane, or the lamp's disc edge). It harms only while the player stands in *its* light; shade is refuge, always, without exception. Chores are the player's only verb — MOVE THE LIGHT — and every chore removes light, so the job itself tightens the rule. The sun steps down with chores done and with wall-time (`Game.step_for`), and never returns.
- **Consequences:** The rule is statable after one death ("it is where the light is; stay out of the light"). No chase, no stinger, no meter. Tension comes from chores that force a crossing through lit patches. Level design must keep at least one shaded route to every interactable, or death is unfair.
