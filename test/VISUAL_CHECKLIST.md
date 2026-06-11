# Visual checklist (agent-run)

The coded suite (`run_tests.sh`) covers deterministic logic. This file covers the
**visual / feel** layer that no headless assert can judge — it's written in plain
prose and executed by the agent (Claude) at test time: launch the game, drive it,
take headed screenshots, and confirm each item by *looking*. Mark results in the
PR description.

This is deliberately not code. These checks are about "does it look/feel right,"
which a human (or an agent reading a screenshot) judges better than a pixel assert.

## How to run it
1. Start the game windowed: `godot --path .` (main scene = `scenes/td_main.tscn`).
2. For each item: set up the situation (often via a temporary `--script` SceneTree
   helper that builds towers / spawns enemies), capture a screenshot, and inspect.
3. Record pass/fail (a screenshot per item is ideal) in the PR.

### Screenshot test map (preferred for tower/enemy visuals)
For *looking at towers and enemies* — shapes, emitters, health bars, damage
numbers — use the dedicated **straight test map** instead of `td_main`: a flat
spawn→goal lane with 8 tower pads (4 per side) and **no walls**, so nothing
occludes the view and the head-on camera frames everything cleanly. The main map's
isometric camera + walls made offscreen screenshots fiddly and prone to empty
frames; the test map removes that.

Render it (use the **headed** Godot binary, not `--headless`, so it actually draws):

```
/Applications/Godot.app/Contents/MacOS/Godot --path . \
	--script test/shot_test_map.gd -- /tmp/shot.png
```

`test/shot_test_map.gd` builds one of each tower type on the pads, spawns an enemy
ahead so turrets aim *across* the view (showing barrels/emitters in profile), and
saves the PNG. Scene: `scenes/td_test_map.tscn` (it reuses `td_game.gd` + the HUD,
so HUD/economy/wave checks work there too). Edit the helper for one-off setups.

## Checks

### Towers & build
- [ ] Four build buttons appear — **Cannon, Frost, Beam, Bomb** — each showing its cost.
- [ ] The **active** build type is unmistakable: its button is filled in that tower's color with a bright border; the others are muted with a thin colored accent. Selecting another type moves the highlight.
- [ ] Building a tower places a visible turret on the chosen slot; the slot turns occupied (dim).
- [ ] Each tower type is visually distinguishable by **both color and head shape** — Cannon: boxy head + barrel; Frost: crystalline prism; Beam: a **tesla-coil/ray-gun emitter** (a coil post lifting a horizontal barrel that extends forward to glowing prongs + a bright tip at the muzzle, where the beam begins); Bomb: squat mortar dome + stubby tube — and upgraded towers look bigger/brighter.
- [ ] The Beam tower's emitter **barrel and tip line up with the start of its beam** — when it fires, the beam emerges from the glowing tip at the end of the barrel, and the whole emitter swings with the turret as it tracks targets.
- [ ] When a tower acquires a target, its turret **swings around to aim** (a visible rotation) rather than snapping instantly; projectile towers hold fire until the barrel is on target.
- [ ] A tower taking Gunner/blast damage shows a **floating green-over-red health bar** above it (same style as enemies) that shrinks as HP drops and fades after a couple seconds; the head keeps its **true type color** (no scorch tint), so a hurt tower never gets confused for a different type.

### Range & line of sight
- [ ] Hovering a free slot (with a type selected) shows a translucent **range dome** sized to that type.
- [ ] Selecting a built tower shows its range dome; it grows when upgraded.
- [ ] A tower behind the obstacle wall does **not** fire at creeps hidden on the far side (LOS), but does once they clear the wall.

### Firing visuals
- [ ] Cannon/Frost fire a visible projectile that travels to and hits the target.
- [ ] Frost-hit enemies tint blue and visibly slow down.
- [ ] Beam tower draws a **solid beam** from its muzzle to the locked target; it retargets when that enemy dies.
- [ ] Bomb tower lobs an arcing bomb that rises and lands; an expanding blast ring shows the AoE; it visibly **misses** when the target rounds a corner.

### Combat feedback
- [ ] Enemy **health bars** appear on damage, show **green over red** (green shrinks left→right as HP drops), and **fade out** after ~2s; further damage resets the timer.
- [ ] Floating **damage numbers** pop white at each hit, drift up, and fade; numbers read as whole integers, and stay a **constant on-screen size when you zoom the camera in/out** (they don't shrink with the map).

### Enemy types
- [ ] **Grunt** (red) is the common creep; on death it shows a small orange **blast ring**, and a tower next to it loses HP (flashes white).
- [ ] An exploding grunt that reaches the goal shows the blast (cosmetic) and costs a life as before.
- [ ] **Healer** (green) periodically emits a green **heal pulse**; a damaged ally inside the pulse visibly regains HP (its bar grows back).
- [ ] **Gunner** (purple) fires a visible **red/orange moving sphere** at the nearest tower in range; the sphere travels across the map and hits; the targeted tower loses HP.
- [ ] A Gunner's in-flight shot **completes even if the Gunner dies or reaches the goal mid-flight** — the sphere keeps traveling to the tower and disappears (no frozen orphan spheres litter the map over a long game; the shot pool stays healthy).
- [ ] **Boss** (2× scale grunt) spawns solo between waves, walks the path with noticeably more HP, and requires sustained fire to kill.
- [ ] A tower under sustained Gunner / blast damage is **destroyed** (shrinks away), its slot frees up, and a "tower destroyed" message shows; if it was selected, the panel closes.

### Damage types & health layers
- [ ] Enemies show a **three-segment health bar**: blue (shield) → yellow (armor) → green (flesh); each segment depletes before the next begins.
- [ ] Tower upgrade panel at level 1 shows a **damage type picker** (Fire / Frost / Poison / Shock); the chosen type appears in panel stats after selection.
- [ ] Frost-typed hits still **slow enemies** (they tint blue and move visibly slower).

### HUD & flow
- [ ] The **Maps** button sits to the right of the wave/stats label in the top-left and does not overlap the tower panel.
- [ ] Lives / currency / wave update correctly as you play.
- [ ] Start-wave button is unavailable mid-wave and available between waves.
- [ ] Win message after the last wave; lose message at 0 lives; **R** restarts.

### Selection UX
- [ ] Clicking a built tower opens its panel (stats + Upgrade + Sell).
- [ ] Clicking empty ground, or pressing **Esc**, dismisses the panel; clicking another tower switches to it.

### Demo mode (debug builds only)
- [ ] A **Demo ▶** button appears (under Start-wave) in debug builds only — not in a release export.
- [ ] Clicking it autoplays hands-free: towers build out across **all four types**, get upgraded, and all 5 waves start on their own.
- [ ] The run shows varied situations (each tower type firing, Gunners damaging/destroying towers, Healer pulses) — the point of the demo.

### Camera / scene
- [ ] The iso scene is well-lit (no black/unlit surfaces); path, slots, goal, and obstacle all read clearly.
