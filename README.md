# FLUTTE — Stage 1

A 2.5D red panda adventure for Godot **4.7.2 stable** (GDScript, no plugins).
Current state: **Stage 1 — project structure + bamboo forest environment.**
The panda in the scene is a static scale reference only. Movement starts in Stage 2.

## Open and test (about 2 minutes)

1. Unzip the project somewhere permanent (for example `Documents/PandaAdventure`).
2. Open **Godot 4.7.2** → Project Manager → **Import** → select `project.godot`.
3. Wait for the first import to finish. This creates `.godot/` and `.import` files.
4. Press **F5** (Run Project).

### What you should see
- A pink sky with a soft sun, lavender and green hills, pink blossom trees,
  three layers of swaying bamboo, pink flower bushes, a sandy path and wooden platforms.
- Pink petals drifting down and to the left.
- Your red panda standing on the path at the left.
- A hint in the top-left corner.

### Controls (preview only)
| Key | Action |
|---|---|
| ← / → or A / D | Pan the camera along the level (distant layers move slower) |
| N | Smoothly switch between day and night (lanterns light up at night) |

### Stage 1 test checklist
Please report the result of each line:
- [ ] Project imports with **no red errors** in the Output panel
- [ ] F5 runs; window opens at 1280×720 in landscape
- [ ] Bamboo and flowers sway gently; petals fall
- [ ] Panning shows parallax (hills move slower than bamboo)
- [ ] N toggles day ⇄ night without errors
- [ ] Shadows from bamboo and the panda appear on the ground
- [ ] **Debugger → Errors** tab is empty after 30 s of play

Optional command-line import check (replace `godot` with the path to your Godot 4.7.2 executable):
```
godot --headless --path . --editor --quit
```
This should finish without `ERROR:` lines.

Optional static check (needs Python 3; does not need Godot):
```
python3 tools/validate_project.py
```

## Project layout
```
project.godot                 Engine settings (Mobile renderer, landscape, 1920×1080 base)
icon.png                      App icon (made from your panda artwork)
Assets/
  Characters/Panda/           panda_reference_sheet.png (original), panda_side.png (cut-out)
  UI/                         main_menu_reference.png (your menu art, used in a later stage)
  Effects/                    petal.png
  Materials/                  foliage_sway.gdshader, sky_backdrop.gdshader
  Audio/ Enemies/ Bosses/ Environments/   (empty, for later stages)
Scenes/
  Levels/Level01_BambooForest.tscn        Main scene for now
  Environments/BambooPlatform.tscn        Reusable platform (set `width` per instance)
  Characters/ Enemies/ Bosses/ UI/ Effects/  (empty, for later stages)
Scripts/
  Environments/bamboo_forest_builder.gd   Builds scenery layers (MultiMesh = few draw calls)
  Environments/day_night_controller.gd    Day/night blend
  Environments/bamboo_platform.gd         Platform sizing
  Environments/stage1_preview_camera.gd   Stage 1 pan camera (replaced in Stage 2)
  Core/ Characters/ Enemies/ Bosses/ UI/ Effects/  (empty, for later stages)
tools/validate_project.py     Static checker
DEVLOG.md                     Development log
```

## Technical choices
- **3D physics only.** Ground and platforms are `StaticBody3D`. The gameplay plane is z = 0.
- **Orthographic camera** at size 12, tilted 7° down so the ground reads as a 3D strip.
  An orthographic camera has no natural parallax, so each scenery layer is offset by
  camera x × (1 − parallax). That is cheap and works on every platform.
- **Mobile renderer** for PC, Android and iOS. No SSAO, SSR, volumetric fog or SDFGI.
  There is one shadowed directional light, and the lantern lights are unshadowed.
- **Scenery** is placed at runtime from a fixed random seed, so the level looks the same
  every time. It is decorative only. All collision lives in the level scene.
- Physics layers are named in Project Settings: World, Player, Enemies, Collectibles,
  PlayerAttack, EnemyAttack.

## Web build (no editor needed)
Every push to GitHub runs **Actions → Build FLUTTE (Web)**. Open the run and scroll to **Artifacts**:
- **FLUTTE-web**: the playable build. This ZIP is ready for itch.io, with `index.html` at the top level.
- **screenshot**: a frame rendered by the build machine.
- **build-logs**: the full Godot output.

If anything is wrong, the run fails before exporting, and its **Summary** page lists the file, line and error.

itch.io upload: Create new project → Kind of project: **HTML** → upload the FLUTTE-web ZIP →
tick **This file will be played in the browser** → viewport 1280×720 → tick **Mobile friendly**,
orientation **Landscape** → leave **SharedArrayBuffer support** off → Save.
