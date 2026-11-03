class_name WaterProfile
extends Resource
## World-space water appearance. Sizes use world pixels, independent of masks.

enum ReflectionStyle { WAVES, GLINTS }

@export var preset_id: StringName = &"Lake"
@export var deep_color: Color = Color("173d4a")
@export var mid_color: Color = Color("255f68")
@export var highlight_color: Color = Color("71aa99")
@export_range(4.0, 128.0) var cell_size_px: float = 24.0
@export_range(1, 16) var pixel_size_px: int = 1
@export_range(0.0, 16.0) var distortion_strength_px: float = 1.5
@export_range(0.0, 4.0) var animation_speed: float = 1.0
@export var flow_direction: Vector2 = Vector2.RIGHT
@export_range(0.0, 64.0) var flow_speed_px_s: float = 2.0
@export_range(0.0, 0.4) var highlight_width: float = 0.05
@export_range(0.0, 1.0) var highlight_breakup: float = 0.48
@export_range(0, 10000) var pattern_seed: int = 0

@export_group("Continuous surface")
## Samples at display resolution; pixel_size_px only applies to the pixel mode.
@export var smooth_surface: bool = false
@export var reflection_style: ReflectionStyle = ReflectionStyle.WAVES
@export_range(8.0, 96.0) var wave_length_px: float = 32.0
@export_range(0.0, 1.0) var wave_strength: float = 0.5
@export_range(0.0, 1.0) var reflection_strength: float = 0.45
@export_range(0.0, 1.0) var voronoi_strength: float = 0.04
@export_range(0.0, 1.0) var shore_tint_strength: float = 0.2
@export_range(4.0, 32.0) var shallow_width_px: float = 20.0
@export_range(0.0, 1.0) var secondary_wave_strength: float = 0.24
@export_range(0.0, 1.0) var calmness: float = 0.55
@export_range(0.0, 1.0) var shore_shadow_strength: float = 0.22

@export_group("Procedural river bank")
## Earthen face inside the river, followed by a submerged shelf. No floor support.
@export var bank_enabled: bool = false
@export_range(1.0, 8.0) var bank_width_px: float = 4.0
@export_range(1.0, 24.0) var bank_submerged_width_px: float = 8.0
@export_range(0.5, 4.0) var bank_contact_width_px: float = 1.5
@export var bank_color: Color = Color("#3d2436")
@export_range(0.0, 1.0) var bank_submerged_tint: float = 0.48

@export_group("Sun glints")
## Used by continuous GLINTS surfaces. Spacing/size are world pixels.
@export var sparkle_color: Color = Color("e5fff4")
@export_range(12.0, 64.0) var sparkle_spacing_px: float = 28.0
@export_range(0.0, 1.0) var sparkle_density: float = 0.42
@export_range(0.5, 3.0) var sparkle_size_px: float = 1.1
@export_range(0.0, 1.0) var sparkle_intensity: float = 0.95
@export_range(0.4, 4.0) var sparkle_lifetime_s: float = 1.4
@export_range(0.0, 1.0) var sparkle_halo_strength: float = 0.38

@export_group("Shore foam")
@export var foam_color: Color = Color("9db8aa")
@export_range(0.5, 4.0) var foam_width_px: float = 1.5
@export_range(4.0, 24.0) var foam_reach_px: float = 12.0
@export_range(0.0, 1.0) var foam_opacity: float = 0.65
@export_range(2.0, 12.0) var shore_wave_period_s: float = 5.5
@export_range(0.0, 1.0) var foam_coverage: float = 0.64
@export_range(0.0, 1.0) var foam_irregularity: float = 0.75
@export_range(0.0, 1.0) var foam_residue: float = 0.25


func validation_error() -> String:
	if str(preset_id).strip_edges().is_empty():
		return "Preset sem identificador"
	if not is_finite(cell_size_px) or cell_size_px < 1.0 or pixel_size_px < 1:
		return "Tamanho de celula/pixel deve ser positivo"
	if not flow_direction.is_finite():
		return "Direcao de fluxo invalida"
	if reflection_style not in [ReflectionStyle.WAVES, ReflectionStyle.GLINTS]:
		return "Estilo de reflexo invalido"
	for value: float in [distortion_strength_px, animation_speed, flow_speed_px_s, highlight_width, highlight_breakup]:
		if not is_finite(value) or value < 0.0:
			return "Parametro de animacao invalido"
	if highlight_width > 0.4 or highlight_breakup > 1.0:
		return "Reflexos fora do intervalo permitido"
	for strength: float in [wave_strength, reflection_strength, voronoi_strength, shore_tint_strength, foam_opacity,
		secondary_wave_strength, calmness, shore_shadow_strength, foam_coverage, foam_irregularity, foam_residue,
		sparkle_density, sparkle_intensity, sparkle_halo_strength, bank_submerged_tint]:
		if not is_finite(strength) or strength < 0.0 or strength > 1.0:
			return "Intensidade visual fora do intervalo 0..1"
	for length_value: float in [wave_length_px, shallow_width_px, foam_width_px, foam_reach_px, shore_wave_period_s,
		sparkle_spacing_px, sparkle_size_px, sparkle_lifetime_s,
		bank_width_px, bank_submerged_width_px, bank_contact_width_px]:
		if not is_finite(length_value) or length_value <= 0.0:
			return "Escala de onda/margem deve ser positiva"
	if foam_reach_px < foam_width_px or maxf(shallow_width_px, foam_reach_px) > 32.0:
		return "Alcance de margem invalido (maximo 32 px)"
	if sparkle_spacing_px < sparkle_size_px * 12.0:
		return "Espacamento dos brilhos deve ser pelo menos 12 vezes o tamanho"
	if bank_width_px + bank_submerged_width_px > 32.0 or bank_contact_width_px > bank_submerged_width_px:
		return "Borda exige contato dentro da faixa submersa e alcance total de ate 32 px"
	for color: Color in [deep_color, mid_color, highlight_color, foam_color, sparkle_color, bank_color]:
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
			return "Cor invalida"
	return ""


func shader_parameters() -> Dictionary:
	return {
		"deep_color": deep_color, "mid_color": mid_color, "highlight_color": highlight_color,
		"cell_size_px": cell_size_px, "pixel_size_px": float(pixel_size_px),
		"distortion_strength_px": distortion_strength_px, "animation_speed": animation_speed,
		"flow_direction": flow_direction.normalized(), "flow_speed_px_s": flow_speed_px_s,
		"highlight_width": highlight_width, "highlight_breakup": highlight_breakup,
		"pattern_seed": float(pattern_seed),
		"smooth_surface": smooth_surface, "reflection_style": reflection_style, "wave_length_px": wave_length_px,
		"wave_strength": wave_strength, "reflection_strength": reflection_strength,
		"voronoi_strength": voronoi_strength, "shore_tint_strength": shore_tint_strength,
		"shallow_width_px": shallow_width_px,
		"secondary_wave_strength": secondary_wave_strength, "calmness": calmness,
		"shore_shadow_strength": shore_shadow_strength,
		"bank_enabled": bank_enabled, "bank_width_px": bank_width_px,
		"bank_submerged_width_px": bank_submerged_width_px, "bank_contact_width_px": bank_contact_width_px,
		"bank_color": bank_color, "bank_submerged_tint": bank_submerged_tint,
		"sparkle_color": sparkle_color, "sparkle_spacing_px": sparkle_spacing_px,
		"sparkle_density": sparkle_density, "sparkle_size_px": sparkle_size_px,
		"sparkle_intensity": sparkle_intensity, "sparkle_lifetime_s": sparkle_lifetime_s,
		"sparkle_halo_strength": sparkle_halo_strength,
	}


func foam_shader_parameters() -> Dictionary:
	return {"foam_color": foam_color, "foam_width_px": foam_width_px,
		"foam_reach_px": foam_reach_px, "foam_opacity": foam_opacity,
		"shore_wave_period_s": shore_wave_period_s, "animation_speed": animation_speed,
		"foam_coverage": foam_coverage, "foam_irregularity": foam_irregularity, "foam_residue": foam_residue}
