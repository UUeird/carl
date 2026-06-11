extends SceneTree

## Screenshot helper for the straight test map (scenes/td_test_map.tscn).
##
## Loads the test map, builds one of each tower type on its pads, spawns an enemy
## so turrets aim and fire, then saves a PNG. Run headed (the editor's Godot, NOT
## --headless) so it actually renders:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script test/shot_test_map.gd -- /tmp/shot.png
##
## The optional trailing arg after `--` is the output path (default /tmp/td_test_map.png).
## The map's camera is positioned head-on, so towers frame cleanly without fiddling.

func _initialize() -> void:
	var out_path := "/tmp/td_test_map.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]

	var map: PackedScene = load("res://scenes/td_test_map.tscn")
	var game = map.instantiate()
	get_root().add_child(game)
	current_scene = game
	await process_frame
	await process_frame

	# Build one of each tower type across the pads (slots are named Slot0..Slot7),
	# cycling through the types if there are more pads than types.
	var types := [TDTower.Type.MACHINE_GUN, TDTower.Type.BEAM, TDTower.Type.MISSILE]
	var slots = game.get_node("Slots")
	var i := 0
	for slot in slots.get_children():
		game.try_build(slot, types[i % types.size()])
		i += 1

	# Spawn an enemy ahead of the towers (further along the path, +X) so every
	# turret aims roughly along +X — across the camera's view, not away from it —
	# which shows each barrel/emitter in profile.
	var enemy_scene: PackedScene = load("res://scenes/td_enemy.tscn")
	var e = enemy_scene.instantiate()
	game.add_child(e)
	e.set_path(PackedVector3Array([Vector3(-30, 0, 0), Vector3(30, 0, 0)]))
	e.global_position = Vector3(26, 0, 0)
	e._target_idx = 1

	# Let turrets swing onto the target and effects settle.
	for _f in 50:
		await process_frame

	get_root().get_viewport().get_texture().get_image().save_png(out_path)
	print("SAVED ", out_path)
	quit()
