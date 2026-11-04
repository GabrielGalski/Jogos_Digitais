shader_type canvas_item;
render_mode unshaded;

uniform sampler2D emission_mask : filter_nearest, repeat_disable;
uniform vec4 fill_colour : source_color = vec4(0.95686, 0.81961, 0.41569, 1.0);
uniform vec4 border_colour : source_color = vec4(0.43922, 0.27843, 0.19216, 1.0);
varying vec4 vertex_tint;

void vertex() { vertex_tint = COLOR; }

float inscription_at(vec2 uv) {
	vec2 mask = texture(emission_mask, uv).rg;
	return step(0.5, max(mask.r, mask.g));
}

void fragment() {
	float core = inscription_at(UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float edge = max(inscription_at(UV + vec2(px.x, 0.0)), inscription_at(UV - vec2(px.x, 0.0)));
	edge = max(edge, max(inscription_at(UV + vec2(0.0, px.y)), inscription_at(UV - vec2(0.0, px.y))));
	COLOR = vec4(mix(border_colour.rgb, fill_colour.rgb, core), max(core, edge)) * vertex_tint;
}
