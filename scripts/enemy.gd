extends CharacterBody3D

## Small chaser enemy. Trimmed cousin of the boss: detects the player, chases,
## and deals contact damage on a cooldown. Reuses the shared Health component.
## No telegraph/lunge — these are meant to be numerous and quick to clear.

@export var move_speed: float = 4.5
@export var detect_range: float = 12.0
@export var attack_range: float = 1.8
@export var contact_damage: float = 8.0
@export var attack_cooldown: float = 0.8
@export var gravity: float = 24.0

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh

var _player: Node3D
var _cooldown: float = 0.0
var _dead: bool = false
var _material: StandardMaterial3D
var _base_color: Color = Color(0.7, 0.35, 0.7)

func _ready() -> void:
	health.died.connect(_on_died)
	_player = get_tree().get_first_node_in_group("player")
	# Give this enemy its OWN material instance — otherwise all enemies share the
	# scene's material and flashing one would flash them all.
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material_override = _material

func take_damage(amount: float) -> void:
	# Projectiles/melee call the body directly; forward to Health + flash.
	health.take_damage(amount)
	_flash()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _player == null:
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	_cooldown = max(_cooldown - delta, 0.0)

	if dist <= detect_range and dist > attack_range:
		var dir := to_player.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if dist <= attack_range and _cooldown <= 0.0:
			_hit_player()
			_cooldown = attack_cooldown

	move_and_slide()

func _hit_player() -> void:
	var ph := _player.get_node_or_null("Health")
	if ph and ph.has_method("take_damage"):
		ph.take_damage(contact_damage)
	_flash(Color(1, 0.6, 0.2))

func _flash(c: Color = Color.WHITE) -> void:
	_material.albedo_color = c
	var tw := create_tween()
	tw.tween_property(_material, "albedo_color", _base_color, 0.15)

func _on_died() -> void:
	_dead = true
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(queue_free)
