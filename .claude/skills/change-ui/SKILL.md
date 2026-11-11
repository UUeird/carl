---
name: change-ui
description: "carl's UI/visual checklist. Use whenever you add or change a HUD element, button, panel, label, screen (map picker, pause, victory/defeat), color, font, or on-screen VFX — before calling it done. Sibling of /change-feature (which covers type tables ⇄ wiring ⇄ tests); a UI change that also changes a gameplay concept needs both."
---

The settled visual direction is **"Tabletop War Room"** on the design canvas
(carl-43): <https://claude.ai/artifact/Js1EhvrCpeiHXQDoL8uUEW> — pages *Look &
feel*, *Screens*, *Combat effects*. That canvas is the source of truth for
colors, fonts, layout and element motifs. Read the one board you're building,
not the whole canvas. Implementation is tracked in carl-46 (HUD + map picker),
carl-47 (combat VFX), carl-48 (enemy restyle).

## Before you build

- **New screen or visible redesign not on the canvas?** Draw it there first
  (1440×900 board, beside the existing ones) and get it settled with the user,
  then build.
- **Find where it lives.** The HUD is mostly built in code in
  [td_hud.gd](../../../scripts/td_hud.gd) on top of the `HUD/Root` nodes in
  [td_main.tscn](../../../scenes/td_main.tscn) (and the copy in
  `td_test_map.tscn`); the map picker is [map_picker.gd](../../../scripts/map_picker.gd)
  + `map_picker.tscn`. A HUD change usually needs both scenes to agree.

## If you make X, do Y

| You are making… | Do this |
| --- | --- |
| **A color** | Use the canvas palette (table `#14171C`, panel `#1B1F26`, border `#2C323C`, accent `#F2CF5B`, lives `#FF7B6E`, gold `#F2CF5B`; element and enemy colors on the *Look & feel* page). If a shared palette/Theme already exists, use it; if you're adding the second site for a color, pull it into one shared place rather than another `Color(...)` literal. |
| **Text** | Display: Chakra Petch 600/700. Body and numbers: Inter 500. If the font isn't bundled under `assets/` yet, add it (and its `.import`) in the same change rather than falling back silently. |
| **A button or clickable** | At least **44px** tall/wide (touch target). Normal / hover / pressed / selected states all styled — a `StyleBoxFlat` per state, as the build buttons do. |
| **Anything positioned** | Anchors and containers, never fixed pixel offsets from the top-left — the window uses `canvas_items` stretch with `expand` aspect and HiDPI, so fixed pixels drift at other sizes (the old Maps-button drift). |
| **A full-screen or large `Control`** | `mouse_filter = IGNORE` (2) on non-interactive containers so they don't swallow clicks meant for tower slots in the 3D view, as `HUD/Root` does. |
| **A modal screen** (pause, victory, defeat) | Pause the tree (`get_tree().paused`) and set the screen's `process_mode` to always; Esc closes/opens consistently with the canvas. |
| **A repeating on-screen effect** (hit spark, number, ring) | Pool it and prewarm its material (CLAUDE.md "Adding or replacing assets"); a shared static material, not one per spawn. No per-hit tweens — refresh a timer. |
| **An element-tinted thing** | Physical white pellets; Fire rounded flame glyph, lighter core; Poison acid `#B6F23A`, liquid (drips, gloss); Shock jagged bolt, zig-zag arcs with white core. Neutral grey before an element is chosen. |

## Before you call it done

1. **Look at it headed.** Run windowed (`Godot --path .`) or a `--script`
   helper that saves a PNG (see [test/VISUAL_CHECKLIST.md](../../../test/VISUAL_CHECKLIST.md),
   "How to run it"), and read the screenshot. Check the resting and the
   active state (hovered, selected, open).
2. **Check another window size.** Resize (or set a different viewport size in
   the helper) and confirm nothing overlaps or drifts off-screen.
3. **Compare against the canvas board** you were implementing; call out any
   deliberate divergence in the PR.
4. **Test the behavior**, not just the render: a GUT test for anything with
   logic (a button that changes state, a screen that pauses), then
   `./run_tests.sh`.
5. **Record it.** Add the visible behavior to `test/VISUAL_CHECKLIST.md`. If you
   settled a new visual rule, add a row to the table above (with the why).
