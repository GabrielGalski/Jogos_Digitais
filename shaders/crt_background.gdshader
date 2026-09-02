shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.075, 0.38, 0.18, 1.0);
uniform float line_strength : hint_range(0.0, 0.25) = 0.10;
uniform float line_spacing : hint_range(8.0, 40.0) = 18.0;
uniform float line_speed : hint_range(0.0, 20.0) = 3.5;


void fragment() {
	// O sinal positivo de TIME faz o padrao se deslocar lentamente para cima.
	float logical_y = UV.y * 270.0;
	float phase = mod(logical_y + TIME * line_speed, line_spacing);
	float distance_to_line = min(phase, line_spacing - phase);
	float horizontal_line = 1.0 - smoothstep(0.0, 1.4, distance_to_line);

	vec3 line_color = base_color.rgb * 1.18;
	vec3 color = mix(base_color.rgb, line_color, horizontal_line * line_strength);
	COLOR = vec4(color, base_color.a);
}
