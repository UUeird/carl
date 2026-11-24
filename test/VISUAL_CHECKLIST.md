# Visual checklist (agent-run)

The coded suite (`run_tests.sh`) covers deterministic logic. This file covers the
**visual / feel** layer that no headless assert can judge — it's written in plain
prose and executed by the agent (Claude) at test time: launch the game, drive it,
take headed screenshots, and confirm each item by *looking*. Mark results in the
PR description.

This is deliberately not code. These checks are about "does it look/feel right,"
which a human (or an agent reading a screenshot) judges better than a pixel assert.

## How to run it
1. Play it windowed with sound: `godot --path .` → map picker → **Find Carl: Main Stage**
   (or straight in: `godot --path . scenes/cs_main.tscn`). Feel — sync, groove,
   mouse steering — can only be judged this way.
2. For screenshots, use the headed helper (NOT `--headless`, so it draws). It plays
   the level silently on the manual clock with a scripted surfer that weaves and
   taps (quarters, 16ths in builds/drops/boss), then saves a PNG:

```
/Applications/Godot.app/Contents/MacOS/Godot --path . \
	--script test/shot_crowd_surf.gd -- <beat|results> /tmp/cs.png [mouse]
```

   Useful beats: 40 (groove), 60 (build), 72 (Drop 1), 146 (DJ arrives), 170 (boss).
   Add `mouse` to show the steering reticle.
3. Record pass/fail (a screenshot per item is ideal) in the PR.

## Checks

### Map picker
Screenshot: `Godot --path . --script test/shot_crowd_surf.gd -- picker <out.png>`.
- [ ] Large **carl** title in Chakra Petch, "Select a map" under it, the version string at the right of the header.
- [ ] One card, **Find Carl: Main Stage**: a crowd thumbnail, the name, a **Proto** tag and a one-line description.
- [ ] Hovering the card lightens it and shows a pointer cursor; clicking starts the song. The card's border stays visible all the way round (the thumbnail doesn't cover it).

### Find Carl: Main Stage (`scenes/cs_main.tscn`)
Capture with `godot --path . --script test/shot_crowd_surf.gd -- <beat|results> /tmp/cs.png`
(silent manual clock, scripted surfer that weaves and blasts on the beat). For
*feel*, play it with sound: map picker → **Find Carl: Main Stage**.
- [ ] Playfield is a centered vertical column; left gutter shows title / section / score / combo / controls, right gutter shows Lift, Distance to stage, Carl sightings, and a DJ WON OVER bar that fills up (status line: "Arrives on the final drop" → "NN% · blast on the beat!" → "WON OVER!"). Left gutter states the GOAL. Nothing in the play layer (boss rings, lasers) draws over the gutters.
- [ ] Floor stripes flow toward the surfer; stage lights at the top pulse on every beat, and sweep the crowd with colored beams during drops and the boss section.
- [ ] Glowsticks leave the surfer on every eighth note (audibly locked to the hats); at combo ≥ 8 they fan out three-wide.
- [ ] Mouse is captured during play; moving it steers a reticle (four white corner ticks, visible even under the surfer, with a faint line to it) that the surfer chases at a capped speed. The cursor comes back on the results screen.
- [ ] A closing ring around the surfer lands on each beat. Every click (or Space) fires a Hype Blast sized by GROOVE: a gold ring when locked in, cyan when grooving, small grey when off. The left gutter's GROOVE bar and tier label ("LOCKED IN · quarter notes", "FREAKING OUT · 16th notes" …) track the rhythm. Tier changes pop above the surfer. Clicking in time at 16ths during a build reads FREAKING OUT; random mashing reads OFF BEAT.
- [ ] Fans read by type: pink plain, blue with headphones, yellow with crossed-arm X, big purple superfans with both. A layer bar (blue/yellow/pink) appears under a fan once it starts being won over.
- [ ] Converted fans change color, put their arms up and bob on the beat; surfing over one shows "+lift".
- [ ] Drop 1 and the boss drop hit with a white flash, a camera shake, a "DROP!" popup, and a burst of superfans.
- [ ] When the DJ arrives, a pink "WIN OVER THE DJ!" popup appears with a smaller "blast on the beat to send cheers to the stage" line under it, and on-beat blasts pop "cheer!" at the booth.
- [ ] The DJ slides onto the booth at the boss drop. Bass rings expand on the beat, each with an opening that drifts but stays near the middle, so you surf through it without being pinned to a wall. While the DJ is on the booth, glowsticks fly toward the booth, not straight up. Phase 2 adds dashed laser telegraphs that fire on the next beat.
- [ ] Carl (orange, black bucket hat) darts sideways through the crowd during the groove/breakdown; touching him pops "CARL?! ...he slipped away".
- [ ] The results panel shows the right ending (DJ won over / dropped / reached the stage but the DJ wasn't won over). It explains why in plain words, including how far the DJ got won over (NN%) and what to do differently, and shows the stats, with Play again and Map picker buttons.
