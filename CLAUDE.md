# Working on `carl`

**Find Carl**, a Godot 4 rhythm crowd-surfing game (2D, one level = one song).
It pivoted from tower defense in Nov 2026; the TD code is in git history and its
backlog is shelved on the board (carl-62). This file is for AI agents
picking up the work — it captures **how we work in this repo**, not what the game
is. For *what it is and how to play*, read [README.md](README.md); for *what's
done / next*, see the roadmap (below).

## Orient yourself first

1. **[README.md](README.md)** — game overview, systems map (one `.gd` per system),
   project structure, collision layers. Start here.
2. **Roadmap** — the source of truth for priorities is the hosted tada board
   `carl`: <https://app.tada-ai.app/b/carl>. Columns: Idea / Planned /
   In Progress / Done; shipped stories get archived to its Changelog.
   - **Edit it via the `tada` MCP server** wired in [.mcp.json](.mcp.json)
     (`view_board`, `add_story`, `set_status`, `update_story`, `board_url`, …).
     It runs `$TADA_HOME/app/mcp/server.ts` from a local
     [tada](https://github.com/UUeird/tada) clone and reads `PROD_MONGODB_URI`
     from `$TADA_HOME/app/.env.local`. **On a new machine:** clone `tada`,
     `npm install` in its `app/`, create that `.env.local`, add
     `export TADA_HOME=/path/to/your/tada` to `~/.zshrc`, and create a
     gitignored `.env.local` in this repo's root containing
     `TADA_OWNER_EMAIL=<board owner's email>` (kept out of this public repo).
     Then fully reload the editor window. If the server fails to start, check
     those.
3. **[CHANGELOG.md](CHANGELOG.md)** — shipped changes.
4. **Skills** in [.claude/skills/](.claude/skills/), ported from tada:
   `/tada` (pick up the In Progress story and work it), `/change-feature`
   (every place a gameplay change must land), `/change-ui` (HUD/visual
   checklist against the design canvas), `/release` (test gate, merge,
   cleanup, board), `/story-review` (re-assess Idea/Planned stories),
   `/git-flow` (branch lifecycle — this file wins where they differ, e.g.
   commit only when asked).

The boot scene is `scenes/map_picker.tscn`, which loads the level
`scenes/cs_main.tscn`. Engine: Godot 4.6, run via
`/Applications/Godot.app/Contents/MacOS/Godot` on this machine.

## The non-negotiables

- **Run the test gate before any PR:** `./run_tests.sh`. It runs the vendored GUT
  suite in `test/` headlessly and exits non-zero on failure. All tests must pass.
- **Verify visual/input/feel changes with a headed run + screenshot**, not just
  headless. Headless proves logic; it can't prove something *looks* right. The
  prose checks live in [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md) — add
  to it when you add visible behavior.
- **Commit/push only when asked.** Branch first if on `main`.
- **Keep the roadmap honest — every session, not just at the end.**
  All of this is on the hosted tada board via the `tada` MCP tools.
  - When you *start* a story, set its status to `in-progress`.
  - When it ships, set status to `done` and update the `note` with what actually landed.
  - If a user request doesn't map to any existing story, **add one** (or a task) before doing the work.
  - If you discover a problem or leave something half-done, add a `bug` or `chore` story.

## Conventions that matter (follow the existing grain)

- **The song is the clock.** Gameplay timing comes from `CSConductor`
  ([scripts/cs_conductor.gd](scripts/cs_conductor.gd)): connect to its
  `beat` / `half_beat` / `section_changed` / `finished` signals or read
  `song_time` / `beat_pos()`. Don't run gameplay off frame timers when it
  should follow the music. While audio plays, the clock is the latency-adjusted
  playback position; with `manual_clock = true` (tests, the bot,
  `CSGame.use_audio = false`) it only moves through `advance(dt)`. Never make
  gameplay depend on sound actually playing.
- **Pacing is data.** Per-section behavior (spawn rate, fan mix, scroll speed,
  drop bursts, Carl chance, boss) lives in `CSGame.SECTION_RULES`, keyed by
  section *kind*. The beatmap JSON only describes the music. Tune pacing in
  the table, not in code paths.
- **Data-driven type tables.** Fans define `const TYPES := {}` keyed by
  `enum Type`, with stats and flags read in `configure(type)`
  ([scripts/cs_fan.gd](scripts/cs_fan.gd)). Adding or balancing a type is a
  one-place edit; don't scatter constants across methods. Damage-like numbers
  (blast radius/power, cheer, Lift) are named consts at the top of their script.
- **Rhythm input goes through the groove.** Every rhythm input (click, Space,
  later touch or shake) calls `CSGame.try_hype_blast()`, which records into
  `CSGroove` and sizes the blast by the groove. Don't add per-beat hit/miss
  judging to new mechanics: groove deliberately tolerates constant lateness and
  rewards in-time double-time.
- **Static registries instead of group scans.** Live entities self-register in
  a `static var all_*: Array` (`CSFan.all_fans`): append in `_ready`, `erase`
  in `_exit_tree`. Always `is_instance_valid()`-check entries while iterating,
  and `duplicate()` the array if anything might free a fan mid-loop.
  Shared per-frame context (scroll speed, player position, beat pulse) is set
  once per frame as static vars on `CSFan` by the game.
- **Pool short-lived nodes; draw cheap effects as data.** Glowsticks use a
  static free-list plus `prewarm()` (`CSGlowstick`). Boss rings/lasers and
  popups are arrays of dictionaries drawn in `_draw()`, not nodes. Effects
  fade on a timer refreshed by hits (`_flash`), not a tween per hit.
- **Mouse = captured + relative.** Steering uses `MOUSE_MODE_CAPTURED` and
  `InputEventMouseMotion.relative` to move a virtual reticle
  (`CSPlayer.nudge_reticle`). Absolute cursor positions
  (`get_global_mouse_position()`, confined/hidden modes) were stale or frozen on
  macOS. Don't switch back without a real-hardware test.
- **GDScript gotchas seen here:** `min()`/`max()` return Variant, so `:=` can't
  infer from them; use `mini`/`maxi`/`minf`/`maxf` or annotate the type. A
  static var with a leading underscore can't be read as `ClassName._name` from
  another class. Self-referential typed static arrays
  (`static var _pool: Array[MyClass]`) break the parser, so use untyped `Array`.
  `var x := scene.instantiate()` can't infer its type, so annotate it
  (`var x: Node = ...`). Godot 4 projects need `config_version=5` in `project.godot`.

## Tuning difficulty

Feel is judged by playing with sound. Numbers come from the bot:
`godot --headless --path . --script test/sim_crowd_surf.gd -- <skill 0..1> <runs>`.
The bot dodges fans and ring openings, and taps a rhythm with timing wobble
scaled by `1 - skill` (going double-time in builds and drops when skilled). It
reports survival, DJ wins and average groove. Calibrate against playtests:
the bot sees everything, so real players do worse than its numbers.

## Adding a fan type or mechanic (the common task)

1. Add an entry to the `TYPES` table (color, layers, chase, grab cost, score).
2. If it needs new behavior, gate it on a flag in the table and reuse the
   registries, the conductor signals, and `SECTION_RULES` for when it appears.
3. Wire it into the `mix` (or `burst`) of the sections where it should spawn.
4. Add GUT tests ([test/test_crowd_surf.gd](test/test_crowd_surf.gd) is the
   model; set `game.use_audio = false` and step the manual clock).
5. Add the visible behavior to [test/VISUAL_CHECKLIST.md](test/VISUAL_CHECKLIST.md)
   and check it with `test/shot_crowd_surf.gd`.
6. Run `./run_tests.sh`, run the difficulty bot if balance moved, do a headed
   check, and update the roadmap.

## ultrareview

`/code-review ultra` launches a multi-agent cloud review of the current branch
(`/code-review ultra <PR#>` for a GitHub PR). It's user-triggered and billed — an
agent can't launch it. `/ultrareview` is a deprecated alias.
