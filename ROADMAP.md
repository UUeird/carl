# carl — Roadmap

A living planning doc for the game. We edit this together as we go: check items off,
add new ones, move things between sections, and revise decisions when we learn something
from playing. Keep it honest — if something's half-done or unproven, say so.

_Last updated: 2026-05-29 · Current version: 2026.05.29.2 (see [CHANGELOG.md](CHANGELOG.md))_

---

## Vision (what we're making)

A 3D action game with **boss fights, fighting through levels, and puzzles**. Built in
Godot 4. Currently a prototype — proving the core loop is fun before scaling up.

**Big open question:** isometric vs first-person. Both are playable right now via a toggle
(**V**). Shooting in first-person "feels good" so far. We haven't committed; we're playing
both to decide.

## Completed

Finished chunks of work, newest first. Each `###` group is a self-contained unit that maps
to one commit — when we wrap a chunk, the heading becomes the commit subject and the bullets
become the body. Move items here from "Next up" as they ship; once recorded in
[CHANGELOG.md](CHANGELOG.md) under a version they can be trimmed to keep this readable.

Everything below is placeholder primitives (capsules/boxes) — no art committed yet.

### Weapons & FPS-style shooting
- Body gun (visible iso/third-person) + first-person viewmodel (bottom-right, FP-only)
- Projectiles spawn from the active muzzle; FP shots follow the camera's full 3D aim
  (incl. pitch), iso stays flat

### First-person mode + presentation polish
- First-person view toggle (**V**): mouse-look, camera-relative movement, camera-forward aim
- FP crosshair (HUD, FP-only); fixed the HUD swallowing mouse-look input
- Lit environment (sky + ambient) so both iso and FP read clearly
- Per-instance enemy/boss materials (fixed all enemies flashing together)

### Level, platforming & enemies
- One linear level: start → path → arena → platforming → arena → sealed boss arena
- Jump + gravity + coyote time; platforming over pits; landing marker (iso) to judge jumps
- Fall → checkpoint respawn with fall damage; checkpoints at each arena
- Small chaser enemies (detect → chase → contact damage)
- Boss: dormant until you enter its arena, then `CHASE → TELEGRAPH → ATTACK → COOLDOWN`
- Follow camera with look-ahead (iso)

### Core combat prototype
- Iso movement (camera-relative WASD) + mouse-cursor aiming
- Combat system with a one-switch feel selector (`combat_mode`: melee / ranged / mixed) — currently **ranged**
- Reliable projectile hits (stepped sphere-overlap; no tunnelling/vertical misses)
- HUD: player + boss HP bars, win/lose message
- Reusable `health.gd` shared by player/enemies/boss

## Decisions log

- **3D isometric first** — to test the most ambitious vision before simplifying. _(set 2026-05-29)_
- **Combat feel decided by playing** — hence the `combat_mode` switch in `combat.gd`. Currently ranged. _(2026-05-29)_
- **First-person added as a toggle, not a replacement** — so we can A/B without losing the iso work. _(2026-05-29)_
- **Art deferred** — placeholder shapes until the loop is proven fun. _(2026-05-29)_

## The big fork: pick a camera direction

We can't polish two control schemes forever. Decide, then delete the loser's scaffolding.

- [ ] Play both modes through the whole level and note which is more fun
- [ ] Decide: first-person, isometric, or third-person over-shoulder
- [ ] Once decided, design encounters/level geometry *for that view* (sightlines differ a lot)

## Next up (near-term, roughly prioritized)

- [ ] **First-person feel & weapon polish** — the FP gun works but feels flat:
  - [ ] Muzzle flash + a tracer/visible-bullet read on firing
  - [ ] Recoil / weapon-sway / fire kick so shots have weight
  - [ ] Replace the blocky placeholder gun shapes with something more gun-like
  - [ ] Crosshair could tighten/tint when on-target
  - [ ] Mouse-look tuning — sensitivity, optional invert-Y, adjustable FOV
- [ ] **Enemy variety** — at least one ranged/turret enemy so fights aren't all melee-chasers
- [ ] **Combat feedback** — hit sound/particle, damage numbers or screen-shake, death effect polish
- [ ] **Boss fight depth** — more than one attack; a second phase at low HP
- [ ] **A real puzzle** — the pressure-plate/door probe exists; build one actual puzzle into the level
- [ ] **Player feedback when hit** — screen flash / knockback (right now only the HP bar moves)

## Later (bigger bets, not yet scheduled)

- [ ] Main menu + pause + proper game-over/restart flow (beyond the **R** key)
- [ ] Multiple levels + progression between them
- [ ] Save/checkpoint persistence across sessions
- [ ] Audio pass (music + SFX)
- [ ] Art pass — commit to a style once the loop is locked (see the original art question)
- [ ] Settings (controls, sensitivity, volume)

## Known issues / debt

- Level geometry was laid out for the iso read; it *works* in FP but isn't designed for it.
- No crosshair/aim-assist read in iso beyond the character facing; fine for now.
- `combat.gd` MIXED mode is a quick "both at once" — revisit if mixed becomes the direction.
- Restart is just **R** (reloads the scene); no UI around death/victory yet.

## How we work in this repo

- Controls + structure live in [README.md](README.md); planning lives here; shipped changes
  are recorded in [CHANGELOG.md](CHANGELOG.md).
- One `.gd` per system in `scripts/`; reusable components (`health.gd`, `combat.gd`) are shared.
- Changes get verified before "done": headless for parse/logic, **headed screenshots** for
  anything visual or input-related. Live mouse-feel still needs a human at the keyboard.

### Shipping a chunk of work

1. Build it; move the item(s) from **Next up** to **Completed** (group under a `###` heading).
2. When ready to record a version, add a CHANGELOG entry (CalVer `YYYY.MM.DD`, `.N` for a
   second cut the same day) and bump `Version.STRING` in [scripts/version.gd](scripts/version.gd)
   so the in-app overlay matches.
3. Commit: use the Completed group's heading as the subject and its bullets as the body.
