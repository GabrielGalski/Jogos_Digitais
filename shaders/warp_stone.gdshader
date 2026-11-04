shader_type canvas_item;
render_mode unshaded;
varying vec4 vertex_tint;
uniform bool hide_pillars = false;
uniform vec4 pillar_rects[4];
uniform bool pillar_only = false;
uniform vec4 pillar_rect = vec4(0.0);

void vertex() { vertex_tint = COLOR; }

// Keep the authored alpha and relief; replace sandstone/grey with local mauves.
vec3 stone_colour(float value) {
	vec3 dark = vec3(37.0, 19.0, 26.0) / 255.0;
	vec3 shade = vec3(68.0, 40.0, 63.0) / 255.0;
	vec3 middle = vec3(117.0, 83.0, 110.0) / 255.0;
	vec3 light = vec3(168.0, 132.0, 158.0) / 255.0;
	if (value < 0.30) return mix(dark, shade, smoothstep(0.04, 0.30, value));
	if (value < 0.65) return mix(shade, middle, smoothstep(0.30, 0.65, value));
	return mix(middle, light, smoothstep(0.65, 1.0, value));
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec2 point = UV / TEXTURE_PIXEL_SIZE;
	if (pillar_only && !(all(greaterThanEqual(point, pillar_rect.xy)) && all(lessThan(point, pillar_rect.xy + pillar_rect.zw)))) discard;
	if (hide_pillars) {
		for (int index = 0; index < 4; index++) {
			vec4 region = pillar_rects[index];
			if (all(greaterThanEqual(point, region.xy)) && all(lessThan(point, region.xy + region.zw))) pixel.a = 0.0;
		}
	}
	float value = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(stone_colour(value), pixel.a) * vertex_tint;
}
