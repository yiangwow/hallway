# ADR

## 001 — Godot 4.5, scene built in code, ASCII as a post-process

- **Date:** 2026-09-02
- **Status:** Accepted
- **Context:** A walkable enclosed hallway with two identical skylit rooms, lit by real light physics, viewable either as proper graphics or as ASCII. Godot 4.5 (Windows, mono) already exists at `C:\Users\computer\Tools`; Unity would need Hub + login + a Windows-side project.
- **Decision:** Godot 4.5, Forward+ renderer. Geometry is generated in `main.gd` from a few metre constants rather than authored in the editor, so the layout is reviewable as text and regenerable. Lighting is a `DirectionalLight3D` sun with shadows plus SDFGI for bounce and thin volumetric fog so shafts are visible. The ASCII look is a `CanvasLayer` screen shader that quantises the *finished* frame into 8×16 cells and stamps a glyph by measured luminance — it never invents shading. "Windows at the top" are read as square skylights so both rooms stay identical under one sun. All albedo and the sky are greyscale.
- **Consequences:** No editor-authored scene to maintain; layout changes are constant edits. SDFGI is Forward+-only (no Compatibility renderer). The project lives on the WSL filesystem and is run by the Windows binary through `//wsl.localhost/...` — `run.sh` encodes this. Screenshot verification uses `--shot=NAME` user args and briefly opens a window on the Windows desktop.
