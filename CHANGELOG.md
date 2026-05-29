# Changelog

All notable changes to **carl**, newest first.

## Versioning

Date-based (**CalVer**), format `YYYY.MM.DD`. A second cut on the same day gets a `.N`
suffix (e.g. `2026.05.29`, then `2026.05.29.2`). Versions sort chronologically. The current
version is shown in-app (bottom-right overlay) and defined in
[scripts/version.gd](scripts/version.gd) — keep that constant in sync with the top entry here.

Pre-1.0 by nature: this is a prototype, anything can still change.

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
