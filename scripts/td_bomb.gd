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

static var _blast_mat: StandardMaterial3D = null
static var _blast_mesh: SphereMesh = null

func _ready() -> void:
	if _blast_mat == null:
		_blast_mat = StandardMaterial3D.new()
		_blast_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blast_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blast_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.4)
	if _blast_mesh == null:
		_blast_mesh = SphereMesh.new()
		_blast_mesh.radius = 1.0
		_blast_mesh.height = 2.0

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
	for e in TDEnemy.all_enemies:
		if not is_instance_valid(e):
			continue
		var d := _to.distance_to(e.global_position)
		if d <= _aoe and e.has_method("take_damage"):
			var falloff := 1.0 - (d / _aoe) * 0.6   # edge still deals 40%
			e.take_damage(_damage * falloff)
	_spawn_blast()
	queue_free()

func _spawn_blast() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	ring.mesh = _blast_mesh
	var mat: StandardMaterial3D = _blast_mat.duplicate()
	ring.material_override = mat
	scene.add_child(ring)
	ring.global_position = _to
	ring.scale = Vector3.ONE * 0.3
	# Timer-driven fade: a small helper node ticks the expand/fade each frame
	# instead of a tween, avoiding per-explosion material property animation overhead.
	var helper := _BlastFade.new(ring, mat, _aoe)
	scene.add_child(helper)

class _BlastFade extends Node:
	const DURATION := 0.25
	var _ring: MeshInstance3D
	var _mat: StandardMaterial3D
	var _target_scale: float
	var _elapsed: float = 0.0

	func _init(ring: MeshInstance3D, mat: StandardMaterial3D, aoe: float) -> void:
		_ring = ring
		_mat = mat
		_target_scale = aoe

	func _process(delta: float) -> void:
		_elapsed += delta
		var f := minf(_elapsed / DURATION, 1.0)
		if is_instance_valid(_ring):
			_ring.scale = Vector3.ONE * lerpf(0.3, _target_scale, f)
		_mat.albedo_color.a = lerpf(0.4, 0.0, f)
		if f >= 1.0:
			if is_instance_valid(_ring):
				_ring.queue_free()
			queue_free()
