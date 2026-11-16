shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_orange : source_color = vec4(0.8, 0.470588, 0.105882, 1.0);
uniform vec4 golden_yellow : source_color = vec4(1.0, 0.831373, 0.282353, 1.0);
uniform vec4 bright_yellow : source_color = vec4(1.0, 0.913725, 0.513725, 1.0);
uniform vec4 highlight : source_color = vec4(1.0, 0.972549, 0.839216, 1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 source_pixel = texture(TEXTURE, UV);
	// The supplied frames share four exact reds. Keep every pixel and its alpha.
	vec3 color = shadow_orange.rgb;
	if (source_pixel.r > 0.95) {
		color = highlight.rgb;
	} else if (source_pixel.r > 0.82) {
		color = bright_yellow.rgb;
	} else if (source_pixel.r > 0.72) {
		color = golden_yellow.rgb;
	}
	COLOR = vec4(color, source_pixel.a) * vertex_tint;
}
