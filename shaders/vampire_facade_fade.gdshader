shader_type canvas_item;

uniform vec2 room_origin;
varying vec2 room_position;

void vertex() {
	room_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - room_origin;
}

void fragment() {
	// Fade only the two hanging facades. The middle corridor and stairs stay opaque.
	float left = 1.0 - smoothstep(192.0, 200.0, room_position.x);
	float right = smoothstep(296.0, 304.0, room_position.x);
	float depth = smoothstep(446.0, 504.0, room_position.y) * max(left, right);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.123, 0.088, 0.205), depth * 0.72);
	COLOR.a *= 1.0 - depth;
}
