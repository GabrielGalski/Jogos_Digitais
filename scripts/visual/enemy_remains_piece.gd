extends RefCounted
## Data only. One scene controller handles flight, expiry and fade without per-piece nodes.
var ground: Vector2 = Vector2.ZERO
var previous_ground: Vector2 = Vector2.ZERO
var height: float = 0.0
var previous_height: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var lift_velocity: float = 0.0
var angle: float = 0.0
var angular_velocity: float = 0.0
var texture_index: int = 0
var source_texture: Texture2D = null
var sprite_kind: StringName = &""
var palette_override: Callable = Callable()
var draw_offset: Vector2 = Vector2.ZERO
var render_scale: Vector2 = Vector2.ONE
var bounces: int = 0
var sleeping: bool = false
var falling: bool = false
var fall_elapsed: float = 0.0
var kick_after: float = 0.0
var expires_at: float = INF
var fade_end_at: float = INF
var opacity: float = 1.0
var profile: Resource = null
