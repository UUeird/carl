extends Label3D
class_name DamageNumber

## A small white number that pops at a hit, drifts upward, and fades out.
## Spawned via the static popup() helper so callers don't need the scene path.

const RISE := 1.2
const LIFE := 0.7

var _t: float = 0.0

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true                 # always readable, even behind geometry
	modulate = Color.WHITE
	outline_modulate = Color(0, 0, 0, 0.8)
	outline_size = 6
	font_size = 48
	pixel_size = 0.012

func _process(delta: float) -> void:
	_t += delta
	position.y += RISE * delta
	modulate.a = clampf(1.0 - _t / LIFE, 0.0, 1.0)
	if _t >= LIFE:
		queue_free()

## Spawn a damage number at a world position, parented to the current scene.
static func popup(scene_root: Node, world_pos: Vector3, amount: int) -> void:
	var dn := DamageNumber.new()
	dn.text = str(amount)
	scene_root.add_child(dn)
	dn.global_position = world_pos
