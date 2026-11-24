---
name: change-feature
description: "Change a gameplay feature completely — add, modify, or remove a fan type, fan layer, rhythm/groove mechanic, boss attack, section rule, stage or screen across the type tables, conductor wiring, SECTION_RULES, HUD, pools, tests, visual checklist and docs. Use before calling any non-trivial carl change 'done'."
---

A carl feature lives in several places at once, and a change applied to only
one of them ships a half-feature that looks done: a fan type added to `TYPES`
but in no section's `mix` (so it never spawns), a mechanic timed off a frame
timer instead of the beat, a new input that bypasses the groove, or a HUD bar
that nothing updates. Removal has the same trap in reverse: when the
per-beat PERFECT/GOOD judging was replaced by the groove meter, every popup,
stat and results line that named "perfect blasts" had to go with it. Before
declaring a change complete, walk the list below and confirm each line is
either updated or genuinely not affected.

## 0. Scope it first

- **A change to a *concept*** (a fan type, a fan layer, a section kind, an
  input, a boss phase or attack) added, renamed or removed: **every surface is
  in scope until proven otherwise.** Walk the whole list.
- **A change to how an existing concept behaves or looks** is scoped to what
  its diff touches, plus a check that nothing else names it: `grep -rn` the
  enum value / key / flag across `scripts/ scenes/ test/ tools/`. If the grep
  only hits files you already changed, you're done with step 1.
- **If the grep surprises you, widen back out.** It's a concept change.

## 1. Apply across the game

- **The type table first.** Fan stats and flags go in `CSFan.TYPES`, read in
  `configure(type)` ([cs_fan.gd](../../../scripts/cs_fan.gd)). Tunables for the
  player, boss and groove are named consts at the top of their scripts. Make it
  a one-place edit.
- **Timing comes from the song.** Hook into `CSConductor` signals
  (`beat`, `half_beat`, `section_changed`, `finished`) or `beat_pos()`, never
  frame timers for musical events. Rhythm inputs go through
  `CSGame.try_hype_blast()` → `CSGroove`.
- **Wiring.** When and where it appears: `CSGame.SECTION_RULES`
  ([cs_game.gd](../../../scripts/cs_game.gd)), covering `mix`, `burst`,
  `every`, `scroll`, `carl` and `boss`. If a section kind is new, the beatmap
  generator ([tools/gen_test_track.py](../../../tools/gen_test_track.py)) must
  emit it, and the track must sound like it. A concept must appear wherever
  it's spawned, scored and shown (HUD, results text, stats).
- **Effects.** Short-lived nodes are pooled (`CSGlowstick` pattern: static
  free-list plus `prewarm()`); cheap repeating visuals (rings, lasers, popups)
  are data drawn in `_draw()`. No tween per hit; refresh a timer.
- **Scenes.** `.tscn` files reference scripts by path; grep them too when
  renaming or removing.
- **When removing**, hunt down every site: a `mix` weight, a HUD label, a
  results-screen stat, a test, or a checklist line for something that no
  longer exists is the removal version of a half-feature.

## 2. Saved data

carl has no save file yet. When one exists (meta-progression, carl-11),
anything that changes its shape must keep old saves loading — add fields with
defaults, never repurpose a key. Map data follows the same rule once maps are
data-driven.

## 3. Prove it with tests

Add or extend a GUT test in `test/`. [test_crowd_surf.gd](../../../test/test_crowd_surf.gd)
is the model: `game.use_audio = false`, step the manual clock to a beat, and
assert. If balance moved, also run the difficulty bot
(`test/sim_crowd_surf.gd`) across a few skill levels. Bias toward a
test that would have failed before your change; include an adversarial case
(zero/edge values, the flag off). When removing, assert the absence. Run
`./run_tests.sh`.

## 4. Look at it

Add the visible behavior to [test/VISUAL_CHECKLIST.md](../../../test/VISUAL_CHECKLIST.md)
and check it headed with a screenshot (`test/shot_crowd_surf.gd -- <beat>`).
Feel (sync, groove, steering) needs a real play with sound.
Headless proves logic, not looks. UI changes also follow
[`/change-ui`](../change-ui/SKILL.md).

## 5. Document it

- An entry under `## Unreleased` in [CHANGELOG.md](../../../CHANGELOG.md).
- [README.md](../../../README.md) if it changes the systems map, a gameplay
  rule, or controls. A removal isn't done until the docs stop describing it.
- CLAUDE.md if you learned a convention or gotcha the next agent needs.

## 6. Ship it

Update the board story (CLAUDE.md "Keep the roadmap honest"), then commit/PR
when asked and land it with [`/release`](../release/SKILL.md).
