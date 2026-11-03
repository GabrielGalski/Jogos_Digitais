shader_type canvas_item;
render_mode unshaded;

// Only the isolated central #25131a component is allowed to become white.
uniform sampler2D charge_mask : filter_nearest, repeat_disable;
uniform float charge_progress : hint_range(0.0, 1.0) = 0.0;
uniform float filled_y = 0.0;

float filled_mask(vec2 uv) {
	return texture(charge_mask, uv).a * step(uv.y, filled_y) * step(0.00001, charge_progress);
}

void fragment() {
	// Fragment COLOR already contains the texture sample and canvas modulation.
	vec4 base = COLOR;
	// Keep only authored opaque pixels: no translucent fringe or halo.
	if (base.a < 0.99) {
		discard;
	}
	float fill = filled_mask(UV);
	COLOR = vec4(mix(base.rgb, vec3(1.0), fill), 1.0);
}
