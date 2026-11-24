shader_type canvas_item;

uniform vec2 room_origin;
varying vec2 room_position;

void vertex() {
	room_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - room_origin;
}

void fragment() {
	// The front walls fade straight down. The opening has a hard edge at the rails.
	if (room_position.x < 293.0 || room_position.x >= 396.0) {
		COLOR.a *= 1.0 - smoothstep(684.0, 736.0, room_position.y);
	}
}
