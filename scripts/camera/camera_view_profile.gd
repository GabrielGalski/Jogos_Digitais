class_name CameraViewProfile
extends Node

@export var display_name: String = ""
@export_range(1.0, 89.0, 0.1) var elevation_degrees: float = 62.0
@export_range(0.5, 8.0, 0.05) var orthographic_size: float = 2.25
@export_range(0.1, 2.0, 0.05) var wall_height: float = 0.75
@export_range(-2.0, 2.0, 0.05) var focus_depth_offset: float = -0.15
@export var floor_color: Color = Color("4d3545")
@export var wall_color: Color = Color("6f4358")
@export var wall_top_color: Color = Color("a45f72")
@export var background_color: Color = Color("25131a")
