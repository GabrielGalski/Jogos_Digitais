shader_type canvas_item;

void fragment() {
	// Map the existing floor base to slate while retaining the tile shading and alpha.
	COLOR.rgb *= vec3(57.0, 54.0, 67.0) / vec3(83.0, 48.0, 72.0);
}
