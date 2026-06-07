extends CanvasLayer

## Lightweight performance/debug overlay (bottom-left). Shows FPS + frame time,
## object/node/orphan counts, render draw-calls/primitives, and game-specific live
## entity counts. Only visible in debug builds (editor / debug export); auto-hides
## in release. Useful for diagnosing combat-time lag — watch the object/projectile
## counts during a wave to spot anything that isn't being freed.

@onready var label: Label = $Label

var _accum := 0.0
const UPDATE_INTERVAL := 0.25   # refresh 4x/sec so the text is readable, not a blur

func _ready() -> void:
	# Hide entirely outside debug builds so it never ships in a release.
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep updating even if the game pauses

func _process(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	label.text = _build_text()

func _build_text() -> String:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var tree := get_tree()
	var enemies := tree.get_nodes_in_group("td_enemy").size() if tree else 0
	var projectiles := tree.get_nodes_in_group("td_projectile").size() if tree else 0

	return "FPS %d  (%.1f ms cpu / %.1f ms phys)\n" % [fps, frame_ms, phys_ms] \
		+ "objects %d   nodes %d   orphans %d\n" % [objects, nodes, orphans] \
		+ "draw calls %d   prims %d\n" % [draw_calls, prims] \
		+ "enemies %d   projectiles %d" % [enemies, projectiles]
