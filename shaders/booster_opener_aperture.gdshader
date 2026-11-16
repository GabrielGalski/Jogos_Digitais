shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float elapsed = 0.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	float mask = texture(TEXTURE, UV).a;
	float tick = floor(elapsed * 12.0) / 12.0;
	float shimmer = 0.88 + 0.12 * sin(tick * 4.0 + floor(UV.x * 128.0) * 0.35);
	vec3 cyan = mix(vec3(0.13, 0.9, 1.0), vec3(0.8, 1.0, 1.0), shimmer * 0.7 + pulse * 0.3);
	COLOR = vec4(cyan, mask * energy * (0.85 + pulse * 0.15)) * vertex_tint;
}
