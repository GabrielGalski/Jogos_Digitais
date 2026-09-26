shader_type canvas_item;
render_mode unshaded;

uniform vec4 deep_color : source_color = vec4(0.137255, 0.474510, 0.431373, 1.0);
uniform vec4 body_color : source_color = vec4(0.266667, 0.517647, 0.450980, 1.0);
uniform vec4 light_color : source_color = vec4(0.643137, 1.0, 0.980392, 1.0);
uniform vec4 foam_color : source_color = vec4(0.886275, 0.992157, 1.0, 1.0);
uniform vec2 water_size = vec2(1024.0, 39.0);
uniform float current_speed : hint_range(0.0, 30.0) = 6.0;
uniform float distant_speed_ratio : hint_range(0.1, 0.9) = 0.45;
uniform float pixel_size : hint_range(0.5, 3.0) = 1.0;
uniform float ripple_strength : hint_range(0.0, 2.0) = 1.0;

varying vec2 water_position;

float hash21(vec2 point) {
	vec3 h = fract(vec3(point.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float smooth_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	// Local geometry coordinates stay anchored when the camera moves.
	water_position = VERTEX;
}

void fragment() {
	vec2 p = (floor(water_position / pixel_size) + 0.5) * pixel_size;
	float depth = clamp(p.y / max(water_size.y, 1.0), 0.0, 1.0);
	float flow = TIME * current_speed;
	vec2 plane = vec2(p.x, p.y * 2.5);
	float broad = smooth_noise((plane + vec2(flow, -flow * 0.13)) / vec2(42.0, 12.0));
	float small = smooth_noise((plane + vec2(-flow * distant_speed_ratio, flow * 0.21)) / vec2(18.0, 6.5));
	float field = broad * 0.72 + small * 0.28;
	vec3 color = mix(deep_color.rgb, body_color.rgb, step(0.46, field));
	// Broken, flattened crests cover the full top-facing plane.
	float bend = (broad - 0.5) * 5.0 * ripple_strength;
	float wave = abs(sin(p.y * 0.70 + bend + small * 2.6 - flow * 0.065));
	float reflection = step(wave, mix(0.16, 0.25, depth)) * step(0.43, field);
	color = mix(color, light_color.rgb, reflection);
	float crest = step(wave, 0.075) * step(0.62, broad) * step(0.40, small);
	color = mix(color, foam_color.rgb, crest);
	// Floating flecks use analytical motion instead of particle nodes.
	vec2 fleck_point = (p + vec2(flow * 0.60, sin(TIME * 0.6) * 0.5)) / vec2(23.0, 8.0);
	vec2 cell = floor(fleck_point);
	float seed = hash21(cell + vec2(17.0, 9.0));
	vec2 fleck_local = fract(fleck_point) - vec2(0.3 + seed * 0.4, 0.5);
	float fleck = step(abs(fleck_local.x), 0.06 + seed * 0.07)
		* step(abs(fleck_local.y), 0.075) * step(0.73, seed)
		* step(0.20, sin(TIME * 0.9 + seed * 30.0));
	color = mix(color, foam_color.rgb, fleck);
	// Exact original shoreline and extent; no vertex displacement.
	float shore = step(p.y, pixel_size) * step(0.48, broad);
	color = mix(color, light_color.rgb, shore);
	COLOR = vec4(color, 1.0);
}
