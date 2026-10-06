shader_type canvas_item;
render_mode unshaded;

uniform float health_blocks : hint_range(0.0, 6.0) = 6.0;
varying vec4 tint;

void vertex() { tint = COLOR; }

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	// Classify the authored texel to preserve the frame while clipping health.
	vec2 texel_center = (floor(UV * vec2(96.0, 16.0)) + vec2(0.5)) / vec2(96.0, 16.0);
	vec4 authored = texture(TEXTURE, texel_center);
	// Only authored #2cf7a3 pixels are depleted. Frame, icon and red frames stay intact.
	if (authored.a > 0.5 && distance(authored.rgb, vec3(44.0, 247.0, 163.0) / 255.0) < 0.01) {
		float x = floor(UV.x * 96.0);
		float block_index = 0.0;
		float start = 16.0;
		float width = 8.0;
		if (x >= 71.0) { block_index = 5.0; start = 71.0; width = 10.0; }
		else if (x >= 59.0) { block_index = 4.0; start = 59.0; width = 10.0; }
		else if (x >= 48.0) { block_index = 3.0; start = 48.0; width = 9.0; }
		else if (x >= 38.0) { block_index = 2.0; start = 38.0; width = 9.0; }
		else if (x >= 26.0) { block_index = 1.0; start = 26.0; width = 9.0; }
		float fraction = clamp(health_blocks - block_index, 0.0, 1.0);
		if ((x - start + 0.5) / width > fraction) { pixel = vec4(0.0); }
	}
	COLOR = pixel * tint;
}
