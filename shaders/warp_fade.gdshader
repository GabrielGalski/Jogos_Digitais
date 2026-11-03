shader_type canvas_item;
render_mode unshaded;
uniform float coverage : hint_range(0.0,1.0) = 1.0;
uniform vec2 logical_size = vec2(480.0,270.0);
void fragment() {
	vec2 cell = floor(UV*logical_size/2.0);
	float grain = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
	float alpha = floor(clamp(coverage,0.0,1.0)*8.0+grain)/8.0;
	COLOR = vec4(vec3(0.1451,0.0745,0.1020),alpha);
}
