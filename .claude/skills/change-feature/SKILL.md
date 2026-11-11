---
name: change-feature
description: "Change a gameplay feature completely — add, modify, or remove a tower/enemy type, damage type, mechanic, map or screen across the type tables, behavior code, scenes, HUD, spawner, asset prewarm/pools, tests, visual checklist and docs. Use before calling any non-trivial carl change 'done'."
---

A carl feature lives in several places at once, and a change applied to only
one of them ships a half-feature that looks done: a tower type added to
`TYPES` but missing a build button, an enemy type that never spawns because
`_pick_enemy_type()` wasn't wired, a new mesh that hitches mid-wave because it
wasn't prewarmed. Removal has the same trap in reverse — Frost was folded into
Shock, so every place that named Frost had to go with it. Before declaring a
change complete, walk the list below and confirm each line is either updated
or genuinely not affected.

## 0. Scope it first

- **A change to a *concept*** — a tower/enemy type, a damage type or layer, a
  stat or behavior flag — added, renamed or removed: **every surface is in
  scope until proven otherwise.** Walk the whole list.
- **A change to how an existing concept behaves or looks** is scoped to what
  its diff touches, plus a check that nothing else names it: `grep -rn` the
  enum value / key / flag across `scripts/ scenes/ test/`. If the grep only
  hits files you already changed, you're done with step 1.
- **If the grep surprises you, widen back out** — it's a concept change.

## 1. Apply across the game

- **The type table first.** Stats and behavior flags go in the `TYPES` const
  keyed by the `enum Type`, read in `configure(type)` —
  [td_tower.gd](../../../scripts/td_tower.gd),
  [td_enemy.gd](../../../scripts/td_enemy.gd). One-place edit; don't scatter
  constants across methods.
- **Behavior.** Tick logic gated on the flag, reusing the static registries
  (`TDEnemy.all_enemies`, `TDTower.all_towers`), `_process` for towers,
  `_physics_process` for enemies, timer stagger (`randf() * INTERVAL`) seeded
  in `configure()`. Effects that `add_child` into `current_scene` no-op when
  it's null, with damage applied first.
- **Wiring.** Enemies: the wave mix in `_pick_enemy_type()`
  ([td_game.gd](../../../scripts/td_game.gd)). Towers: the HUD build buttons
  and tower panel ([td_hud.gd](../../../scripts/td_hud.gd)), costs/economy,
  and [tower_sandbox.gd](../../../scripts/tower_sandbox.gd) /
  [test/shot_test_map.gd](../../../test/shot_test_map.gd) type lists. A concept
  must appear everywhere the player *picks* it, not just where it's displayed.
  Damage types: the modifier matrix and the element picker.
- **Assets** (CLAUDE.md "Adding or replacing assets"): mesh path in the
  `_MESHES` const + `_load_glb_mesh` call in `_prewarm_shaders()`; new scene or
  unique material added to `_prewarm_shaders()`; short-lived nodes pooled, not
  allocated per event. Regenerated `.glb`s need `--import` before they show.
- **Scenes.** `.tscn` files reference scripts, nodes and resources by path —
  grep them too, especially when renaming or removing.
- **When removing**, hunt down every site: a build button, a picker option, a
  wave-mix weight, a prewarm entry, a test, a checklist line for something that
  no longer exists is the removal version of a half-feature.

## 2. Saved data

carl has no save file yet. When one exists (meta-progression, carl-11),
anything that changes its shape must keep old saves loading — add fields with
defaults, never repurpose a key. Map data follows the same rule once maps are
data-driven.

## 3. Prove it with tests

Add or extend a GUT test in `test/` — [test_enemy_types.gd](../../../test/test_enemy_types.gd)
is the model: configure stats, range in/out, behavior on/off. Bias toward a
test that would have failed before your change; include an adversarial case
(zero/edge values, the flag off). When removing, assert the absence. Run
`./run_tests.sh`.

## 4. Look at it

Add the visible behavior to [test/VISUAL_CHECKLIST.md](../../../test/VISUAL_CHECKLIST.md)
and check it headed with a screenshot (the test map helper is the easy path).
Headless proves logic, not looks. UI changes also follow
[`/change-ui`](../change-ui/SKILL.md).

## 5. Document it

- An entry under `## Unreleased` in [CHANGELOG.md](../../../CHANGELOG.md).
- [README.md](../../../README.md) if it changes the systems map, a gameplay
  rule, or controls. A removal isn't done until the docs stop describing it.
- CLAUDE.md if you learned a convention or gotcha the next agent needs.

## 6. Ship it

Update the board story (CLAUDE.md "Keep the roadmap honest"), then commit/PR
when asked and land it with [`/release`](../release/SKILL.md).
