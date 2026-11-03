shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/terrain_scenery_grade.gdshaderinc"

uniform sampler2D water_mask : filter_nearest, repeat_disable;
uniform float water_elapsed = 0.0;
uniform float waterline_y = 0.0;
uniform vec2 flow_direction = vec2(0.08, 1.0);
uniform float flow_speed = 12.0;
uniform vec4 water_tint : source_color = vec4(0.11, 0.5, 0.57, 1.0);
varying vec2 world_position;
varying vec4 vertex_tint;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_tint = COLOR;
}

void fragment() {
	vec2 flow = length(flow_direction) > 0.001 ? normalize(flow_direction) : vec2(0.0, 1.0);
	vec2 moving_world = world_position - flow * flow_speed * water_elapsed;
	float wave = sin(moving_world.x * 0.12 + moving_world.y * 0.045) * 0.7;
	wave += sin(moving_world.x * 0.23 - water_elapsed * 1.1) * 0.3;
	float wet = texture(water_mask, UV).r;
	float depth = world_position.y - waterline_y - floor(wave * 1.2);
	float submerged = wet * smoothstep(-1.0, 3.0, depth);
	// Only underwater masonry refracts. Deck, rails and gameplay never move.
	vec2 offset = vec2(floor(wave * 1.1 + 0.5), 0.0) * TEXTURE_PIXEL_SIZE * submerged;
	vec2 sample_uv = clamp(UV + offset, TEXTURE_PIXEL_SIZE * 0.5, vec2(1.0) - TEXTURE_PIXEL_SIZE * 0.5);
	vec4 stone = texture(TEXTURE, sample_uv) * vertex_tint;
	stone.rgb = scenery_colour(stone.rgb);
	stone.rgb = mix(stone.rgb, water_tint.rgb * (0.62 + wave * 0.025), submerged * 0.55);
	stone.a *= mix(1.0, 0.58, submerged);
	COLOR = stone;
}
