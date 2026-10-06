shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 light_color : source_color = vec4(0.364706, 0.176471, 0.262745, 1.0);
uniform float door_width = 57.0;
uniform float reach = 36.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float depth = max(local_position.y, 0.0);
	// The spill follows the same floor skew as the hall's walking plane.
	float across = abs(local_position.x + depth * 0.428571 - door_width * 0.5);
	float width = door_width * 0.5 + depth * 0.16;
	float edge = 1.0 - smoothstep(width - 3.0, width + 7.0, across);
	float floor_fade = pow(max(1.0 - depth / reach, 0.0), 2.0);
	float above = smoothstep(-3.0, 0.0, local_position.y);
	float source = exp(-abs(local_position.y - 0.5) * 0.75);
	float intensity = edge * above * (floor_fade * 0.72 + source * 0.8);
	COLOR = vec4(light_color.rgb, intensity * strength);
}
