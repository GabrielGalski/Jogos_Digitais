shader_type canvas_item;

// Reconstruct only the transparent silhouette. Opaque RGB stays point-sampled.
// Standalone animation frames are sampled from TEXTURE, so no texture binding
// or image upscaling is needed when AnimatedSprite2D changes its frame.
uniform float edge_strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.5, 1.5) = 1.0;
uniform float coverage_threshold : hint_range(0.35, 0.65) = 0.5;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

vec4 clear_outside(vec4 pixel, vec2 coordinate) {
	if (any(lessThan(coordinate, vec2(0.0))) || any(greaterThanEqual(coordinate, vec2(1.0)))) {
		return vec4(0.0);
	}
	return pixel;
}

vec4 premultiply(vec4 pixel) {
	return vec4(pixel.rgb * pixel.a, pixel.a);
}

void fragment() {
	vec2 grid_position = UV / TEXTURE_PIXEL_SIZE;
	vec2 point_uv = (floor(grid_position) + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
	vec4 point_pixel = clear_outside(texture(TEXTURE, point_uv), point_uv);
	vec2 cell = floor(grid_position - vec2(0.5));
	vec2 fraction = fract(grid_position - vec2(0.5));
	vec2 top_left_uv = (cell + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
	vec2 top_right_uv = top_left_uv + vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 bottom_left_uv = top_left_uv + vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	vec2 bottom_right_uv = top_left_uv + TEXTURE_PIXEL_SIZE;
	vec4 top_left = clear_outside(texture(TEXTURE, top_left_uv), top_left_uv);
	vec4 top_right = clear_outside(texture(TEXTURE, top_right_uv), top_right_uv);
	vec4 bottom_left = clear_outside(texture(TEXTURE, bottom_left_uv), bottom_left_uv);
	vec4 bottom_right = clear_outside(texture(TEXTURE, bottom_right_uv), bottom_right_uv);

	// Alpha-aware interpolation keeps transparent PNG RGB from creating halos.
	vec4 filtered = mix(
		mix(premultiply(top_left), premultiply(top_right), fraction.x),
		mix(premultiply(bottom_left), premultiply(bottom_right), fraction.x),
		fraction.y
	);
	// Reconstruct the half-coverage contour, rather than blur the entire sprite.
	// Derivatives keep the antialiasing band near one screen pixel while moving,
	// scaling, flipping or rotating; there is no temporal noise or screen effect.
	float antialias_width = clamp(fwidth(filtered.a) * 0.5 * edge_softness, 0.015, 0.5);
	float coverage = smoothstep(
		coverage_threshold - antialias_width,
		coverage_threshold + antialias_width,
		filtered.a
	);
	// Color is untouched inside the silhouette. Only newly covered edge pixels
	// need color from neighboring opaque texels (never a transparent black pixel).
	vec3 edge_rgb = filtered.rgb / max(filtered.a, 0.00001);
	vec3 rgb = point_pixel.a > 0.001 ? point_pixel.rgb : edge_rgb;
	float alpha = mix(point_pixel.a, coverage, edge_strength);
	COLOR = vec4(rgb, alpha) * sprite_tint;
}
