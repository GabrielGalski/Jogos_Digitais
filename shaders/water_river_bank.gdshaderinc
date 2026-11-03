// A fixed earthen face and submerged shelf, measured normal to the shared coast.
// Only procedural river banks opt in; the protected cliff has no active bank.
uniform bool bank_enabled = false;
uniform float bank_width_px : hint_range(1.0, 8.0) = 4.0;
uniform float bank_submerged_width_px : hint_range(1.0, 24.0) = 8.0;
uniform float bank_contact_width_px : hint_range(0.5, 4.0) = 1.5;
uniform vec4 bank_color : source_color = vec4(0.239216, 0.141176, 0.211765, 1.0);
uniform float bank_submerged_tint : hint_range(0.0, 1.0) = 0.48;

vec3 river_bank_water(vec3 water_color, vec3 shallow_color, float water_distance, float contact_strength) {
	float depth = max(water_distance, 0.0);
	float shelf = 1.0 - smoothstep(0.0, bank_submerged_width_px, depth);
	// Keep the moving surface visible over a slightly purple submerged ledge.
	vec3 submerged_ground = mix(bank_color.rgb, shallow_color, 0.72);
	vec3 color = mix(water_color, submerged_ground, shelf * bank_submerged_tint);
	// Contact is independent of the texture's alpha/mask channel.
	float contact = 1.0 - smoothstep(0.0, bank_contact_width_px, depth);
	return color * (1.0 - contact * contact_strength);
}

float river_bank_face(float ground_distance, float aa) {
	return 1.0 - smoothstep(bank_width_px - aa, bank_width_px + aa, ground_distance);
}
