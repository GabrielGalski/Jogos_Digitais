shader_type canvas_item;
render_mode unshaded;

uniform float flash_amount : hint_range(0.0, 1.0) = 1.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(mix(source.rgb, vec3(1.0), flash_amount), source.a) * tint;
}
