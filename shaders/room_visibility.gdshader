shader_type canvas_item;
render_mode unshaded;

// Grade the world snapshot; this permits gains above 1 in LDR without washing out black.
// HUD draws afterwards on higher canvases and is never included in this snapshot.
uniform sampler2D world_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 ambient_multiplier : source_color = vec4(0.92, 0.90, 0.96, 1.0);
uniform vec4 center_multiplier : source_color = vec4(1.12, 1.08, 1.16, 1.0);
uniform float saturation = 1.0;
uniform float radius = 30.8;
uniform float clear_center_ratio = 0.0;
uniform vec2 center_world = vec2(0.0);
uniform vec2 world_origin = vec2(0.0);
uniform vec2 world_axis_x = vec2(480.0, 0.0);
uniform vec2 world_axis_y = vec2(0.0, 270.0);
uniform bool has_subject = true;
uniform float pixel_size = 2.0;
uniform float brightness_steps = 0.0;

void fragment() {
	vec2 world_position = world_origin + UV.x * world_axis_x + UV.y * world_axis_y;
	if (pixel_size >= 1.0) {
		world_position = (floor(world_position / pixel_size) + vec2(0.5)) * pixel_size;
	}
	float outer = max(radius, 1.0);
	float inner = outer * clamp(clear_center_ratio, 0.0, 0.95);
	float falloff = has_subject ? smoothstep(inner, outer, distance(world_position, center_world)) : 1.0;
	if (brightness_steps >= 2.0) {
		falloff = floor(falloff * brightness_steps + 0.5) / brightness_steps;
	}
	vec4 source_pixel = texture(world_screen, SCREEN_UV);
	vec3 graded = source_pixel.rgb * mix(center_multiplier.rgb, ambient_multiplier.rgb, falloff);
	float luminance = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	graded = mix(vec3(luminance), graded, saturation);
	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), source_pixel.a);
}
