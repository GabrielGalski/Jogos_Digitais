// Shared scenery colour transform. Material presets retain their own strength.
uniform bool enabled = true;
uniform float brightness : hint_range(0.0, 1.5, 0.01) = 0.78;
uniform float saturation : hint_range(0.0, 1.5, 0.01) = 0.65;
uniform float contrast : hint_range(0.0, 1.5, 0.01) = 0.90;

vec3 scenery_colour(vec3 rgb) {
	if (!enabled) {
		return rgb;
	}
	float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luminance), rgb, saturation);
	// Dark pivot: soften bright details without washing dark floors to grey.
	graded = mix(vec3(0.15), graded, contrast) * brightness;
	return clamp(graded, vec3(0.0), vec3(1.0));
}
