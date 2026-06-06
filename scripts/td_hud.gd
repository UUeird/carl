extends CanvasLayer

## TD HUD: shows lives / currency / wave, a "Start wave" button, and messages.
## Reads nothing directly — reacts to the controller's signals.

@export var game_path: NodePath

@onready var stats: Label = $Root/Stats
@onready var message: Label = $Root/Message
@onready var start_btn: Button = $Root/StartBtn
@onready var hint: Label = $Root/Hint

var _game

func _ready() -> void:
	_game = get_node_or_null(game_path)
	if _game == null:
		return
	_game.state_changed.connect(_refresh)
	_game.message.connect(_on_message)
	_game.game_over.connect(_on_game_over)
	start_btn.pressed.connect(func(): _game.start_next_wave())
	hint.text = "Click a green slot to build a tower (cost shown). Towers auto-fire."
	_refresh()

func _refresh() -> void:
	stats.text = "♥ %d    ⬢ %d    Wave %d/%d" % [_game.lives, _game.currency, _game.wave, _game.wave_count]
	start_btn.text = "Start wave %d  ▶" % (_game.wave + 1)
	start_btn.disabled = not _game.can_start_wave()

func _on_message(text: String) -> void:
	message.text = text

func _on_game_over(_victory: bool) -> void:
	start_btn.disabled = true
