extends CharacterBody3D
class_name TDEnemy

## A tower-defense creep: walks an ordered list of waypoints from spawn to goal.
## Reuses the shared Health component. Reaching the goal costs the player a life;
## dying to towers pays out currency. The game controller wires up the signals.

signal reached_goal(enemy: TDEnemy)
signal killed(enemy: TDEnemy)

@export var speed: float = 3.5
@export var bounty: int = 5          ## currency paid when killed by a tower
@export var leak_damage: int = 1     ## lives lost if it reaches the goal

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh

var _path: PackedVector3Array = PackedVector3Array()
var _target_idx: int = 0
var _dead: bool = false
var _material: StandardMaterial3D
var _base_color: Color = Color(0.85, 0.4, 0.4)

func _ready() -> void:
	health.died.connect(_on_died)
	# Own material instance so a hit flash on one creep doesn't affect others.
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material_override = _material

## Called by the spawner before adding to the scene.
func set_path(points: PackedVector3Array) -> void:
	_path = points
	if _path.size() > 0:
		global_position = _path[0]
		_target_idx = 1

func _physics_process(delta: float) -> void:
	if _dead or _target_idx >= _path.size():
		return
	var target: Vector3 = _path[_target_idx]
	var to: Vector3 = target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= 0.1:
		_target_idx += 1
		if _target_idx >= _path.size():
			_leak()
		return
	var step := to.normalized() * speed * delta
	if step.length() >= dist:
		global_position = Vector3(target.x, global_position.y, target.z)
	else:
		global_position += step
	# Face travel direction (cosmetic).
	if to.length() > 0.05:
		look_at(global_position + to.normalized(), Vector3.UP)

func take_damage(amount: float) -> void:
	if _dead:
		return
	health.take_damage(amount)
	_flash()

func _flash() -> void:
	_material.albedo_color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(_material, "albedo_color", _base_color, 0.15)

func _leak() -> void:
	if _dead:
		return
	_dead = true
	reached_goal.emit(self)
	queue_free()

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	killed.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(queue_free)
