extends CanvasLayer
## Keep the operating-system pointer out of gameplay without hiding clickable UI.

const RETICLE: Script = preload("res://scripts/dungeon/manifestation_reticle.gd")

var pointer: Sprite2D


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	pointer = Sprite2D.new()
	pointer.name = "GamePointer"
	pointer.set_script(RETICLE)
	add_child(pointer)
	pointer.hide()


func _process(_delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		pointer.hide()
		return
	# Combat scenes already draw a reticle that also carries their card tint.
	pointer.visible = scene.find_child("Crosshair", true, false) == null


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
