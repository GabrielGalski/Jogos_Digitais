shader_type canvas_item;
render_mode unshaded;
uniform vec4 element_color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float outline_pixels = 4.0;
varying vec4 modulation;

void vertex() {
	modulation = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * outline_pixels;
	float edge = max(max(texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a,
		texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a));
	vec3 fill = mix(pixel.rgb, element_color.rgb, 0.40);
	float alpha = max(pixel.a, edge * 0.9);
	COLOR = vec4(mix(element_color.rgb, fill, pixel.a), alpha) * modulation;
}
