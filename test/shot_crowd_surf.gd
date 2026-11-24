extends SceneTree

## Screenshot helper for the "Find Carl" crowd-surf prototype. Run headed
## (NOT --headless) so it renders:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script test/shot_crowd_surf.gd -- <beat> /tmp/cs.png
##
## Plays the level silently on the manual clock from 12 beats before <beat> up
## to <beat>, with a scripted surfer that weaves and Hype Blasts on the beat, so
## the crowd, conversions, drops and boss attacks are all in frame. Pass
## `results` instead of a beat to capture the end-of-song screen, or `picker`
## for the map picker. Add a third
## arg `mouse` to show the mouse-steering reticle.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var target: String = args[0] if args.size() > 0 else "70"
	var out_path: String = args[1] if args.size() > 1 else "/tmp/carl_cs.png"

	if target == "picker":
		var picker: Node = (load("res://scenes/map_picker.tscn") as PackedScene).instantiate()
		get_root().add_child(picker)
		for _f in 10:
			await process_frame
		get_root().get_viewport().get_texture().get_image().save_png(out_path)
		print("SAVED ", out_path)
		quit()
		return
	var scene: Node = (load("res://scenes/cs_main.tscn") as PackedScene).instantiate()
	scene.use_audio = false
	get_root().add_child(scene)
	current_scene = scene
	await process_frame

	var c = scene.conductor
	var spb: float = c.seconds_per_beat()
	if target == "results":
		scene._spawn_boss()
		c.advance(c.length_beats * spb + 0.01)
	else:
		var b := float(target)
		c.advance(max(b - 12.0, 0.0) * spb)   # skip ahead (spawns fire, crowd hasn't moved)
		for f in scene.get_children():
			if f.has_method("win_over") and f.get("is_carl") != null:
				f.queue_free()
		await process_frame
		var dt := 1.0 / 60.0
		var last_beat := -1
		while c.beat_pos() < b:
			c.advance(dt)
			var bp: float = c.beat_pos()
			scene.player.position.x = 640.0 + sin(c.song_time * 1.3) * 200.0
			# Tap quarters normally, 16ths in builds/drops/boss (the "freak-out").
			var kind: String = c.current_section().get("kind", "")
			var per_beat := 4 if kind in ["build", "drop", "boss"] else 1
			var slot := int(floor(bp * per_beat))
			if slot != last_beat:
				last_beat = slot
				scene.try_hype_blast()
			await process_frame
	if args.size() > 2 and args[2] == "mouse":
		# Show the mouse-steering reticle: cursor up-left of the surfer.
		scene.player.use_mouse = true
		scene.player.mouse_target = scene.player.position + Vector2(-140, -90)
		scene.player.set_process(false)
		scene.player.queue_redraw()
	for _f in 3:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(out_path)
	print("SAVED ", out_path)
	quit()
