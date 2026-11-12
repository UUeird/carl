extends SceneTree

## Screenshot helper for the UI screens (map picker and in-game HUD).
## Run headed (NOT --headless) so it renders:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script test/shot_ui.gd -- picker /tmp/picker.png [1280x720]
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --script test/shot_ui.gd -- hud /tmp/hud.png [1920x1080]
##
## `hud` loads the main map, builds a tower and selects it so the tower panel
## (with the element picker) shows. The optional size sets the window size, to
## check the layout holds at other resolutions.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "hud"
	var out_path: String = args[1] if args.size() > 1 else "/tmp/carl_%s.png" % mode
	if args.size() > 2:
		var wh := args[2].split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))

	var path := "res://scenes/map_picker.tscn" if mode == "picker" else "res://scenes/td_main.tscn"
	var scene: Node = (load(path) as PackedScene).instantiate()
	get_root().add_child(scene)
	current_scene = scene
	for _f in 3:
		await process_frame

	if mode == "hud":
		var slot = scene.get_node("Slots").get_child(0)
		scene.try_build(slot, 0)   # MACHINE_GUN; no TDTower ref (autoloads not loaded yet at compile)
		scene._select_slot(slot)

	for _f in 20:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(out_path)
	print("SAVED ", out_path, " at ", DisplayServer.window_get_size())
	quit()
