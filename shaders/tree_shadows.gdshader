shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform float strength : hint_range(0.0, 0.6) = 0.18;
uniform vec4 shadow_tint : source_color = vec4(0.145098, 0.074510, 0.101961, 1.0);

void fragment() {
	float coverage = step(0.5, texture(TEXTURE, UV).r);
	// White is neutral in multiplicative blending; no per-tree work occurs here.
	COLOR = vec4(mix(vec3(1.0), shadow_tint.rgb, coverage * strength), 1.0);
}
