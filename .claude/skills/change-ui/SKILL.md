---
name: change-ui
description: "carl's UI/visual checklist. Use whenever you add or change a HUD element, button, panel, label, screen (map/stage picker, pause, results), color, font, or on-screen effect — before calling it done. Sibling of /change-feature (which covers type tables ⇄ wiring ⇄ tests); a UI change that also changes a gameplay concept needs both."
---

The UI uses the shared look in [ui_theme.gd](../../../scripts/ui_theme.gd):
slate panels and the Chakra Petch + Inter fonts, inherited from the
"Tabletop War Room" design canvas (carl-43). That canvas was drawn for the old
tower-defense game, so its HUD, screens and combat-effects boards don't
describe Find Carl. Use it for palette and type only. A new Find Carl screen
or HUD redesign needs its own design pass, settled with the user before
building.

## Before you build

- **Find where it lives.** The level's HUD (side gutters, results panel,
  popups overlay) is built in code in [cs_game.gd](../../../scripts/cs_game.gd)
  (`_build_hud`, `_update_hud`, `_Overlay`). The map picker is
  [map_picker.gd](../../../scripts/map_picker.gd). Fans, player and boss draw
  themselves in `_draw()`.

## If you make X, do Y

| You are making… | Do this |
| --- | --- |
| **A color** | UI chrome uses `UITheme` constants (table `#14171C`, panel `#1B1F26`, border `#2C323C`, accent `#F2CF5B`). Festival colors (dance colors, fan types, DJ pink `#FF5FA2`) live with their owners (`CSFan.DANCE_COLORS`, `TYPES`). If you're adding the second use of a color, pull it into one shared place rather than another `Color(...)` literal. |
| **Text** | Display: Chakra Petch 600/700 (`UITheme.display_font`). Body and numbers: Inter 500 (`UITheme.body_font`). Labels via `UITheme.label` / `caption`. |
| **A button or clickable** | At least **44px** tall/wide (touch target, which matters for mobile). Normal / hover / pressed states all styled via `UITheme.style_button`. Remember the mouse is **captured** during play: anything clickable mid-song needs the cursor released first, as the results screen does. |
| **Anything positioned** | The playfield is a fixed 600px column (`CSGame.FIELD`) with HUD gutters either side. HUD controls go in the gutters' containers. For new screens, use anchors and containers, not fixed offsets: the window uses `canvas_items` stretch with `expand` aspect. |
| **A full-screen or large `Control`** | `mouse_filter = IGNORE` on non-interactive containers so they don't eat clicks (clicks are the rhythm input). |
| **A modal screen** (pause, results) | Pausing must pause the music and the conductor together, release the mouse, and recapture it on resume (see carl-13). |
| **Anything that pulses or moves with the music** | Drive it from `conductor.beat_pulse()` / `beat_pos()` (or `CSFan.pulse`), not a free-running timer, so it stays locked to the song. |
| **A repeating effect** (ring, popup, spark) | Draw it as data in `_draw()` or pool it; never allocate a node per event. No per-hit tweens; refresh a timer. |
| **Feedback text over the playfield** | Use `CSGame.popup()` (drawn on the top overlay, cleared when the results screen opens) rather than new Labels. |

## Before you call it done

1. **Look at it headed.** Run windowed (`Godot --path .`) or a `--script`
   helper that saves a PNG (see [test/VISUAL_CHECKLIST.md](../../../test/VISUAL_CHECKLIST.md),
   "How to run it"), and read the screenshot. Check the resting and the
   active state (hovered, selected, open).
2. **Check another window size.** Resize (or set a different viewport size in
   the helper) and confirm nothing overlaps or drifts off-screen.
3. **Compare against the design you settled with the user**, and call out
   any deliberate divergence in the PR.
4. **Test the behavior**, not just the render: a GUT test for anything with
   logic (a button that changes state, a screen that pauses), then
   `./run_tests.sh`.
5. **Record it.** Add the visible behavior to `test/VISUAL_CHECKLIST.md`. If you
   settled a new visual rule, add a row to the table above (with the why).
