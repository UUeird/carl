extends SceneTree

## Headless difficulty probe for the crowd-surf prototype. Plays the whole song
## on the manual clock with a simple bot and prints Lift per section, so tuning
## SECTION_RULES / fan stats can be checked with numbers, not just feel.
##
##   godot --headless --path . --script test/sim_crowd_surf.gd -- [skill] [runs]
##
## skill: 0..1 — chance each beat the bot lands a Hype Blast on time (else it
## mistimes it), and how well it steers away from the closest grabby fan.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var skill: float = float(args[0]) if args.size() > 0 else 0.5
	var runs: int = int(args[1]) if args.size() > 1 else 5
	var deaths := 0
	for r in runs:
		seed(r + 1)
		var scene: Node = (load("res://scenes/cs_main.tscn") as PackedScene).instantiate()
		scene.use_audio = false
		get_root().add_child(scene)
		await process_frame
		var c = scene.conductor
		var spb: float = c.seconds_per_beat()
		var dt := 1.0 / 60.0
		var last_beat := -1
		var last_kind := ""
		var next_tap := 0.06
		var line := "run %d:" % r
		while not scene.over:
			c.advance(dt)
			var bp: float = c.beat_pos()
			# Steer: dodge the nearest unconverted fan ahead, with skill-scaled reaction.
			var p: Vector2 = scene.player.position
			var push := 0.0
			for f in CSFan.all_fans:
				if is_instance_valid(f) and not f.is_converted and not f.is_carl:
					var d: Vector2 = f.position - p
					if d.y < 0 and d.y > -160 and abs(d.x) < 70:
						push -= sign(d.x if d.x != 0 else 1.0) * (70 - abs(d.x))
			# Ring openings: steer toward where the next incoming ring's gap crosses our row.
			var boss = scene.boss
			if is_instance_valid(boss) and not boss.defeated:
				var d_boss: float = p.distance_to(boss.position)
				var best = null
				for ring in boss.rings:
					if ring["r"] < d_boss + 10.0 and (best == null or ring["r"] > best["r"]):
						best = ring
				if best != null and randf() < skill:
					var gx: float = boss.position.x + (p.y - boss.position.y) / tan(best["gap"])
					push += (gx - p.x) * 2.0
			p.x += clamp(push * skill * 0.4, -380 * dt, 380 * dt)
			scene.player.position = p
			# Rhythm: tap on a grid with timing wobble σ = (1-skill)·0.12s and a
			# constant 60 ms lateness (which groove shouldn't punish). Skilled bots
			# go double-time in builds/drops/boss, like a player freaking out.
			var kind: String = c.current_section().get("kind", "")
			var pace := 1
			if kind in ["build", "drop", "boss"]:
				pace = 4 if skill >= 0.8 else (2 if skill >= 0.5 else 1)
			if c.song_time >= next_tap:
				var saved: float = c.song_time
				c.song_time = next_tap
				scene.try_hype_blast()
				c.song_time = saved
				var step: float = spb / pace
				var grid: float = (floor((next_tap - 0.06) / step + 0.5) + 1.0) * step
				next_tap = grid + 0.06 + randfn(0.0, (1.0 - skill) * 0.12)
				next_tap = max(next_tap, c.song_time + spb * 0.2)
			if int(bp) != last_beat:
				last_beat = int(bp)
				if kind != last_kind:
					line += "  %s@%d" % [kind, int(scene.player.lift)]
					last_kind = kind
			scene._process(dt)
			for f in CSFan.all_fans.duplicate():
				if is_instance_valid(f):
					f._process(dt)
			for g in CSGlowstick.active.duplicate():
				if is_instance_valid(g):
					g._process(dt)
			if is_instance_valid(scene.boss):
				scene.boss._process(dt)
			scene.player._process(dt)
		var died: bool = scene.player.lift <= 0.0
		line += "  groove=%d%%" % int(scene.avg_groove() * 100.0)
		if died:
			deaths += 1
		print(line, "  -> ", "DIED at beat %d (%s)" % [int(c.beat_pos()), c.current_section().get("name", "")] if died else "survived lift=%d won=%s" % [int(scene.player.lift), scene.won])
		scene.queue_free()
		await process_frame
		for f in CSFan.all_fans.duplicate():
			if is_instance_valid(f):
				f.free()
	print("skill %.2f: %d/%d deaths" % [skill, deaths, runs])
	quit()
