shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float elapsed = 0.0;
uniform vec4 glow_tint : source_color = vec4(1.0, 0.83, 0.36, 1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	float mask = texture(TEXTURE, UV).a;
	vec2 step_size = TEXTURE_PIXEL_SIZE * 2.0;
	float halo = (
		texture(TEXTURE, UV + vec2(step_size.x, 0.0)).a +
		texture(TEXTURE, UV - vec2(step_size.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(0.0, step_size.y)).a +
		texture(TEXTURE, UV - vec2(0.0, step_size.y)).a
	) * 0.10;
	float tick = floor(elapsed * 12.0) / 12.0;
	float shimmer = 0.88 + 0.12 * sin(tick * 4.0 + floor(UV.x * 128.0) * 0.35);
	float intensity = max(mask, halo) * energy * shimmer * (0.9 + pulse * 0.1);
	COLOR = vec4(glow_tint.rgb, intensity) * vertex_tint;
}
