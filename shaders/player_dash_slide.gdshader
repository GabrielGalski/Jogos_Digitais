shader_type canvas_item;
render_mode unshaded;

uniform float slide_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 slide_tint : source_color = vec4(1.0);
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// Recolor the real animation frame, preserving its authored silhouette and alpha.
	COLOR = vec4(mix(source.rgb, slide_tint.rgb, slide_mix), source.a) * tint;
}
