shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/water_coast.gdshaderinc"
#include "res://shaders/river_contour.gdshaderinc"
uniform bool combined_foam = false;

uniform vec4 deep_color : source_color = vec4(0.09, 0.24, 0.29, 1.0);
uniform vec4 mid_color : source_color = vec4(0.15, 0.37, 0.41, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.44, 0.67, 0.60, 1.0);
uniform float cell_size_px : hint_range(4.0, 128.0) = 24.0;
uniform float pixel_size_px : hint_range(1.0, 16.0, 1.0) = 1.0;
uniform float distortion_strength_px : hint_range(0.0, 16.0) = 1.5;
uniform float animation_speed : hint_range(0.0, 4.0) = 1.0;
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed_px_s : hint_range(0.0, 64.0) = 2.0;
uniform float highlight_width : hint_range(0.0, 0.4) = 0.05;
uniform float highlight_breakup : hint_range(0.0, 1.0) = 0.48;
uniform float pattern_seed = 0.0;
uniform float water_elapsed = 0.0;
uniform bool smooth_surface = false;
// 0: elongated wave reflections. 1: local sun glints, with no line crests.
uniform int reflection_style = 0;
uniform float wave_length_px = 32.0;
uniform float wave_strength = 0.5;
uniform float reflection_strength = 0.45;
uniform float voronoi_strength = 0.04;
uniform float shore_tint_strength = 0.2;
uniform float shallow_width_px = 20.0;
uniform float secondary_wave_strength = 0.24;
uniform float calmness = 0.55;
uniform float shore_shadow_strength = 0.22;
uniform vec4 sparkle_color : source_color = vec4(0.898, 1.0, 0.957, 1.0);
uniform float sparkle_spacing_px = 28.0;
uniform float sparkle_density = 0.42;
uniform float sparkle_size_px = 1.1;
uniform float sparkle_intensity = 0.95;
uniform float sparkle_lifetime_s = 1.4;
uniform float sparkle_halo_strength = 0.38;
// Background meshes supply a local distance field through TEXTURE.
// Authored sprites keep their original alpha mask and leave this disabled.
uniform bool use_shore_field = false;

#include "res://shaders/water_river_bank.gdshaderinc"

varying vec2 world_position;
varying vec4 surface_modulate;

vec2 hash22(vec2 point) {
	vec3 h = fract(vec3(point.xyx) * vec3(0.1031, 0.1030, 0.0973));
	h += dot(h, h.yzx + 33.33);
	return fract((h.xx + h.yz) * h.zy);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash22(cell).x, hash22(cell + vec2(1.0, 0.0)).x, local.x),
		mix(hash22(cell + vec2(0.0, 1.0)).x, hash22(cell + vec2(1.0)).x, local.x), local.y);
}

vec2 voronoi_distances(vec2 point, float elapsed) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 nearest_squared = vec2(100.0);
	float motion = min(distortion_strength_px / cell_size_px, 0.18);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 random = hash22(cell + neighbor + vec2(pattern_seed, pattern_seed * 0.37));
			vec2 seed = vec2(0.5) + (random - 0.5) * 0.60;
			seed += motion * sin(random * TAU + elapsed * vec2(0.43, 0.37));
			vec2 delta = neighbor + seed - local;
			float distance_squared = dot(delta, delta);
			if (distance_squared < nearest_squared.x) {
				nearest_squared.y = nearest_squared.x;
				nearest_squared.x = distance_squared;
			} else if (distance_squared < nearest_squared.y) {
				nearest_squared.y = distance_squared;
			}
		}
	}
	return sqrt(nearest_squared);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	surface_modulate = COLOR;
}

float glint_fragment(vec2 p, vec2 radius, float footprint) {
	vec2 box = abs(p) - radius;
	float distance = length(max(box, vec2(0.0))) + min(max(box.x, box.y), 0.0);
	return 1.0 - smoothstep(-footprint * 0.5, footprint * 0.5, distance);
}

vec2 sun_glints(vec2 p, float elapsed, float footprint) {
	vec2 cell = floor(p / sparkle_spacing_px);
	vec2 random = hash22(cell + vec2(pattern_seed * 0.73, 41.7));
	float lifetime = sparkle_lifetime_s * (0.7 + random.y * 0.6);
	float age = elapsed / lifetime + random.x * 13.0;
	float cycle = floor(age);
	float phase = fract(age);
	vec2 birth = hash22(cell + vec2(cycle * 17.31 + 3.7, cycle * 9.13 + pattern_seed));
	float presence = hash22(cell + vec2(cycle * 5.1 + 91.1, 17.3 + pattern_seed)).x;
	if (presence > sparkle_density) {
		return vec2(0.0);
	}
	// The entire cluster fits inside its cell. Birth positions change only at
	// phase wrap, where the envelope and all satellites/halo are invisible.
	float envelope = smoothstep(0.04, 0.3, phase) * (1.0 - smoothstep(0.6, 0.96, phase));
	float margin = sparkle_size_px * 4.8 / sparkle_spacing_px;
	vec2 center = mix(vec2(margin), vec2(1.0 - margin), birth) * sparkle_spacing_px;
	center += vec2(sin(elapsed * 0.57 + random.x * TAU), cos(elapsed * 0.43 + random.y * TAU)) * sparkle_size_px * 0.25;
	vec2 local = p - cell * sparkle_spacing_px - center;
	local.x *= mix(0.85, 1.15, random.x);
	local.y *= random.x > 0.5 ? -1.0 : 1.0;
	float size = sparkle_size_px * (0.8 + envelope * 0.2);
	float core = glint_fragment(local, vec2(1.35, 0.45) * size, footprint);
	core = max(core, glint_fragment(local - vec2(-1.9, 0.65) * size, vec2(0.6, 0.4) * size, footprint) * 0.8);
	core = max(core, glint_fragment(local - vec2(1.7, -0.7) * size, vec2(0.5, 0.4) * size, footprint) * mix(0.3, 0.85, birth.x));
	core = max(core, glint_fragment(local - vec2(-0.5, -1.6) * size, vec2(0.25) * size, footprint) * step(0.5, birth.x) * 0.55);
	vec2 glow_p = local / (sparkle_size_px * vec2(2.3, 1.9));
	float halo = exp(-dot(glow_p, glow_p));
	halo *= 1.0 - smoothstep(sparkle_size_px * 2.7, sparkle_size_px * 3.5, length(local));
	float visibility = 1.0 - smoothstep(size * 1.3, size * 4.0, footprint);
	return vec2(core, halo) * envelope * (0.65 + birth.x * 0.35) * visibility;
}

vec3 continuous_water(vec2 p, vec2 point, float elapsed, float footprint, float shore_visibility) {
	vec2 direction = length(flow_direction) > 0.001 ? normalize(flow_direction) : vec2(1.0, 0.0);
	vec2 cross_direction = vec2(-direction.y, direction.x);
	vec2 oriented = vec2(dot(p, direction), dot(p, cross_direction));
	float transport = flow_speed_px_s * min(length(flow_direction), 1.0);
	vec2 slow = (oriented - vec2(transport, 0.0) * elapsed * 0.35) / cell_size_px;
	vec2 cloud_scale = reflection_style == 1 ? vec2(0.5, 0.65) : vec2(0.25, 0.4);
	vec2 swell_scale = reflection_style == 1 ? vec2(1.3, 1.7) : vec2(0.55, 0.8);
	float cloud = value_noise(slow * cloud_scale + vec2(pattern_seed * 0.13, elapsed * 0.014));
	float swell = value_noise(slow * swell_scale - vec2(elapsed * 0.025, 0.0));
	float body = 0.2 + cloud * 0.45 + swell * 0.12;
	if (reflection_style == 1) {
		body = mix(0.48, mix(0.12, 0.88, smoothstep(0.15, 0.85, cloud * 0.6 + swell * 0.4)), max(wave_strength, 0.25));
	}
	vec3 color = mix(deep_color.rgb, mid_color.rgb, body);
	float caustic = 0.0;
	if (voronoi_strength > 0.0) {
		vec2 distances = voronoi_distances(point * vec2(0.7, 1.25), elapsed);
		float gap = distances.y - distances.x;
		float edge_aa = max(fwidth(gap), 0.001);
		caustic = (1.0 - smoothstep(highlight_width, highlight_width + edge_aa, gap));
		caustic *= smoothstep(0.58, 0.78, swell) * voronoi_strength;
	}
	if (reflection_style == 1) {
		if (sparkle_intensity > 0.0 && sparkle_density > 0.0) {
			vec2 glints = sun_glints(p - direction * transport * elapsed * 0.1, elapsed, footprint);
			float calm = mix(1.0, 0.5 + swell * 0.5, calmness);
			glints *= sparkle_intensity * reflection_strength * shore_visibility * calm;
			color = mix(color, highlight_color.rgb, clamp(glints.y * sparkle_halo_strength, 0.0, 1.0));
			color = mix(color, sparkle_color.rgb, clamp(glints.x * sparkle_color.a * 1.3, 0.0, 1.0));
		}
		return mix(color, highlight_color.rgb, clamp(caustic * reflection_strength, 0.0, 0.4));
	}

	float wind = value_noise(slow * vec2(0.8, 1.1) + vec2(0.0, elapsed * 0.045));
	float phase = oriented.y * TAU / wave_length_px + wind * 2.8 - elapsed * 0.48;
	phase += sin(oriented.x / (wave_length_px * 1.6) + elapsed * 0.21) * 0.65;
	float ridge = abs(sin(phase));
	float aa = max(fwidth(phase), 0.01);
	float fragments = smoothstep(0.48, 0.74, value_noise(slow * vec2(1.3, 0.7) + vec2(7.0, elapsed * 0.025)));
	float ripple = (1.0 - smoothstep(0.035, 0.1 + aa, ridge)) * fragments;
	float calm = mix(1.0, smoothstep(0.32, 0.72, cloud), calmness);
	float detail_visibility = 1.0 - smoothstep(0.4, 1.6, aa);
	float cross_phase = (oriented.y * 0.88 + oriented.x * 0.35) * TAU / (wave_length_px * 0.62);
	cross_phase += wind * 2.0 + elapsed * 0.29;
	float cross_aa = max(fwidth(cross_phase), 0.01);
	float cross_ripple = 1.0 - smoothstep(0.025, 0.075 + cross_aa, abs(sin(cross_phase)));
	cross_ripple *= smoothstep(0.5, 0.8, swell) * secondary_wave_strength;
	cross_ripple *= 1.0 - smoothstep(0.4, 1.6, cross_aa);
	float secondary = 0.5 + 0.5 * sin(phase * 0.63 + wind * 3.0 + elapsed * 0.36);
	color = mix(color, mid_color.rgb, secondary * wave_strength * 0.12);

	float reflection = ((ripple * detail_visibility + cross_ripple) * calm * wave_strength * 0.55 + caustic) * reflection_strength;
	return mix(color, highlight_color.rgb, clamp(reflection, 0.0, 0.4));
}

void fragment() {
	vec4 field = texture(TEXTURE, UV);
	float coast_aa = max(fwidth(field.r), 0.25);
	float footprint = max(max(length(dFdx(world_position)), length(dFdy(world_position))), 0.001);
	float mask_alpha = use_shore_field ? 1.0 : step(0.5, field.a);
	vec3 river_bank = river_contour_enabled ? river_fields_at(world_position) : vec3(0.0);
	float bank_amount = bank_enabled ? river_bank.z : 0.0;
	bool has_bank = bank_amount > 0.0;
	float coast_amount = max(river_bank.y, bank_amount);
	bool has_coast = use_shore_field || coast_amount > 0.0;
	if (coast_amount > 0.0) {
		// Water is opaque under the complementary ground edge. Applying the
		// same alpha twice would create a dark seam over GroundBase.
		mask_alpha = mix(mask_alpha, 1.0, coast_amount);
		// The authored edge remains the collision boundary. Water/foam begin
		// at the foot of the decorative face, four pixels farther inside.
		field = vec4(river_bank.x - (has_bank ? bank_width_px : 0.0), coast_amount, 1.0, coast_amount);
		coast_aa = max(0.25, river_edge_softness_px * 0.5);
	}
	if (mask_alpha < 0.001 || surface_modulate.a <= 0.0) {
		discard;
	}
	// Continuous water is sampled at display resolution. Terrain stays nearest.
	vec2 p = smooth_surface ? world_position : (floor(world_position / pixel_size_px) + 0.5) * pixel_size_px;
	float elapsed = water_elapsed * animation_speed;
	vec2 warp = vec2(sin(p.y / (cell_size_px * 1.8) + elapsed * 0.43),
		cos(p.x / (cell_size_px * 1.6) - elapsed * 0.37)) * distortion_strength_px;
	vec2 point = (p - flow_direction * flow_speed_px_s * elapsed + warp) / cell_size_px;
	vec3 water_color;
	if (smooth_surface) {
		float shore_visibility = has_coast ? smoothstep(foam_width_px, foam_width_px + 5.0, field.r) : 1.0;
		water_color = continuous_water(p + warp, point, elapsed, footprint, shore_visibility);
		if (has_coast && !has_bank) {
			float variation = value_noise(world_position * 0.025 + vec2(pattern_seed));
			float shallow_width = shallow_width_px * field.b * (0.65 + variation * 0.35);
			float shallow = 1.0 - smoothstep(0.0, shallow_width, field.r);
			water_color = mix(water_color, mid_color.rgb, shallow * shore_tint_strength * (0.6 + variation * 0.4));
			float shadow = (1.0 - smoothstep(0.0, 5.0, field.r)) * field.a * shore_shadow_strength;
			water_color *= 1.0 - shadow;
		}
	} else {
		vec2 distances = voronoi_distances(point, elapsed);
		float edge_gap = distances.y - distances.x;
		float broad = value_noise(point * 0.8 + vec2(pattern_seed * 0.13, elapsed * 0.035));
		float body = step(0.47, broad);
		water_color = mix(deep_color.rgb, mid_color.rgb, body);
		float broken_edges = step(highlight_breakup, broad);
		float reflection = (1.0 - step(highlight_width, edge_gap)) * broken_edges;
		water_color = mix(water_color, highlight_color.rgb, reflection);
	}
	if (has_bank) {
		water_color = mix(water_color,
			river_bank_water(water_color, mid_color.rgb, field.r, shore_shadow_strength), bank_amount);
	}
	if (combined_foam && has_coast && field.r < foam_reach_px && field.g > 0.0) {
		water_color = mix(water_color, foam_color.rgb, coast_foam(world_position, field, elapsed, coast_aa));
	}
	if (has_bank) {
		// Cover foam on the face itself; only its foot touches the surface.
		float face = river_bank_face(river_bank.x, coast_aa) * bank_amount * bank_color.a;
		water_color = mix(water_color, bank_color.rgb, face);
	}
	COLOR = vec4(water_color * surface_modulate.rgb, mask_alpha * surface_modulate.a);
}
