// One compact, interpolated bank profile shared with support and collision.
uniform bool river_contour_enabled = false;
uniform sampler2D river_profile : filter_linear, repeat_disable;
uniform vec4 river_rect = vec4(0.0);
uniform vec2 river_world_origin = vec2(0.0);
uniform float river_profile_count = 1.0;
uniform float river_profile_step = 2.0;
uniform float river_edge_softness_px = 1.0;
uniform bool river_ground_fill = false;
// The visual low bank meets the cliff foot before the curvature/physics guard ends.
uniform float river_west_bank_start_y = 1e20;

vec4 river_banks_at(float y) {
	float coordinate = clamp((y - river_rect.y) / river_profile_step, 0.0, river_profile_count - 1.0);
	return texture(river_profile, vec2(0.5, (coordinate + 0.5) / river_profile_count));
}

vec3 river_fields_at(vec2 world) {
	vec2 p = world - river_world_origin;
	if (!river_contour_enabled || p.x < river_rect.x || p.x >= river_rect.x + river_rect.z || p.y < river_rect.y || p.y >= river_rect.y + river_rect.w) {
		return vec3(0.0);
	}
	vec4 banks = river_banks_at(p.y);
	vec4 before = river_banks_at(p.y - river_profile_step);
	vec4 after = river_banks_at(p.y + river_profile_step);
	bool west = p.x <= (banks.x + banks.y) * 0.5;
	float slope = (west ? after.x - before.x : after.y - before.y) / (river_profile_step * 2.0);
	float distance_to_bank = (west ? p.x - banks.x : banks.y - p.x) / sqrt(1.0 + slope * slope);
	float coast = west ? banks.z : banks.w;
	float visual_bank = west ? max(coast, banks.w * step(river_west_bank_start_y, p.y)) : coast;
	return vec3(distance_to_bank, coast, visual_bank);
}

vec2 river_distance_at(vec2 world) {
	// Existing ground clipping keeps its original activation and collision guard.
	return river_fields_at(world).xy;
}

float river_land_coverage(vec2 field) {
	float half_width = max(river_edge_softness_px, 0.1) * 0.5;
	return 1.0 - smoothstep(-half_width, half_width, field.x);
}
