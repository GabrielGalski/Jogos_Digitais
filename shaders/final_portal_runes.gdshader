shader_type canvas_item;
render_mode unshaded;
uniform int active_runes : hint_range(0,24) = 0;
uniform sampler2D rune_map : filter_nearest, repeat_disable;
uniform vec4 idle_color : source_color = vec4(0.243137,0.207843,0.274510,1.0);
uniform vec4 active_color : source_color = vec4(1.0,0.650980,0.337255,1.0);
uniform vec4 edge_color : source_color = vec4(0.929412,0.388235,0.160784,1.0);
varying vec4 vertex_tint;

void vertex() { vertex_tint = COLOR; }

float lit_at(vec2 uv) {
	float id = floor(texture(rune_map, uv).r * 255.0 + 0.5);
	return step(0.5, id) * step(id, float(active_runes));
}

void fragment() {
	float id = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	float core = step(0.5, id);
	float lit = lit_at(UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float halo = max(max(lit_at(UV+vec2(px.x,0.0)),lit_at(UV-vec2(px.x,0.0))),
		max(lit_at(UV+vec2(0.0,px.y)),lit_at(UV-vec2(0.0,px.y))));
	float wide = max(max(lit_at(UV+vec2(px.x,px.y)),lit_at(UV-vec2(px.x,px.y))),
		max(lit_at(UV+vec2(px.x,-px.y)),lit_at(UV+vec2(-px.x,px.y))));
	vec3 color = mix(idle_color.rgb, active_color.rgb, lit);
	float alpha = max(core, max(halo * 0.65, wide * 0.22));
	color = mix(edge_color.rgb, color, core);
	COLOR = vec4(color, alpha) * vertex_tint;
}
