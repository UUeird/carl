# Changelog

All notable changes to **carl**, newest first.

## Versioning

Date-based (**CalVer**), format `YYYY.MM.DD`. A second cut on the same day gets a `.N`
suffix (e.g. `2026.05.29`, then `2026.05.29.2`). Versions sort chronologically. The current
version is shown in-app (bottom-right overlay) and defined in
[scripts/version.gd](scripts/version.gd) — keep that constant in sync with the top entry here.

Pre-1.0 by nature: this is a prototype, anything can still change.

---

## Unreleased

### Fixed
- **Gunner shot pool leak** — a Gunner's in-flight projectile mover was parented to the Gunner, so if the Gunner died or reached the goal mid-flight the mover was freed with it, orphaning a visible pooled sphere on the map and permanently draining the shot pool. The mover is now parented to the scene and flies to completion.

### Docs
- README & CLAUDE.md: corrected the boot scene to `map_picker.tscn` (it loads `td_main.tscn`); documented the Boss enemy in the README enemy table; removed the stale "leftover action-prototype scripts" note (those files no longer exist).
- Removed dead `DamageNumber.popup()` API (superseded by `acquire`/`release`).
- Roadmap: removed two stray "Test ticket from Playwright" items.

## 2026.06.09

### Added
- **Boss enemy** — large (2× scale), high-health (120 flesh + 60 armor), slow creep worth 40g that spawns solo between each wave.
- **Damage layer system** — enemies have shield / armor / flesh HP pools that deplete sequentially; health bar shows three colour segments.
- **Damage type system** — towers choose a damage type (Fire / Frost / Poison / Shock / Physical) at first upgrade; a modifier matrix amplifies or resists each type against each layer.
- **Enemy projectiles** — Gunner enemies fire visible red/orange moving spheres instead of instant tracer cylinders; 24-slot pool, no per-shot allocation.
- **Map picker** — new scene lets you choose a map before starting.
- **Performance timer** (`PerfTimer`) for per-bucket CPU profiling in debug builds.

### Changed
- Projectile pool (32 slots) and bomb pool (8 slots) replace instantiate/queue_free per shot.
- Healer aura ring is now parented to the healer so it follows the enemy as it moves.
- Damage numbers now use a per-enemy accumulator with a single pinned label (Borderlands-style), pooled to avoid Label3D allocation mid-combat.
- Fixed "0" damage number flash on enemy death.
- **Maps button** moved to top-left row (beside wave/stats) so it no longer overlaps the tower panel.
- Roadmap: sections reordered (In Progress → Planned → Debt → Ideas → Done), Next Up removed, starred items sort to section top, star/unstar toggle on card, status picker cleaned up.

---

## 2026.06.06

### Changed
- **Roadmap is now an interactive HTML app** instead of a flat markdown doc. Data lives in
  `roadmap/roadmap.json` (the source of truth); `roadmap/index.html` renders a dashboard with
  progress stats, search, status filters, collapsible sections, hash-deep-linkable filters, and
  the starred "view-switching" idea highlighted. `ROADMAP.md` is now a short pointer + the
  "how we work" notes.
- **In-browser editing that saves to disk** — a tiny stdlib Python server
  (`roadmap/server.py`) serves the page and persists edits to `roadmap.json` (atomic write).
  Add / edit / reorder / delete items, change status or section, and star items right in the
  page; no more download-and-replace. Without the server it falls back to a read-only viewer.
- `.claude/` (local editor/agent settings) is now gitignored.

---

## 2026.05.29.2

### Added
- **Weapons** — a gun on the player body (visible in iso/third-person) and a first-person
  viewmodel (bottom-right, FP-only). Projectiles now spawn from the active gun's muzzle.

### Changed
- **Projectile aim** — in first-person, shots travel along the camera's full 3D aim
  (including up/down pitch) instead of always flying flat. Isometric keeps the flat,
  floor-aimed shot that suits its top-down view.

---

## 2026.05.29

First recorded version. Everything is placeholder primitives (capsules/boxes); no art yet.

### Added
- **Core combat** — camera-relative WASD movement, mouse aiming, and a one-switch combat-feel
  selector (`combat_mode`: melee / ranged / mixed), currently set to ranged. Projectiles use a
  stepped sphere-overlap so hits are reliable (no tunnelling or vertical misses).
- **A level** — one linear path: start → path → arena → platforming gap → arena → sealed boss
  arena. Jump with gravity + coyote time, platforming over pits, fall-to-checkpoint respawn
  with fall damage, and an iso landing marker to judge jumps.
- **Enemies & boss** — small chaser enemies (detect → chase → contact damage) and a boss that
  stays dormant until you enter its arena, then runs a `CHASE → TELEGRAPH → ATTACK → COOLDOWN`
  loop. Reusable `health.gd` shared across player/enemies/boss.
- **First-person mode** — toggle with **V**: mouse-look, camera-relative movement,
  camera-forward aim, and an FP-only crosshair.
- **Presentation** — lit environment (sky + ambient) so both iso and first-person read clearly;
  HUD with player + boss HP bars and a win/lose message; follow camera with look-ahead (iso).
- **In-app version overlay** (this versioning system).

### Fixed
- All enemies flashed together when one was hit — each enemy/boss now owns its material instance.
- The full-screen HUD swallowed mouse-look input in first-person — HUD set to ignore mouse,
  look handling moved ahead of the UI.
