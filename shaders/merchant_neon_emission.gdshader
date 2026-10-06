shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	// Preserve only the authored luminous pixels, not the sign's dark backing.
	float luminous = step(0.70, max(pixel.r, max(pixel.g, pixel.b)));
	COLOR = vec4(pixel.rgb, pixel.a * luminous);
}
