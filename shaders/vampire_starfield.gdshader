shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_size = vec2(480.0, 270.0);
uniform vec2 camera_drift = vec2(0.0);
uniform float world_per_pixel = 1.0;

vec3 cell_seed(vec2 cell) {
	vec3 value = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
	value += dot(value, value.yzx + 33.33);
	return fract((value.xxy + value.yzz) * value.zyx);
}

vec3 star_layer(vec2 point, float cell_size, float density, bool foreground) {
	vec2 cell = floor(point / cell_size);
	vec3 seed = cell_seed(cell + (foreground ? vec2(291.0, -103.0) : vec2(0.0)));
	vec2 anchor = floor(vec2(2.0) + seed.xy * (cell_size - 4.0));
	vec2 distance_px = abs(floor(point - cell * cell_size) - anchor);
	float center = 1.0 - step(0.5, max(distance_px.x, distance_px.y));
	float cross = (1.0 - step(1.5, distance_px.x + distance_px.y)) - center;
	float large = step(0.66, seed.x) * (foreground ? 1.0 : 0.0);
	float cycle = fract(TIME * mix(0.20, 0.48, seed.y) + seed.x * 23.0);
	float brightness = smoothstep(0.18, 0.48, cycle) * (1.0 - smoothstep(0.62, 0.96, cycle));
	float shape = center + cross * large * 0.43;
	vec3 tint = mix(vec3(0.36, 0.29, 0.66), vec3(0.39, 0.68, 0.83), step(0.42, seed.z));
	tint = mix(tint, vec3(0.98, 0.64, 0.40), foreground ? step(0.76, seed.z) : 0.0);
	return tint * shape * brightness * step(1.0 - density, seed.z) * (foreground ? 0.81 : 0.45);
}

void fragment() {
	vec2 pixel = (UV - 0.5) * view_size * world_per_pixel;
	float nebula = 1.0 - smoothstep(10.0, 160.0, abs(pixel.y + 0.25 * pixel.x + camera_drift.y * 0.07));
	vec3 sky = mix(vec3(0.073, 0.055, 0.126), vec3(0.127, 0.083, 0.217), nebula * 0.68);
	sky += star_layer(pixel + camera_drift * 0.11, 8.0, 0.58, false);
	sky += star_layer(pixel + camera_drift * 0.29, 16.0, 0.50, true);
	COLOR = vec4(sky, 1.0);
}
