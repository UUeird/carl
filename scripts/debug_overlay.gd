extends CanvasLayer

## Lightweight performance/debug overlay (bottom-left). Shows FPS + frame time,
## object/node/orphan counts, render draw-calls/primitives, and game-specific live
## entity counts. Only visible in debug builds (editor / debug export); auto-hides
## in release. Useful for diagnosing combat-time lag — watch the object/projectile
## counts during a wave to spot anything that isn't being freed.
##
## Color coding: labels are white; values are green/yellow/red by load threshold.
## Thresholds are intentionally loose — tune them as the game grows.

@onready var label: RichTextLabel = $Label

var _accum := 0.0
var _accum_frames := 0
const UPDATE_INTERVAL := 0.25

# --- Thresholds (tune as needed) -------------------------------------------
const FPS_GREEN  := 50
const FPS_YELLOW := 30

const CPU_MS_GREEN  := 10.0
const CPU_MS_YELLOW := 20.0

const PHYS_MS_GREEN  := 5.0
const PHYS_MS_YELLOW := 10.0

const ORPHANS_GREEN  := 0
const ORPHANS_YELLOW := 5

const DRAW_GREEN  := 200
const DRAW_YELLOW := 400

const PRIMS_GREEN  := 200_000
const PRIMS_YELLOW := 500_000
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	label.bbcode_enabled = true
	# Pin to bottom-left — clear of the top-left HUD stats and top-right buttons.
	# All geometry lives here so both scene files stay in sync automatically.
	label.anchor_left   = 0.0
	label.anchor_top    = 1.0
	label.anchor_right  = 0.0
	label.anchor_bottom = 1.0
	label.offset_left   = 8.0
	label.offset_top    = -130.0
	label.offset_right  = 480.0
	label.offset_bottom = -6.0
	label.fit_content   = false
	label.scroll_active = false

func _process(delta: float) -> void:
	_accum += delta
	_accum_frames += 1
	if _accum < UPDATE_INTERVAL:
		return
	label.text = _build_text()
	_accum = 0.0
	_accum_frames = 0

# Returns a BBCode hex color string for a value given two ascending thresholds.
# Below green_threshold → green, below yellow_threshold → yellow, else → red.
# higher_is_better=true reverses the sense (used for FPS).
func _col(value: float, green_thresh: float, yellow_thresh: float,
		higher_is_better: bool = false) -> String:
	var good: bool
	var warn: bool
	if higher_is_better:
		good = value >= green_thresh
		warn = value >= yellow_thresh
	else:
		good = value <= green_thresh
		warn = value <= yellow_thresh
	if good:
		return "#88dd88"
	elif warn:
		return "#ddcc55"
	else:
		return "#dd5555"

func _v(value: float, green_thresh: float, yellow_thresh: float,
		fmt: String, higher_is_better: bool = false) -> String:
	var c := _col(value, green_thresh, yellow_thresh, higher_is_better)
	return "[color=%s]" % c + fmt % value + "[/color]"

func _build_text() -> String:
	var fps      := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms  := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var objects  := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes    := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans  := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims    := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var tree := get_tree()
	var enemies     := tree.get_nodes_in_group("td_enemy").size() if tree else 0
	var projectiles := tree.get_nodes_in_group("td_projectile").size() if tree else 0

	# Per-system timings from PerfTimer — flush resets accumulators each interval.
	var perf: Dictionary = PerfTimer.flush()
	# Convert accumulated μs over the interval to average ms per frame.
	var frames := maxf(float(_accum_frames), 1.0)
	var tower_ms:      float = int(perf.get("towers",      0)) / 1000.0 / frames
	var enemy_ms:      float = int(perf.get("enemies",     0)) / 1000.0 / frames
	var hbar_ms:       float = int(perf.get("health_bars", 0)) / 1000.0 / frames
	var proj_ms:       float = int(perf.get("projectiles", 0)) / 1000.0 / frames
	var bomb_ms:       float = int(perf.get("bombs",       0)) / 1000.0 / frames
	var blast_ms:      float = int(perf.get("blast_fade",  0)) / 1000.0 / frames

	var W := "[color=#ffffff]"
	var E := "[/color]"

	return (
		W + "fps " + E + _v(fps, FPS_GREEN, FPS_YELLOW, "%d", true)
		+ W + "  cpu " + E + _v(frame_ms, CPU_MS_GREEN, CPU_MS_YELLOW, "%.1f ms")
		+ W + "  phys " + E + _v(phys_ms, PHYS_MS_GREEN, PHYS_MS_YELLOW, "%.1f ms") + "\n"
		+ W + "objects " + E + _v(objects, 9999, 9999, "%d")
		+ W + "  nodes " + E + _v(nodes, 9999, 9999, "%d")
		+ W + "  orphans " + E + _v(orphans, ORPHANS_GREEN, ORPHANS_YELLOW, "%d") + "\n"
		+ W + "draw calls " + E + _v(draw_calls, DRAW_GREEN, DRAW_YELLOW, "%d")
		+ W + "  prims " + E + _v(prims, PRIMS_GREEN, PRIMS_YELLOW, "%d") + "\n"
		+ W + "enemies " + E + _v(enemies, 9999, 9999, "%d")
		+ W + "  projectiles " + E + _v(projectiles, 9999, 9999, "%d") + "\n"
		+ W + "towers " + E + _v(tower_ms, 1.0, 3.0, "%.2f ms")
		+ W + "  enemies " + E + _v(enemy_ms, 1.0, 3.0, "%.2f ms")
		+ W + "  hbars " + E + _v(hbar_ms, 0.5, 1.5, "%.2f ms") + "\n"
		+ W + "proj " + E + _v(proj_ms, 0.5, 2.0, "%.2f ms")
		+ W + "  bombs " + E + _v(bomb_ms, 0.5, 2.0, "%.2f ms")
		+ W + "  blast " + E + _v(blast_ms, 0.1, 0.5, "%.2f ms")
	)
