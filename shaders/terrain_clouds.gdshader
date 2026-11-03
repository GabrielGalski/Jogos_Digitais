shader_type canvas_item;
render_mode unshaded;

// Adapted from MonsterShift's arena_soil_clouds; the source PNG palette is intact.
#include "res://shaders/terrain_scenery_grade.gdshaderinc"
#include "res://shaders/scenery_asset_palette.gdshaderinc"
#include "res://shaders/river_contour.gdshaderinc"

uniform bool clouds_enabled = true;
uniform float cloud_elapsed = 0.0;
uniform vec2 cloud_velocity = vec2(7.0, 1.5);
uniform float cloud_scale : hint_range(64.0, 1024.0) = 384.0;
uniform float cloud_threshold : hint_range(0.25, 0.8) = 0.68;
uniform float cloud_detail : hint_range(0.0, 0.4) = 0.22;
uniform float shadow_strength : hint_range(0.0, 0.35) = 0.20;
varying vec2 world_position;
varying vec4 vertex_tint;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 smooth_f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), smooth_f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), smooth_f.x), smooth_f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_tint = COLOR;
}

void fragment() {
	vec4 soil = texture(TEXTURE, UV) * vertex_tint;
	if (river_contour_enabled) {
		vec2 bank = river_distance_at(world_position);
		float land = river_land_coverage(bank);
		soil.a *= river_ground_fill ? bank.y * land : mix(1.0, land, bank.y);
		if (soil.a < 0.001) { discard; }
	}
	// Grass and cliff tops share the exact solid ground colour. Preserve it
	// so decorative atlas backgrounds join the floor without darker patches.
	bool ground_background = (asset_palette == 1 || asset_palette == 5) && palette_match(soil.rgb, vec3(83.0, 48.0, 72.0));
	if (asset_palette != 4 && !ground_background) {
		soil.rgb = scenery_colour(asset_colour(soil.rgb));
	}
	vec2 sample_world = world_position - cloud_velocity * cloud_elapsed;
	vec2 p = (sample_world + vec2(35.0, 81.0)) / cloud_scale;
	float cloud = mix(value_noise(p * vec2(0.75, 1.15)), value_noise(p * 2.1 + 19.0), cloud_detail);
	// MonsterShift/Asterion reference: one fixed shaded state per cloud.
	// The continuous world coordinates keep the enlarged outline rounded.
	if (clouds_enabled && cloud > cloud_threshold) {
		soil.rgb *= 1.0 - shadow_strength;
	}
	COLOR = soil;
}
