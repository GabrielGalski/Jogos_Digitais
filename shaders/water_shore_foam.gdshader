shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/water_coast.gdshaderinc"
uniform float water_elapsed = 0.0;
uniform float animation_speed = 1.0;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 field = texture(TEXTURE, UV);
	// Derivatives must precede nonuniform discard/branches at the foam cutoff.
	float aa = max(fwidth(field.r), 0.25);
	if (field.r >= foam_reach_px || field.g <= 0.0) {
		discard;
	}
	float alpha = coast_foam(world_position, field, water_elapsed * animation_speed, aa);
	COLOR = vec4(foam_color.rgb, alpha);
}
