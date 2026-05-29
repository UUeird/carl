extends StaticBody3D

## Training dummy: a damageable target with hit feedback. Forwards damage to its
## Health child and flashes/squashes on hit so attacks read clearly.

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh

var _base_scale: Vector3

func _ready() -> void:
	_base_scale = mesh.scale
	health.died.connect(_on_died)

## combat.gd / projectiles call take_damage directly on the body.
func take_damage(amount: float) -> void:
	health.take_damage(amount)
	_flash()

func _flash() -> void:
	var mat := _ensure_material()
	if mat:
		mat.albedo_color = Color(1.0, 1.0, 1.0)
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", Color(0.4, 0.6, 0.9), 0.15)
	# Squash-and-stretch pop.
	mesh.scale = _base_scale * Vector3(1.15, 0.85, 1.15)
	var st := create_tween()
	st.tween_property(mesh, "scale", _base_scale, 0.18).set_trans(Tween.TRANS_BACK)

func _ensure_material() -> StandardMaterial3D:
	var mat := mesh.get_active_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.6, 0.9)
		mesh.material_override = mat
	return mat if mat is StandardMaterial3D else null

func _on_died() -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", deg_to_rad(85.0), 0.4)  # topple over
