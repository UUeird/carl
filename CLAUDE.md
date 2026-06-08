# Working on `carl`

A Godot 4 tower-defense game (3D, isometric camera). This file is for AI agents
picking up the work — it captures **how we work in this repo**, not what the game
is. For *what it is and how to play*, read [README.md](README.md); for *what's
done / next*, see the roadmap (below).

## Orient yourself first

1. **[README.md](README.md)** — game overview, systems map (one `.gd` per system),
   project structure, collision layers. Start here.
2. **Roadmap** — the source of truth for priorities. Run `python3 roadmap/server.py`
   and open <http://localhost:8770/>; data lives in
   [roadmap/roadmap.json](roadmap/roadmap.json). Sections: `next` (do these),
   `later`, `ideas`, `completed` (status `done`), `debt`.
3. **[CHANGELOG.md](CHANGELOG.md)** — shipped changes.

The main scene is `scenes/td_main.tscn`. Engine: Godot 4.6, run via
`/Applications/Godot.app/Contents/MacOS/Godot` on this machine.

## The non-negotiables

- **Run the test gate before any PR:** `./run_tests.sh`. It runs the vendored GUT
  suite in `test/` headlessly and exits non-zero on failure. All tests must pass.
- **Verify visual/input/feel changes with a headed run + screenshot**, not just
  headless. Headless proves logic; it can't prove something *looks* right. The
  prose checks live in [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md) — add
  to it when you add visible behavior.
- **Commit/push only when asked.** Branch first if on `main`.
- **Keep the roadmap honest.** When you finish a roadmap item, move it to the
  `completed` section (`status: "done"`) with a note on what actually shipped; if
  you discover a problem, add a `debt` item. Validate the file after editing:
  `python3 -m json.tool roadmap/roadmap.json`.

## Conventions that matter (follow the existing grain)

- **Data-driven type tables.** Both towers and enemies define a `const TYPES := {}`
  keyed by an `enum Type`, holding per-type stats + behavior flags, and a
  `configure(type)` that reads from it. Adding or balancing a type is a *one-place
  edit in the table* — don't scatter constants across methods. See
  [scripts/td_tower.gd](scripts/td_tower.gd) and
  [scripts/td_enemy.gd](scripts/td_enemy.gd).
- **Static registries instead of group scans.** Live entities self-register in a
  `static var all_*: Array` (`TDEnemy.all_enemies`, `TDTower.all_towers`):
  append in `_ready`, `erase` in `_exit_tree`. Iterate these instead of
  `get_nodes_in_group(...)` on hot paths — the group scan was a measured
  bottleneck. Always `is_instance_valid()`-check entries while iterating.
- **Timer-driven flashes/effects, not per-hit tweens.** Repeated damage refreshes
  a `_flash_timer` that a `_process`/`_physics_process` tick fades — so a beam
  hitting every frame costs nothing extra. Don't spawn a tween per hit.
- **Stagger per-frame work across instances.** When many instances do periodic
  work (retarget, heal pulse, gun shot), seed their timer with
  `randf() * INTERVAL` in `configure()` so they don't all fire on the same frame.
- **`_process` vs `_physics_process`.** Stationary things that don't move/collide
  (towers) run in `_process`; things that move via the physics path (enemies) run
  in `_physics_process`. Putting stationary logic in `_physics_process` caused
  physics-catchup bursts.
- **Guard against a null `current_scene`.** Effects that `add_child` into
  `get_tree().current_scene` must no-op when it's null (tests run without one).
  Do gameplay-affecting work (damage) *before* the visual so the visual's null
  guard doesn't skip it. See `_spawn_explosion` in
  [scripts/td_enemy.gd](scripts/td_enemy.gd).
- **GDScript gotchas seen here:** a static var with a leading underscore can't be
  read as `ClassName._name` from another class (drop the underscore if it must be
  cross-class); `var x := scene.instantiate()` can't infer type — annotate
  `var x: Node = ...`. Godot 4 projects need `config_version=5` in `project.godot`.

## Adding an enemy or tower type (the common task)

1. Add an entry to the `TYPES` table (color, health/stats, behavior flags).
2. If it needs new behavior, add the tick logic gated on its flag (e.g.
   `if _heal_radius > 0.0: _tick_heal(delta)`), reusing the registries above.
3. For enemies, the spawner picks types in `_pick_enemy_type()` in
   [scripts/td_game.gd](scripts/td_game.gd) — wire the wave-mix there.
4. Add GUT tests (see [test/test_enemy_types.gd](test/test_enemy_types.gd) as the
   model: configure stats, range in/out, behavior on/off).
5. Add the visible behavior to [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md).
6. Run `./run_tests.sh`, do a headed check, update the roadmap.

## ultrareview

`/code-review ultra` launches a multi-agent cloud review of the current branch
(`/code-review ultra <PR#>` for a GitHub PR). It's user-triggered and billed — an
agent can't launch it. `/ultrareview` is a deprecated alias.
