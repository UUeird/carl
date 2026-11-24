# carl

**Find Carl** is a rhythm crowd-surfing game built with [Godot 4](https://godotengine.org/).
You've lost your friend Carl at a music festival. Each level is one stage and one song:
you crowd-surf toward the stage while the crowd moves to the music, winning fans over
(not hurting them), and at the final drop you win over the DJ, who might know where Carl went.

> Earlier versions of this repo were a 3D tower-defense game and, before that, a 3D action
> prototype. Both are preserved in git history. The tower-defense backlog is shelved on
> the board (carl-62).

Everything is gray-box placeholder art, and the music is a generated placeholder track.

## Getting started

1. Install [Godot 4](https://godotengine.org/download/) (built and tested on 4.6).
2. Run `godot --path .` (on macOS: `/Applications/Godot.app/Contents/MacOS/Godot --path .`),
   or open `project.godot` in the editor and press **F5**.
3. Pick **Find Carl: Main Stage** in the map picker. To skip the picker, run
   `godot --path . scenes/cs_main.tscn`.

Play with sound on; the whole game is driven by the music.

## How to play

| Input | What it does |
|---|---|
| **Mouse** | Steer. The cursor is captured; a reticle (four white ticks) shows where you're heading, and the surfer chases it. |
| **Click in time with the music** | Hype Blast: a ring that wins over fans around you. **Space** works too. |
| WASD / arrows | Alternative steering. |
| R / Esc | Restart / back to the map picker. |

- **Groove:** every click blasts. How big and strong the blast is depends on your groove,
  meaning how steady your rhythm has been over the last few beats. Going double-time
  *in time* during builds and drops hits harder (**FREAKING OUT**); random mashing barely
  does anything. Being consistently a little late doesn't count against you.
- **Glowsticks** fly automatically on every eighth note. While the DJ is on stage, they
  aim at the booth.
- **Lift** is your health. Grabby fans drain it; surfing over fans who are dancing
  (won over) refills it, and so does a steady groove. At zero, the crowd drops you.
- **Carl** (orange, bucket hat) darts through the crowd now and then. Touch him for a
  sighting.
- **The DJ** arrives on the final drop. They attack on the beat: bass rings (surf through
  the opening) and lasers (aimed one beat before they fire). Your in-groove blasts send
  cheers to the stage. Win the DJ over before the song ends to find out where Carl went.

### Fans

Fans have up to three layers, worn down in order: **headphones** (blue; glowsticks barely
register, but Hype Blasts knock them off), **crossed arms** (yellow; skeptical), and
**hype** (pink; when full, the fan is won over and starts dancing).

| Fan | |
|---|---|
| Fan (pink) | Hype only. |
| Headphones (blue) | Tuned out until a blast knocks the headphones off. |
| Skeptic (yellow, arms crossed) | Drifts toward you. |
| Superfan (big purple) | All three layers; arrives in bursts when a drop hits. |

## How the song drives the level

The beatmap (`assets/music/test_track.json`) splits the song into sections: intro, groove,
build, drop, breakdown, boss drop and outro. `CSGame.SECTION_RULES` sets each section kind's
spawn rate, fan mix, scroll speed and drop bursts, so tuning pacing against the music is a
one-table edit. The track and its beatmap both come from one structure table in
`tools/gen_test_track.py`, so they can't drift apart. Run
`python3 tools/gen_test_track.py` to regenerate them.

## What's here

| System | File |
|---|---|
| Beat clock: audio-synced beat, half-beat and section signals, plus a manual clock for tests | [scripts/cs_conductor.gd](scripts/cs_conductor.gd) |
| Groove: rhythm-over-time scoring (phase × evenness × tempo fit) | [scripts/cs_groove.gd](scripts/cs_groove.gd) |
| Game controller: spawning, section rules, contacts, HUD, results | [scripts/cs_game.gd](scripts/cs_game.gd) |
| Player: steering, Lift, combo, Hype Blast | [scripts/cs_player.gd](scripts/cs_player.gd) |
| Fans: the `TYPES` table and layer logic | [scripts/cs_fan.gd](scripts/cs_fan.gd) |
| Glowsticks (pooled) | [scripts/cs_glowstick.gd](scripts/cs_glowstick.gd) |
| The DJ boss: phases and beat-timed attacks | [scripts/cs_boss.gd](scripts/cs_boss.gd) |
| Map picker | [scripts/map_picker.gd](scripts/map_picker.gd) |
| Shared UI look: palette, bundled fonts (Chakra Petch + Inter), button/panel styles | [scripts/ui_theme.gd](scripts/ui_theme.gd) |

## Project structure

```
carl/
├── project.godot        # config + input map; main scene = scenes/map_picker.tscn
├── scenes/              # map_picker (boot), cs_main (the level)
├── scripts/             # one .gd per system (table above)
├── assets/fonts/        # Chakra Petch + Inter (OFL)
├── assets/music/        # placeholder track + beatmap
├── tools/               # gen_test_track.py
├── test/                # GUT tests, screenshot helper, difficulty bot, VISUAL_CHECKLIST.md
├── addons/gut/          # vendored test framework
└── run_tests.sh         # headless test gate
```

## Testing

```
./run_tests.sh
```

It runs the [GUT](https://github.com/bitwes/Gut) suite in `test/` headlessly and exits
non-zero if anything fails, so it works as a gate. The suite covers the beat clock, groove
scoring, fan layers, spawning against section rules, blasts, Lift, the boss, mouse
steering and the map picker.

- **Looks and feel:** [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md) is a prose
  checklist checked against headed screenshots. Take them with
  `test/shot_crowd_surf.gd`.
- **Difficulty:** `godot --headless --path . --script test/sim_crowd_surf.gd -- <skill 0..1> <runs>`
  plays the whole song with a bot and reports survival, DJ wins and average groove.

> **Why GUT is committed to the repo (vendored), not installed per developer:** Godot has
> no package manager. Addons come from the editor's Asset Library GUI, which can't be
> scripted or version-pinned. Vendoring `addons/gut/` lets a fresh clone run
> `./run_tests.sh` with no setup.

## Roadmap

What's done, open and next lives on the hosted [tada](https://app.tada-ai.app) board at
<https://app.tada-ai.app/b/carl>. Shipped changes are recorded in [CHANGELOG.md](CHANGELOG.md).
