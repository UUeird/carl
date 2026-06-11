extends Label3D
class_name DamageNumber

## A small white number that pops at a hit, drifts upward, and fades out.
## Uses a static free-list pool to avoid per-hit alloc + add_child cost.
##
## acquire() pins a node in place (no drift/fade) so the caller can update its
## text each frame as damage accumulates; release() lets it drift and fade.

const RISE := 1.2
const LIFE := 0.7
const POOL_SIZE := 24

static var _pool: Array = []
static var _root_ref: Node = null

var _t: float = 0.0
var _pinned: bool = false   ## true while held by beam tower; suppresses drift/fade

func _setup() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	modulate = Color.WHITE
	outline_modulate = Color(0, 0, 0, 0.8)
	outline_size = 6
	font_size = 48
	pixel_size = 0.00045
	set_process(false)  # idle until activated

func _process(delta: float) -> void:
	if _pinned:
		return
	_t += delta
	position.y += RISE * delta
	modulate.a = clampf(1.0 - _t / LIFE, 0.0, 1.0)
	if _t >= LIFE:
		_return_to_pool()

func _return_to_pool() -> void:
	set_process(false)
	visible = false
	_pinned = false
	_pool.append(self)

## Pre-allocate pool nodes under the given scene root. Call once at startup.
static func prewarm(scene_root: Node) -> void:
	_root_ref = scene_root
	for i in POOL_SIZE:
		var dn := DamageNumber.new()
		dn._setup()
		dn.visible = false
		scene_root.add_child(dn)
		_pool.append(dn)

## Grab a node from the pool and pin it — no drift or fade until release().
## The caller must call release() or the node leaks from the pool permanently.
static func acquire(scene_root: Node, world_pos: Vector3) -> DamageNumber:
	if scene_root == null or not scene_root.is_inside_tree():
		return null
	var dn: DamageNumber
	if _pool.size() > 0:
		dn = _pool.pop_back()
	else:
		dn = DamageNumber.new()
		dn._setup()
		scene_root.add_child(dn)
	dn.text = ""
	dn._t = 0.0
	dn._pinned = true
	dn.visible = true
	dn.set_process(true)
	dn.modulate = Color.WHITE
	dn.global_position = world_pos
	return dn

## Unpin a node acquired via acquire() and let it drift and fade normally.
static func release(dn: DamageNumber) -> void:
	if dn == null:
		return
	dn._pinned = false
	dn._t = 0.0
