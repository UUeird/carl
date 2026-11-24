extends GutTest

## "Find Carl" crowd-surf prototype: the song clock, beat-driven spawning, the
## win-them-over layer system, Hype Blast timing, Lift, and the boss.
## The game runs with use_audio = false so the conductor is a manual clock.

const MAIN := preload("res://scenes/cs_main.tscn")

var game: CSGame

func before_each():
	game = MAIN.instantiate()
	game.use_audio = false
	add_child_autofree(game)
	await wait_process_frames(1)

func _spb() -> float:
	return game.conductor.seconds_per_beat()

## Step the manual clock to just past beat `b`.
func _to_beat(b: float) -> void:
	game.conductor.advance(b * _spb() + 0.001 - game.conductor.song_time)

func _clear_fans() -> void:
	for f in CSFan.all_fans.duplicate():
		f.free()

# --- Conductor ----------------------------------------------------------------

func test_beatmap_loads():
	var c := game.conductor
	assert_eq(c.bpm, 128.0)
	assert_gt(c.sections.size(), 4, "track has several sections")
	assert_eq(c.sections[-1]["end"], c.length_beats, "sections cover the whole song")

func test_beats_and_half_beats_fire_in_order():
	var c := CSConductor.new()
	add_child_autofree(c)
	c.manual_clock = true
	c.load_beatmap({"bpm": 120, "length_beats": 8, "sections": [{"name": "A", "kind": "groove", "start": 0, "end": 8}]})
	var beats := []
	var halves := []
	c.beat.connect(func(b): beats.append(b))
	c.half_beat.connect(func(h): halves.append(h))
	c.play()
	c.advance(1.6)   # 0.5s per beat → beats 0..3, halves 0..6
	assert_eq(beats, [0, 1, 2, 3])
	assert_eq(halves, [0, 1, 2, 3, 4, 5, 6])

func test_section_change_and_finish():
	var c := CSConductor.new()
	add_child_autofree(c)
	c.manual_clock = true
	c.load_beatmap({"bpm": 120, "length_beats": 4, "sections": [
		{"name": "A", "kind": "intro", "start": 0, "end": 2},
		{"name": "B", "kind": "drop", "start": 2, "end": 4}]})
	var kinds := []
	c.section_changed.connect(func(s): kinds.append(s["kind"]))
	watch_signals(c)
	c.play()
	c.advance(1.01)
	assert_eq(kinds, ["intro", "drop"])
	assert_signal_not_emitted(c, "finished")
	c.advance(1.1)
	assert_signal_emitted(c, "finished")

func test_judge_windows():
	var c := game.conductor
	var spb := _spb()
	assert_eq(c.judge(spb * 4.0), "perfect")
	assert_eq(c.judge(spb * 4.0 + 0.1), "good")
	assert_eq(c.judge(spb * 4.0 - 0.1), "good", "early hits count too")
	assert_eq(c.judge(spb * 4.5), "miss", "halfway between beats is a miss")

# --- Fans: layers ---------------------------------------------------------------

func test_fan_types_configure_from_table():
	for t in CSFan.TYPES:
		var f := CSFan.new()
		f.configure(t)
		assert_eq(f.max_hype, CSFan.TYPES[t]["hype"])
		assert_eq(f.radius, CSFan.TYPES[t]["radius"])
		f.free()

func test_layers_deplete_in_order_and_convert():
	var f: CSFan = game.spawn_fan(CSFan.Type.ELITE, Vector2(640, 300))
	f.win_over(1.0, "blast")   # 1 * 2.0 vs phones
	assert_almost_eq(f.phones, f.max_phones - 1.0 * CSFan.MODS["blast"]["phones"], 0.001, "headphones come off first")
	assert_eq(f.crossed, f.max_crossed, "arms untouched while headphones are on")
	f.win_over(100.0, "blast")
	assert_true(f.is_converted, "enough hype converts the fan")

func test_glowsticks_barely_dent_headphones():
	var a: CSFan = game.spawn_fan(CSFan.Type.HEADPHONES, Vector2(500, 300))
	var b: CSFan = game.spawn_fan(CSFan.Type.HEADPHONES, Vector2(700, 300))
	a.win_over(2.0, "glowstick")
	b.win_over(2.0, "blast")
	assert_gt(a.phones, b.phones, "Hype Blast is the headphone counter")

func test_converted_fan_ignores_more_hype():
	var f: CSFan = game.spawn_fan(CSFan.Type.FAN, Vector2(640, 300))
	watch_signals(f)
	assert_true(f.win_over(10.0, "glowstick"))
	assert_false(f.win_over(10.0, "glowstick"))
	assert_signal_emit_count(f, "converted", 1)

func test_glowstick_hits_fan():
	_clear_fans()
	var f: CSFan = game.spawn_fan(CSFan.Type.FAN, Vector2(640, 300))
	f.set_process(false)
	var g := CSGlowstick.throw(game, Vector2(640, 330), Vector2(0, -CSGlowstick.SPEED))
	g._process(0.05)
	assert_lt(f.hype, f.max_hype, "glowstick wins the fan over a little")
	assert_false(g.visible, "glowstick returns to the pool on hit")

# --- Beat-driven spawning -----------------------------------------------------

func test_spawns_follow_section_rules():
	_clear_fans()
	# Intro spawns every 4 beats: beats 0, 4, 8, 12 → 4 fans by beat 13.
	_to_beat(13)
	var n := 0
	for f in CSFan.all_fans:
		if not f.is_carl:
			n += 1
	assert_eq(n, 4)

func test_drop_hits_with_elite_burst():
	_to_beat(63.5)
	_clear_fans()
	_to_beat(64)
	var elites := CSFan.all_fans.filter(func(f): return f.fan_type == CSFan.Type.ELITE)
	assert_gte(elites.size(), CSGame.SECTION_RULES["drop"]["burst"].size(), "the drop drops superfans")
	assert_eq(game.conductor.current_section()["kind"], "drop")

func test_boss_arrives_at_boss_section():
	var start := 0
	for s in game.conductor.sections:
		if s["kind"] == "boss":
			start = s["start"]
	_to_beat(start - 1)
	assert_null(game.boss)
	_to_beat(start)
	assert_not_null(game.boss, "the DJ steps up when the boss drop hits")

# --- Player: Hype Blast, Lift ---------------------------------------------------

## Tap at the given beats (song-time), through the real game input path.
func _tap_beats(beats: Array) -> String:
	var last := ""
	for b in beats:
		game.conductor.song_time = b * _spb()
		last = game.try_hype_blast()
	return last

func test_steady_rhythm_builds_groove_and_combo():
	_clear_fans()
	_tap_beats([4, 5, 6, 7, 8, 9])
	assert_gt(game.groove.groove(), 0.9, "steady quarter notes = full groove")
	assert_gt(game.player.combo, 0, "combo builds while locked in")

func test_mashing_has_low_groove():
	_clear_fans()
	_tap_beats([4.0, 4.37, 4.61, 5.13, 5.3, 5.82, 6.05, 6.71])
	assert_lt(game.groove.groove(), 0.5, "random mashing doesn't groove")
	assert_eq(game.player.combo, 0)

func test_fast_inputs_ignored_below_a_sixteenth():
	_tap_beats([4.0])
	game.conductor.song_time = 4.05 * _spb()
	assert_eq(game.try_hype_blast(), "", "inputs faster than a 16th don't count")

func test_in_time_blast_converts_nearby_fan():
	_clear_fans()
	_tap_beats([4, 5, 6])
	var f: CSFan = game.spawn_fan(CSFan.Type.FAN, game.player.position + Vector2(0, -100))
	_tap_beats([7])
	assert_true(f.is_converted)

func test_double_time_in_time_is_freaking_out():
	_clear_fans()
	var beats := []
	for i in 12:
		beats.append(8.0 + i * 0.25)
	assert_eq(_tap_beats(beats), "FREAKING OUT", "in-time 16ths get the freak-out tier")
	assert_eq(game.groove.subdivision(), 4)

func test_double_time_hits_harder_per_beat_than_quarters():
	var q := pow(1.0, -CSPlayer.FAST_SPLIT) * 1.0
	var sixteenth := pow(4.0, -CSPlayer.FAST_SPLIT) * 4.0
	assert_gt(sixteenth, q * 1.5, "4 in-time taps per beat out-hype 1")

func test_grab_costs_lift_then_invuln():
	_clear_fans()
	var f: CSFan = game.spawn_fan(CSFan.Type.FAN, game.player.position)
	f.set_process(false)
	game._check_contacts()
	assert_eq(game.player.lift, CSPlayer.MAX_LIFT - f.grab_cost)
	var f2: CSFan = game.spawn_fan(CSFan.Type.FAN, game.player.position)
	f2.set_process(false)
	game._check_contacts()
	assert_eq(game.player.lift, CSPlayer.MAX_LIFT - f.grab_cost, "invulnerable right after a grab")

func test_dancers_give_lift():
	_clear_fans()
	game.player.lift = 50.0
	var f: CSFan = game.spawn_fan(CSFan.Type.FAN, game.player.position)
	f.set_process(false)
	f.win_over(99.0, "blast")
	game._check_contacts()
	assert_eq(game.player.lift, 50.0 + CSGame.LIFT_PER_DANCER)

func test_carl_sighting():
	_clear_fans()
	var f: CSFan = game.spawn_fan(CSFan.Type.CARL, game.player.position)
	f.set_process(false)
	game._check_contacts()
	assert_eq(game.carl_sightings, 1)

func test_lift_zero_ends_run():
	game.player.lift = 0.0
	await wait_process_frames(1)
	assert_true(game.over)
	assert_false(game.won)

# --- Boss -------------------------------------------------------------------------

func test_boss_phases_and_win():
	var b := CSBoss.new()
	add_child_autofree(b)
	b._arrive = 1.0
	watch_signals(b)
	b.win_over(1000.0, "glowstick")
	assert_true(b.defeated)
	assert_signal_emitted(b, "won_over")
	assert_signal_emitted(b, "phase_changed")

func test_boss_ring_hits_player_on_the_band():
	var b := CSBoss.new()
	add_child_autofree(b)
	b._arrive = 1.0
	b.position = Vector2.ZERO
	b.rings = [{"r": 200.0, "gap": 0.0}]   # opening points right
	assert_gt(b.hit_test(Vector2(0, 200), 14.0), 0.0, "on the ring")
	assert_eq(b.hit_test(Vector2(0, 100), 14.0), 0.0, "inside the ring is safe")
	assert_eq(b.hit_test(Vector2(200, 0), 14.0), 0.0, "surfing through the opening is safe")

func test_song_end_with_boss_won_is_victory():
	game._spawn_boss()
	game.boss._arrive = 1.0
	game.boss.win_over(9999.0, "blast")
	game._on_song_finished()
	assert_true(game.over)
	assert_true(game.won)

# --- Goal clarity -------------------------------------------------------------

func test_dj_won_over_progress():
	assert_eq(game.dj_won_over(), 0.0, "nothing to show before the DJ arrives")
	game._spawn_boss()
	game.boss._arrive = 1.0
	game.boss.win_over(10.0, "glowstick")
	assert_gt(game.dj_won_over(), 0.0)
	assert_lt(game.dj_won_over(), 1.0)

func test_distant_in_groove_blast_cheers_the_dj():
	game._spawn_boss()
	game.boss._arrive = 1.0
	_tap_beats([4, 5, 6, 7])   # player is far from the booth
	assert_gt(game.dj_won_over(), 0.0, "cheer wave reaches the stage")

func test_results_explain_how_close_you_got():
	game._spawn_boss()
	game.boss._arrive = 1.0
	game.boss.win_over(30.0, "glowstick")
	game._on_song_finished()
	assert_false(game.won)
	assert_string_contains(game._ui["res_title"].text, "wasn't won over")
	assert_string_contains(game._ui["res_body"].text, "%d%% won over" % int(game.dj_won_over() * 100.0))

# --- Mouse controls -----------------------------------------------------------

func test_surfer_chases_cursor_at_capped_speed():
	var p := game.player
	p.position = Vector2(640, 600)
	p.use_mouse = true
	p.mouse_target = Vector2(640, 300)
	p._process(0.1)
	assert_almost_eq(p.position.y, 600.0 - CSPlayer.MOUSE_SPEED * 0.1, 0.01, "moves toward the cursor, capped")
	p._process(10.0)
	assert_almost_eq(p.position.y, 300.0, 0.01, "arrives and stops on the cursor")
	p.mouse_target = Vector2(640, 50)
	p._process(10.0)
	assert_almost_eq(p.position.y, p.field.position.y + 180.0, 0.01, "still kept out of the stage area")

func test_mouse_motion_steers_the_reticle_from_the_surfer():
	var p := game.player
	p.use_mouse = false
	p.position = Vector2(640, 600)
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(30, -40)
	p._input(ev)
	assert_true(p.use_mouse, "mouse motion switches to mouse steering")
	assert_eq(p.mouse_target, Vector2(670, 560), "reticle starts at the surfer and moves by the delta")
	ev.relative = Vector2(5000, 0)
	p._input(ev)
	assert_eq(p.mouse_target.x, p.field.end.x - CSPlayer.RADIUS, "reticle stays inside the playfield")

func test_glowsticks_aim_at_the_dj_during_the_boss():
	assert_eq(game.player.throw_dir(), Vector2.UP)
	game._spawn_boss()
	game.boss._arrive = 1.0
	game.player.position = Vector2(400, 600)
	var d := game.player.throw_dir()
	assert_almost_eq(d.angle(), game.player.position.direction_to(game.boss.position).angle(), 0.001)

func test_ring_openings_stay_near_the_middle():
	var b := CSBoss.new()
	add_child_autofree(b)
	b._arrive = 1.0
	for i in 200:
		b.on_beat(i * 4, Vector2.ZERO)
	for ring in b.rings:
		assert_lt(abs(angle_difference(ring["gap"], PI / 2.0)), CSBoss.GAP_RANGE + 0.001)

func test_click_triggers_hype_blast():
	game.conductor.song_time = 4.0 * _spb()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	game._unhandled_input(ev)
	assert_eq(game.blasts, 1, "left click is the Hype Blast")


# --- Groove engine ----------------------------------------------------------------

func _groove(spb := 0.5) -> CSGroove:
	var g := CSGroove.new()
	g.setup(spb)
	g.max_sub = 4
	return g

func test_groove_needs_a_few_inputs():
	var g := _groove()
	g.record(0.0)
	g.record(0.5)
	assert_eq(g.groove(), 0.0)
	g.record(1.0)
	assert_gt(g.groove(), 0.9)

func test_constant_lateness_does_not_hurt_groove():
	var g := _groove()
	for i in 8:
		g.record(i * 0.5 + 0.09)   # always 90 ms late (e.g. shake-detection lag)
	assert_gt(g.groove(), 0.95, "consistent lateness still grooves")
	assert_almost_eq(g.offset(), 0.09, 0.005, "and the lateness is measured")

func test_jitter_lowers_groove():
	var g := _groove()
	var jitter := [0.0, 0.11, -0.09, 0.13, -0.12, 0.08, -0.1, 0.12]
	for i in 8:
		g.record(i * 0.5 + jitter[i])
	assert_lt(g.groove(), 0.85)

func test_subdivision_detected_from_pace():
	var g := _groove()
	for i in 8:
		g.record(i * 0.25)
	assert_eq(g.subdivision(), 2, "8th notes")
	g.reset()
	for i in 12:
		g.record(i * 0.125)
	assert_eq(g.subdivision(), 4, "16th notes")

func test_groove_fades_when_you_stop():
	var g := _groove()
	for i in 6:
		g.record(i * 0.5)
	assert_gt(g.groove(2.6), 0.9, "still grooving right after")
	assert_eq(g.groove(2.5 + 5.0), 0.0, "gone after a few silent beats")
