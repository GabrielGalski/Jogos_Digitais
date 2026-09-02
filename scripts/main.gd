extends Node2D

@onready var arena: Arena = $Arena
@onready var player: Player = $Player


func _ready() -> void:
	player.set_movement_bounds(arena.get_player_bounds())
	player.global_position = Vector2.ZERO
