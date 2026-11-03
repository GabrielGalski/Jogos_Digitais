shader_type canvas_item;
render_mode unshaded;

uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform float gradient_softness = 0.12;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float front = mix(-gradient_softness, 1.0 + gradient_softness, reveal_progress);
	float white_mask = smoothstep(front - gradient_softness, front + gradient_softness, UV.y);
	COLOR = vec4(mix(source.rgb, vec3(1.0), white_mask), source.a) * vertex_tint;
}
