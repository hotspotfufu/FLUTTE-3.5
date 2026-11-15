# Development Log — Panda Adventure

## Stage 1 — Project structure and bamboo forest environment
**Date:** 2026-11-14   **Status:** built and statically validated; waiting for an in-engine test on your machine

### Environment check
- Target engine: Godot 4.7.2 stable (a maintenance release on the 4.7 line, no known incompatibilities with 4.7.x).
- The build workspace **has no Godot binary**, and engine downloads are blocked there. Because of that,
  the project has **not yet been launched in Godot**. Every script uses only long-standing Godot 4 APIs
  (available since 4.0–4.2 and unchanged in 4.7) to keep that risk low.
- Checks run instead:
  - `tools/validate_project.py`: all resource paths, resource ids, node parents and exported node paths
    resolve. No Godot 3 syntax. Tab-only indentation. Balanced brackets. No duplicate scripts. → **PASS**
  - Validator self-test: four planted errors (Godot 3 `onready`, space indent, missing texture,
    broken node path) were all caught.
  - Camera framing checked with a 2D layout sketch using the same camera maths. As a result, the
    foreground flowers were moved forward so they no longer hide the panda's feet.

### Artwork inspected
- `panda_reference_sheet.png` (1824×862): front, side and back views of a red panda with a conical
  straw hat, red braided band and tassels, orange cord, red gem pendant, rope sash and bamboo stick.
- `main_menu_reference.png` (1672×941): the "FLUTTE" title screen. The Start Game, Settings and Quit
  buttons are painted into the image.
- Produced from them: `panda_side.png` (transparent cut-out of the side view), `icon.png` (front-view face).

### Files created
- `project.godot`, `icon.png`, `.gitignore`, `README.md`, `DEVLOG.md`
- `Assets/Characters/Panda/panda_reference_sheet.png`, `panda_side.png`
- `Assets/UI/main_menu_reference.png`, `Assets/Effects/petal.png`
- `Assets/Materials/foliage_sway.gdshader`, `sky_backdrop.gdshader`
- `Scenes/Levels/Level01_BambooForest.tscn`, `Scenes/Environments/BambooPlatform.tscn`
- `Scripts/Environments/bamboo_forest_builder.gd`, `day_night_controller.gd`,
  `bamboo_platform.gd`, `stage1_preview_camera.gd`
- `tools/validate_project.py`
- Empty folders for later stages

### Known limitations (by design for Stage 1)
- The panda is a static image used to check scale. It has no movement or animation yet.
- The foreground bamboo can briefly cover the panda when he walks behind it.
  Stage 11 will fade it when it overlaps the player.
- The scenery is generated when the level loads, so the editor viewport shows only ground, platforms,
  camera and panda. Press F5 to see the full forest.
- No audio yet.

### Open questions for Stage 2
1. **Animation frames.** The reference sheet has 3 still poses. For the 15 required animations, choose one:
   (a) you supply frame sheets, or (b) I build a cut-out rig: body, head, hat, arm, tail and bamboo
   pieces cut from your art and animated in Godot. Option (b) is smooth and works now. Option (a)
   looks more hand-drawn.
2. **Game title.** The menu art says "FLUTTE". Should that be the game's name?

---

## Web build + GitHub Actions
**Date:** 2026-11-15   **Status:** prepared and statically validated; first real run happens on GitHub

### Why the editor crashed
Godot opened the project but showed a blank "Alert!" box. That points to the laptop's graphics
driver not handling the Mobile (Vulkan/Direct3D 12) renderer. Godot's Web export only supports the
**Compatibility** (OpenGL / WebGL 2) renderer anyway, so the project now uses it everywhere.

### Changes (nothing rebuilt; Stage 1 content preserved)
- `project.godot`: renderer → `gl_compatibility` (PC, mobile and Web); app name → FLUTTE;
  mouse can act as touch so drag controls work with a mouse too.
- `Scripts/Environments/stage1_preview_camera.gd`: drag to pan on touch screens.
- `Scripts/Environments/day_night_controller.gd`: double-tap toggles day/night.
- `Scenes/Levels/Level01_BambooForest.tscn`: hint text mentions the touch controls.
- New `export_presets.cfg`: "Web" preset. Threads off so it runs on itch.io and iPhone Safari
  without special server headers. Both desktop and mobile (ETC2/ASTC) texture compression on.
- New `tools/ci_verify.gd`: loads every script, shader and scene headlessly. It fails with the file
  name, and Godot prints the line number of any parse error just above it.
- New `.github/workflows/build-web.yml`: installs Godot 4.7.2 and its export templates, imports,
  verifies, runs the scene, renders frames with software OpenGL (catches shader errors and saves a
  screenshot), then exports and uploads the Web build. On any error the export is skipped, and the
  run summary lists the exact file, line and message.

### Tested here
- `tools/validate_project.py` → PASS.
- The workflow's "restore folder layout" step, run on a flattened copy (like the GitHub repo):
  every file landed in the right folder → PASS. It also removes stale loose duplicates.
- The error-report step, fed a fake parse error: it reported `bamboo_platform.gd` line 21,
  stopped the build, and skipped the export, as intended.
- Godot itself has **not** run here (no Godot binary in this workspace). The first real
  import, compile and export happens on GitHub's machine.
