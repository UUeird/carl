# carl

A 3D action **prototype** built with [Godot 4](https://godotengine.org/), playable in both
isometric and first-person (toggle with **V**).

This is a vertical slice, not a finished game. It's a single explorable **level**: fight
through arenas of small enemies, cross a platforming gap over a pit, and face a boss gated at
the end. Combat can flip between melee, ranged, and mixed from a single switch
([scripts/combat.gd](scripts/combat.gd)) so combat feel can be decided by playing.

## Getting Started

1. Install [Godot 4](https://godotengine.org/download/) (built/tested on 4.6).
2. Open Godot, import this project (`project.godot`).
3. Press **F5** to run.

CLI: `godot --path .` (or `/Applications/Godot.app/Contents/MacOS/Godot --path .` on macOS).

## Controls

| Action | Key |
|--------|-----|
| Move   | **WASD** / arrow keys |
| Aim    | **Mouse** |
| Jump   | **Space** (with coyote time — works briefly after leaving a ledge) |
| Attack | **Left mouse** |
| Toggle view | **V** — switch between isometric and first-person |
| Free mouse (in FP) | **Esc** (click to re-capture) |
| Restart | **R** |

When airborne, a **cyan landing marker** projects straight down to show where you'll touch
down — it grows brighter mid-jump and disappears when you're over a pit.

### View modes

Press **V** to toggle between two cameras (an experiment — both share the same combat,
jump, and enemy logic):

- **Isometric** (default) — screen-aligned WASD, mouse-cursor aim, follow camera with
  look-ahead. Aim by moving the mouse; the character faces the cursor.
- **First-person** — mouse-look (the body yaws, the camera pitches), camera-relative WASD,
  and aim straight down the camera via a center **crosshair**. The mouse is captured; press
  **Esc** to free it.

Planning and the longer-term direction live in [ROADMAP.md](ROADMAP.md).

## The core experiment: combat feel

All combat lives in [scripts/combat.gd](scripts/combat.gd) so you can decide melee vs ranged
vs mixed *by playing*, not by guessing. Open the **Player → Combat** node in the inspector and
change **Combat Mode**:

- `MELEE` — short forward hit arc (tunables: damage, range, arc, cooldown).
- `RANGED` — fires a projectile toward the cursor (tunables: damage, speed, cooldown).
- `MIXED` — both on each attack.

Every tuning number is an export on that node, editable live — no code changes needed to
compare feels. This is the whole point of the prototype.

## The level

A single linear level you traverse from start to boss ([scenes/main.tscn](scenes/main.tscn)):

1. **Start platform** → a path leading into the level.
2. **Arena 1** — a few small chaser enemies.
3. **Platforming gap** — raised platforms at varying heights over a **pit**. Fall in and you
   respawn at the last checkpoint (with fall damage). The landing marker helps you judge jumps.
4. **Arena 2** — more enemies, on raised ground.
5. **Boss arena** — crossing the entrance **seals the door behind you** and **wakes the boss**;
   it's dormant until then.

**Checkpoints** sit at the start of each arena, so a pit fall doesn't send you far back.

## What's here

- **Player** — iso movement, mouse-aim, jump/coyote-time, fall-respawn, landing marker
  ([scripts/player.gd](scripts/player.gd)).
- **Follow camera** — tracks the player with look-ahead toward movement
  ([scripts/follow_camera.gd](scripts/follow_camera.gd)).
- **Small enemy** — detects, chases, and deals contact damage; a trimmed cousin of the boss
  ([scripts/enemy.gd](scripts/enemy.gd)).
- **Boss** — `IDLE → CHASE → TELEGRAPH → ATTACK → COOLDOWN` state machine; yellow wind-up,
  lunge attack, `start_dormant` until activated ([scripts/boss.gd](scripts/boss.gd)).
- **Gating** — boss trigger seals the arena + wakes the boss
  ([scripts/boss_trigger.gd](scripts/boss_trigger.gd)); checkpoints update respawn
  ([scripts/checkpoint.gd](scripts/checkpoint.gd)).
- **HUD** — player + boss HP bars, win/lose message ([scripts/hud.gd](scripts/hud.gd)).
- **Health** — one reusable component shared by player/enemies/boss ([scripts/health.gd](scripts/health.gd)).
- **Puzzle probe** — a pressure-plate/door script kept for later use
  ([scripts/pressure_plate.gd](scripts/pressure_plate.gd)).

Everything is placeholder primitives (capsules/boxes) — no art is committed yet.

## Project structure

```
carl/
├── project.godot        # config + input map (move/jump/attack/toggle_view/restart)
├── scenes/
│   ├── main.tscn         # the level: path, arenas, platforming, boss gate, camera, HUD
│   ├── player.tscn       # CharacterBody3D + Health + Combat + landing marker
│   ├── enemy.tscn        # small chaser (CharacterBody3D + Health)
│   ├── boss.tscn         # CharacterBody3D + Health + state machine
│   └── projectile.tscn   # Area3D used in RANGED/MIXED mode
└── scripts/              # one .gd per system (see links above)
```

Collision layers: `1` = player, `2` = hittable (enemies/boss), `4` = environment.

---

What's decided, what's open, and what's next lives in [ROADMAP.md](ROADMAP.md).
