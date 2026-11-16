shader_type canvas_item;
render_mode unshaded;

// View-dependent texture sampling adapted from the supplied cardHolo3 example.
uniform sampler2D foil_pattern : source_color, repeat_enable, filter_linear;
uniform sampler2D border_mask : filter_nearest;
uniform vec4 border_tint : source_color = vec4(1.0);
uniform vec2 view_tilt = vec2(0.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float mask = texture(border_mask, UV).r;
	vec3 foil = texture(foil_pattern, UV * 0.8 + view_tilt * 1.8).rgb;
	float sweep = UV.x * 1.7 + UV.y * 0.8 + view_tilt.x * 2.0 + view_tilt.y * 2.0 - TIME * 0.18;
	float highlight = pow(0.5 + 0.5 * sin(sweep * 6.283185), 10.0);
	float luminosity = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	float grain = dot(foil, vec3(0.333333));
	vec3 metallic = mix(border_tint.rgb, vec3(1.0), highlight * 0.55);
	metallic *= luminosity * (0.8 + grain * 0.25 + highlight * 0.2);
	base.rgb = mix(base.rgb, metallic, mask * strength);
	COLOR = base * vertex_tint;
}
