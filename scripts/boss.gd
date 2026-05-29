extends CharacterBody3D

## Minimal boss state machine: IDLE -> CHASE -> TELEGRAPH -> ATTACK -> COOLDOWN.
## Chases the player, pauses to telegraph (color flash), lunges, then recovers.
## Uses the shared Health component and dies at 0 HP.

enum State { IDLE, CHASE, TELEGRAPH, ATTACK, COOLDOWN, DEAD }

@export var move_speed: float = 3.5
@export var detect_range: float = 14.0
@export var attack_range: float = 2.5
@export var attack_damage: float = 20.0
@export var telegraph_time: float = 0.6
@export var attack_time: float = 0.25
@export var cooldown_time: float = 1.0
@export var lunge_speed: float = 10.0
@export var gravity: float = 24.0
## When true, the boss is dormant until activate() is called (used to gate the
## fight to the end of the level). When false it wakes on player proximity.
@export var start_dormant: bool = false

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh

var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Node3D
var _lunge_dir: Vector3 = Vector3.ZERO
var _base_color: Color = Color(0.8, 0.2, 0.2)
var _active: bool = true
var _material: StandardMaterial3D

func _ready() -> void:
	health.died.connect(_on_died)
	_player = get_tree().get_first_node_in_group("player")
	# Own material instance so telegraph color changes don't leak into the shared
	# scene resource.
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material_override = _material
	_active = not start_dormant

## Wake the boss up (called by the boss-arena trigger).
func activate() -> void:
	_active = true
	if _state == State.IDLE:
		_state = State.CHASE

func _physics_process(delta: float) -> void:
	# Keep the boss grounded even while dormant.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	if not _active or _state == State.DEAD or _player == null:
		move_and_slide()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	match _state:
		State.IDLE:
			if dist <= detect_range:
				_state = State.CHASE
		State.CHASE:
			_face(to_player)
			if dist <= attack_range:
				_enter_telegraph()
			else:
				velocity.x = to_player.normalized().x * move_speed
				velocity.z = to_player.normalized().z * move_speed
		State.TELEGRAPH:
			velocity = Vector3.ZERO
			_face(to_player)
			_timer -= delta
			if _timer <= 0.0:
				_enter_attack(to_player)
		State.ATTACK:
			velocity = _lunge_dir * lunge_speed
			_timer -= delta
			if dist <= attack_range and _player.has_method("take_damage"):
				# applied once via cooldown gate below
				pass
			_try_hit_player(dist)
			if _timer <= 0.0:
				_state = State.COOLDOWN
				_timer = cooldown_time
				_set_color(_base_color)
		State.COOLDOWN:
			velocity = Vector3.ZERO
			_timer -= delta
			if _timer <= 0.0:
				_state = State.CHASE

	velocity.y = 0.0
	move_and_slide()

var _hit_landed: bool = false

func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = telegraph_time
	_hit_landed = false
	_set_color(Color(1.0, 0.85, 0.2))  # yellow wind-up

func _enter_attack(to_player: Vector3) -> void:
	_state = State.ATTACK
	_timer = attack_time
	_lunge_dir = to_player.normalized()
	_set_color(Color(1.0, 0.3, 0.3))

func _try_hit_player(dist: float) -> void:
	if _hit_landed:
		return
	if dist <= attack_range + 0.5:
		var ph := _player.get_node_or_null("Health")
		if ph and ph.has_method("take_damage"):
			ph.take_damage(attack_damage)
			_hit_landed = true

func _face(dir: Vector3) -> void:
	if dir.length() > 0.05:
		look_at(global_position + dir.normalized(), Vector3.UP)

func _set_color(c: Color) -> void:
	if _material:
		_material.albedo_color = c

func _on_died() -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	_set_color(Color(0.3, 0.3, 0.3))
	set_physics_process(false)
	# Sink into the floor as a cheap death tell, then remove.
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 2.0, 0.8)
	tween.tween_callback(queue_free)
