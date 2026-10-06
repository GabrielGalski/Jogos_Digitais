extends Resource
@export var shadow_color: Color = Color("#170f1b")
@export var midtone_color: Color = Color("#694052")
@export var highlight_color: Color = Color("#f6ede5")
@export_range(0.0, 0.4, 0.01) var world_palette_mix: float = 0.18
@export var halo_opacity: float = 0.17
@export var shot_recoil: float = 0.85
@export var shot_energy: float = 0.18
@export var shot_duration: float = 0.075
@export var impact_energy: float = 0.26
@export var impact_duration: float = 0.10

static func accent(code: StringName) -> Color:
	match code:
		&"M01": return Color("#a8e387")
		&"M02": return Color("#67c974")
		&"M03": return Color("#b9f4ee")
		&"M04": return Color("#ffe26b")
		&"M05": return Color("#c5a7ff")
		&"M06": return Color("#f3a5c2")
		&"M07", &"M08": return Color("#ffb649")
	return Color("#f6ede5")
