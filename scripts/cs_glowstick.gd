extends Node2D
class_name CSGlowstick

## A thrown glowstick. The player tosses these automatically on every eighth
## note, so your fire rate *is* the song's rhythm. Pooled (static free-list +
## prewarm) because they spawn constantly — never allocate one per throw.

const SPEED := 900.0
const POWER := 1.0
const HIT_PAD := 6.0
const COLORS := [Color("#B6F23A"), Color("#5FE1FF"), Color("#FF5FA2")]

static var _free: Array = []             ## untyped: self-typed static arrays break the parser
static var active: Array = []
static var field_top: float = -40.0

var velocity: Vector2 = Vector2.ZERO
var power: float = POWER
var _color: Color = COLORS[0]
var _spin: float = 0.0

## Fill the pool up front so the first throws don't allocate.
static func prewarm(parent: Node, count: int = 48) -> void:
	for i in count:
		var g := CSGlowstick.new()
		g.visible = false
		g.set_process(false)
		parent.add_child(g)
		_free.append(g)

static func throw(parent: Node, pos: Vector2, vel: Vector2, pwr: float = POWER) -> CSGlowstick:
	var g: CSGlowstick = null
	while not _free.is_empty() and g == null:
		var cand = _free.pop_back()
		if is_instance_valid(cand):
			g = cand
	if g == null:
		g = CSGlowstick.new()
		parent.add_child(g)
	g.position = pos
	g.velocity = vel
	g.power = pwr
	g._color = COLORS[randi() % COLORS.size()]
	g._spin = randf() * TAU
	g.visible = true
	g.set_process(true)
	active.append(g)
	return g

static func reset_pool() -> void:
	_free.clear()
	active.clear()

func _exit_tree() -> void:
	active.erase(self)
	_free.erase(self)

func _release() -> void:
	visible = false
	set_process(false)
	active.erase(self)
	_free.append(self)

func _process(delta: float) -> void:
	position += velocity * delta
	_spin += delta * 18.0
	rotation = _spin
	if position.y < field_top:
		_release()
		return
	for f in CSFan.all_fans:
		if not is_instance_valid(f) or f.is_converted or f.is_carl:
			continue
		if position.distance_to(f.position) < f.radius + HIT_PAD:
			f.win_over(power, "glowstick")
			_release()
			return
	var boss = CSBoss.active
	if is_instance_valid(boss) and boss.hittable() and position.distance_to(boss.position) < boss.RADIUS:
		boss.win_over(power, "glowstick")
		_release()

func _draw() -> void:
	draw_line(Vector2(0, -9), Vector2(0, 9), _color.lightened(0.3), 4.0)
	draw_line(Vector2(0, -9), Vector2(0, 9), Color(_color, 0.35), 10.0)
