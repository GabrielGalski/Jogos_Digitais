shader_type canvas_item;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 center = (floor(UV / texel) + vec2(0.5)) * texel;
	vec4 crisp = texture(TEXTURE, center);
	vec4 soft = texture(TEXTURE, UV);
	float minimum_alpha = min(min(texture(TEXTURE, UV + vec2(texel.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(texel.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, texel.y)).a,
		texture(TEXTURE, UV - vec2(0.0, texel.y)).a));
	float edge = 1.0 - step(0.99, min(soft.a, minimum_alpha));
	// Preserve the face's pixel detail; interpolate only the silhouette edge.
	COLOR = mix(crisp, soft, edge) * sprite_tint;
}
