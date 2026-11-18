shader_type canvas_item;
render_mode unshaded;

uniform vec4 edge_color : source_color = vec4(0.1451, 0.0745, 0.1020, 1.0);
uniform vec4 plum_color : source_color = vec4(0.1412, 0.0745, 0.1804, 1.0);
uniform vec4 center_color : source_color = vec4(0.2784, 0.1490, 0.2471, 1.0);
uniform vec2 logical_size = vec2(480.0, 270.0);
uniform float reveal_pulse = 0.0;

void fragment() {
	vec2 uv = floor(UV * logical_size) / logical_size;
	vec2 centered = (uv - vec2(0.5, 0.48)) * vec2(logical_size.x / logical_size.y, 1.0);
	float focal = 1.0 - smoothstep(0.08, 0.75, length(centered));
	vec3 base = mix(edge_color.rgb, plum_color.rgb, 0.35 + uv.y * 0.3);
	base = mix(base, center_color.rgb, focal * 0.63);
	float grain = mod(floor(uv.x * logical_size.x) + floor(uv.y * logical_size.y), 2.0);
	base += vec3(grain * 0.003);
	base += vec3(0.10, 0.065, 0.105) * reveal_pulse * pow(focal, 3.0);
	COLOR = vec4(base, 1.0);
}
