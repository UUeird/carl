# carl

A classic **tower-defense** prototype built with [Godot 4](https://godotengine.org/):
enemies advance along a fixed path in waves, and you place & upgrade towers to stop them
before they reach the goal. 3D, viewed from an isometric camera.

> Pivoted from an earlier 3D action/FPS prototype — same engine, rebuilt gameplay. That
> earlier work is preserved in git history and noted in the roadmap's archive.

Everything is placeholder primitives (capsules/boxes) — no art is committed yet.

## Getting started

1. Install [Godot 4](https://godotengine.org/download/) (built/tested on 4.6).
2. Open Godot and import this project (`project.godot`), then press **F5**.

CLI: `godot --path .` (or `/Applications/Godot.app/Contents/MacOS/Godot --path .` on macOS).
The main scene is `scenes/td_main.tscn`.

## How to play

1. Pick a tower type from the build buttons (top-left), then click a green **slot** to place it.
2. Press **Start wave** to send a wave; towers auto-fire at enemies in range and line of sight.
3. Kills earn currency; an enemy reaching the goal costs a life. Survive all waves to win;
   reach 0 lives and you lose. **R** restarts.
4. Click a placed tower to **upgrade** it (Lv 1→3) or **sell** it (50% refund). Click empty
   ground or press **Esc** to close the panel.

### Tower types

| Tower  | Role |
|--------|------|
| **Cannon** | Burst single-target projectile. |
| **Beam**   | Continuous low **DPS** beam locked on one target. |
| **Bomb**   | Lobs an arcing AoE shell to a *predicted* landing point — leads the target, so it can miss on turns. |

Towers target the enemy **furthest along the path** within a spherical range, and only fire
with clear **line of sight** (terrain/obstacles block shots). Upgrades raise range, damage,
fire rate, and projectile speed. Towers are **destructible** — a Gunner's fire or an exploding
Grunt can destroy one, freeing its slot.

At **level 2**, every tower permanently chooses a **damage type** — Fire, Frost, Poison, or
Shock — which applies modifiers against each enemy health layer. Frost-typed towers also slow
enemies on hit.

### Enemy health layers

Enemies have up to three stacked health pools, depleted sequentially:

| Layer | Color | Depletes before… |
|-------|-------|-----------------|
| **Shield** (blue) | shown on top | Armor |
| **Armor** (yellow) | shown middle | Flesh |
| **Flesh** (red) | shown at bottom | — (death) |

Each layer gives way to a dark-grey background as it drains. Depleted layers disappear from
the health bar. Damage type modifiers apply per layer as damage flows through.

### Design influences

The damage type / health layer / damage number system is deliberately modelled on the
**Borderlands** franchise (Gearbox Software). Key borrowings:

- Elemental damage types with per-layer modifier tables (fire melts shields, shock wrecks
  armor, etc.)
- Stacked health bars that deplete sequentially and disappear when exhausted
- A single accumulating damage number per enemy that counts up across all concurrent sources,
  then pops off and fades when the damage streak ends

### Enemy types

Enemies are data-driven from a `TYPES` table the same way towers are; the spawner mixes them
by wave (Healers from wave 2, Gunners from wave 3).

| Enemy  | Behavior |
|--------|----------|
| **Grunt** (red)   | Common creep. **Explosive**: a blast when it reaches the goal, and on death a small AoE that damages nearby towers. |
| **Healer** (green) | Periodically pulses a **heal aura** that restores HP to nearby living allies. |
| **Gunner** (purple) | Carries a turret that **shoots the nearest tower** in range, damaging and eventually destroying it. |

## Testing

Run the coded test suite before opening a PR:

```
./run_tests.sh
```

It runs the [GUT](https://github.com/bitwes/Gut) suite in `test/` headlessly and exits
non-zero if anything fails (so it works as a gate). Covers the deterministic logic: economy
(build/upgrade/sell), tower targeting + line-of-sight, AoE falloff, frost slow, beam DPS,
bomb lead-prediction, and wave/lives flow.

Visual/feel behavior that can't be asserted headlessly (range domes, health bars, the beam,
damage numbers, etc.) lives in [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md) — a prose
checklist run by launching the game and inspecting screenshots. Both should be green before a PR.

> **Why GUT is committed to the repo (vendored), not installed per-developer:** Godot has no
> package manager — addons are downloaded through the editor's Asset Library GUI, which can't
> be scripted or version-pinned. Vendoring `addons/gut/` is the idiomatic Godot approach: a
> fresh clone runs `./run_tests.sh` with zero setup, the version is pinned, and CI needs nothing
> extra. The cost is a larger repo. To update GUT, re-vendor a newer release.

## What's here

- **Game controller** — economy, waves, lives, win/lose, build/upgrade/sell ([scripts/td_game.gd](scripts/td_game.gd)).
- **Tower** — targeting (range + LOS), firing, tiered upgrades; all types are data-driven from one
  `TYPES` table; **destructible** (Health + on-death slot cleanup) ([scripts/td_tower.gd](scripts/td_tower.gd)).
- **Enemy** — walks the path, has Health, slowable; exposes velocity for bomb lead-prediction.
  Multiple types (Grunt/Healer/Gunner) from a data-driven `TYPES` table
  ([scripts/td_enemy.gd](scripts/td_enemy.gd)).
- **Projectiles** — homing shot ([scripts/td_projectile.gd](scripts/td_projectile.gd)) and lobbed
  AoE bomb ([scripts/td_bomb.gd](scripts/td_bomb.gd)).
- **Slots** — clickable buildable spots ([scripts/tower_slot.gd](scripts/tower_slot.gd)).
- **HUD** — lives/currency/wave, build buttons, the tower panel ([scripts/td_hud.gd](scripts/td_hud.gd)).
- **Feedback** — billboarded enemy health bars ([scripts/health_bar.gd](scripts/health_bar.gd)) and
  floating damage numbers ([scripts/damage_number.gd](scripts/damage_number.gd)).
- **Health** — one reusable component for anything damageable ([scripts/health.gd](scripts/health.gd)).

## Project structure

```
carl/
├── project.godot          # config + input map; main scene = scenes/td_main.tscn
├── scenes/                # td_main, td_test_map (straight lane for screenshot tests), td_tower, td_enemy, td_projectile, td_bomb, tower_slot
├── scripts/               # one .gd per system (see links above)
├── test/                  # GUT tests (test_*.gd) + VISUAL_CHECKLIST.md
├── addons/gut/            # vendored test framework
├── roadmap/               # interactive roadmap app (index.html + roadmap.json + server.py)
└── run_tests.sh           # headless test gate
```

Collision layers: `2` = enemies (hittable), `4` = environment (blocks line of sight),
`8` = tower slots.

> Note: the repo still contains the earlier action-prototype scenes/scripts (player, boss,
> combat, level). They're not part of the TD game and are slated for cleanup — see the
> roadmap's debt list.

## Roadmap

What's done, open, and next lives in the interactive roadmap — run `python3 roadmap/server.py`
and open <http://localhost:8770/>. Shipped changes
are recorded in [CHANGELOG.md](CHANGELOG.md).
