extends CanvasLayer

## Minimal HUD: binds to the player's and boss's Health components via signals.
## Decoupled — it never reads hp directly, only reacts to health_changed/died.

@export var player_path: NodePath
@export var boss_path: NodePath

@onready var player_bar: ProgressBar = $Root/PlayerBar
@onready var boss_bar: ProgressBar = $Root/BossBar
@onready var boss_label: Label = $Root/BossLabel
@onready var message: Label = $Root/Message
@onready var crosshair: Control = $Root/Crosshair
@onready var version_label: Label = $Root/VersionLabel

## Called by the player when toggling view modes; crosshair is FP-only.
func set_crosshair_visible(v: bool) -> void:
	crosshair.visible = v

func _ready() -> void:
	version_label.text = "v" + Version.STRING
	var player := get_node_or_null(player_path)
	if player:
		var ph: Health = player.get_node_or_null("Health")
		if ph:
			ph.health_changed.connect(_on_player_health)
			ph.died.connect(_on_player_died)
	var boss := get_node_or_null(boss_path)
	if boss:
		var bh: Health = boss.get_node_or_null("Health")
		if bh:
			bh.health_changed.connect(_on_boss_health)
			bh.died.connect(_on_boss_died)
	message.text = ""

func _on_player_health(current: float, maximum: float) -> void:
	player_bar.max_value = maximum
	player_bar.value = current

func _on_boss_health(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

func _on_player_died() -> void:
	message.text = "YOU DIED — press R to restart"

func _on_boss_died() -> void:
	boss_bar.value = 0
	boss_label.text = "BOSS DEFEATED"
	message.text = "VICTORY — press R to restart"
