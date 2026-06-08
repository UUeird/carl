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

## Checks

### Towers & build
- [ ] Four build buttons appear — **Cannon, Frost, Beam, Bomb** — each showing its cost.
- [ ] The **active** build type is unmistakable: its button is filled in that tower's color with a bright border and a ► marker; the others are muted with a thin colored accent. Selecting another type moves the highlight.
- [ ] Building a tower places a visible turret on the chosen slot; the slot turns occupied (dim).
- [ ] Each tower type is visually distinguishable (color/shape), and upgraded towers look bigger/brighter.

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
- [ ] Floating **damage numbers** pop white at each hit, drift up, and fade; numbers read as whole integers.

### Enemy types
- [ ] **Grunt** (red) is the common creep; on death it shows a small orange **blast ring**, and a tower next to it loses HP (flashes white).
- [ ] An exploding grunt that reaches the goal shows the blast (cosmetic) and costs a life as before.
- [ ] **Healer** (green) periodically emits a green **heal pulse**; a damaged ally inside the pulse visibly regains HP (its bar grows back).
- [ ] **Gunner** (purple) fires a brief yellow **tracer** at the nearest tower in range; the targeted tower flashes white and loses HP.
- [ ] A tower under sustained Gunner / blast damage is **destroyed** (shrinks away), its slot frees up, and a "tower destroyed" message shows; if it was selected, the panel closes.

### HUD & flow
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
