extends CanvasLayer
## Reuses Nox's authored life bar; the Player remains the source of health.
var _player: Player = null
@onready var bar: Range = $Interface/SafeArea/Column/HP


func bind_player(subject: Player) -> void:
	if is_instance_valid(_player) and _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.disconnect(_on_health_changed)
	_player = subject
	_player.health_changed.connect(_on_health_changed)
	_on_health_changed(_player.health, _player.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = current
