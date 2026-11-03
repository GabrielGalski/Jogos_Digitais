shader_type canvas_item;

uniform float cloud_elapsed = 0.0;
uniform vec2 cloud_velocity = vec2(7.0, 1.5);
uniform float cloud_scale = 96.0;
uniform float shadow_strength = 0.08;
uniform bool clouds_enabled = true;
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
	vec4 original = texture(TEXTURE, UV);
	// Only the two light interior tiles. Dark trail, rims and void stay authored.
	ivec2 atlas_cell = ivec2(floor(UV * vec2(4.0, 3.0)));
	if (atlas_cell.y == 1 && (atlas_cell.x == 1 || atlas_cell.x == 2)) {
		vec2 sample_world = floor(world_position / 2.0) * 2.0 - cloud_velocity * cloud_elapsed;
		vec2 p = (sample_world + vec2(35.0, 81.0)) / cloud_scale;
		float cloud = value_noise(p * vec2(0.75, 1.15)) * 0.78 + value_noise(p * 2.1 + 19.0) * 0.22;
		if (clouds_enabled && cloud > 0.72) {
			original.rgb *= 1.0 - shadow_strength;
		}
	}
	COLOR = original * vertex_tint;
}
