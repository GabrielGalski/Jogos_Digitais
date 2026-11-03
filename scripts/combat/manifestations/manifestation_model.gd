class_name ProceduralManifestationModel
extends Resource
## Immutable authored behavior and three-color appearance; timers belong to the caster.

enum Family { PROJECTILE, BEAM, STREAM }
enum Shape { DROP, MASS, LASER, SPIKE, FIREBALL, FLAME }

@export var card: ManifestationCard
@export var family: Family = Family.PROJECTILE
@export var shape: Shape = Shape.DROP
@export var shadow_color: Color = Color("#25131a")
@export var body_color: Color = Color("#00baa7")
@export var core_color: Color = Color("#f6ede5")
## Presentation scale, independent of damage, travel and collision geometry.
@export_range(0.3, 1.0) var visual_scale: float = 0.6
@export_range(0.5, 12.0) var hit_radius: float = 3.0
@export_range(0.0, 64.0) var trail_length: float = 17.0
@export_range(0.0, 0.4) var halo_opacity: float = 0.18
@export_range(8.0, 48.0) var halo_size: float = 22.0
@export var blast_radius: float = 0.0
@export var spread_degrees: float = 0.0
@export var attached_duration: float = 0.0
@export var dot_interval: float = 0.32
@export var dot_damage: float = 1.0
@export var reach: float = 240.0
@export var start_half_width: float = 5.0
@export var end_half_width: float = 17.0
@export var infusion_interval: float = 0.5


func code() -> StringName:
	return card.card_id if card != null else &""


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if card == null:
		errors.append("Manifestation model needs a combat card.")
	else:
		errors.append_array(card.validation_errors())
	if shadow_color == body_color or body_color == core_color or shadow_color == core_color:
		errors.append("The model needs three distinct palette entries.")
	if hit_radius <= 0.0 or reach <= 0.0 or dot_interval <= 0.0 or infusion_interval <= 0.0:
		errors.append("Combat radii and intervals must be positive.")
	return errors
