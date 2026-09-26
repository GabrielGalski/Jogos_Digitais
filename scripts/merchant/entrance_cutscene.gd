extends Node2D
## Foreground aperture for the existing automatic entrance; no movement/level logic.
## hall_entrance.png is an exact 151x334 left crop, with alpha at x=22..42.
const NOX_NORMAL_Z: int = 10
const SHOOTER_NORMAL_Z: int = 9
const DOOR_EXIT_X: float = 11.0 # PNG x=43, aligned with hall origin x=-32.

var active: bool = false

func begin(nox: Node2D, shooter: Node2D) -> void:
	active = true
	show()
	nox.z_index = NOX_NORMAL_Z
	shooter.z_index = SHOOTER_NORMAL_Z
	shooter.set("mouse_look_enabled", false)
	# Both actors approach from behind the opening, not from opposite sides.
	shooter.set("shoulder", -1.0)

func update_layers(nox: Node2D, shooter: Node2D) -> void:
	if not active:
		return
	nox.z_index = 20 if nox.global_position.x >= DOOR_EXIT_X else NOX_NORMAL_Z
	shooter.z_index = 19 if shooter.global_position.x >= DOOR_EXIT_X else SHOOTER_NORMAL_Z

func finish(nox: Node2D, shooter: Node2D) -> void:
	active = false
	hide()
	nox.z_index = NOX_NORMAL_Z
	shooter.z_index = SHOOTER_NORMAL_Z
	shooter.set("mouse_look_enabled", true)
