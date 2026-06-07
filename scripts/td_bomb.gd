extends Node3D
class_name TDBomb

## A lobbed bomb. Fired toward a FIXED ground point (computed at launch from the
## target's current velocity), it arcs through the air and, on landing, deals
## area-of-effect damage with linear falloff from the center. The landing point
## never updates after launch, so enemies that turn off their predicted line are
## missed — that's the bomb tower's intended weakness.

@onready var mesh: MeshInstance3D = $Mesh

var _from: Vector3
var _to: Vector3
var _damage: float = 0.0
var _aoe: float = 2.0
var _t: float = 0.0
var _flight: float = 1.0
var _arc_height: float = 3.0
var _exploded: bool = false

func launch_bomb(from: Vector3, to: Vector3, speed: float, damage: float, aoe: float) -> void:
	_from = from
	_to = to
	_damage = damage
	_aoe = aoe
	var ground := Vector2(to.x - from.x, to.z - from.z).length()
	_flight = max(ground / max(speed, 0.01), 0.25)
	# Higher arc for longer lobs, so it visibly goes "up in the air".
	_arc_height = clampf(ground * 0.4, 1.5, 5.0)
	global_position = from

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_t += delta / _flight
	if _t >= 1.0:
		global_position = _to
		_explode()
		return
	# Lerp along the ground, add a parabolic vertical arc (0 at ends, peak mid).
	var pos := _from.lerp(_to, _t)
	pos.y += _arc_height * 4.0 * _t * (1.0 - _t)
	global_position = pos

func _explode() -> void:
	_exploded = true
	# Damage every enemy within the blast, scaled by distance (full at center).
	for e in get_tree().get_nodes_in_group("td_enemy"):
		if not is_instance_valid(e):
			continue
		var d := _to.distance_to(e.global_position)
		if d <= _aoe and e.has_method("take_damage"):
			var falloff := 1.0 - (d / _aoe) * 0.6   # edge still deals 40%
			e.take_damage(_damage * falloff)
	_spawn_blast()
	queue_free()

func _spawn_blast() -> void:
	# A quick expanding translucent ring so the AoE reads.
	var ring := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	ring.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.4)
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = _to
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * _aoe, 0.25)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(ring.queue_free)
