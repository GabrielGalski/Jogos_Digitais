shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
uniform float frames_per_second = 12.0;
varying vec4 vertex_tint;

void vertex() { vertex_tint = COLOR; }

float hash(vec2 value) { return fract(sin(dot(value, vec2(127.1,311.7))) * 43758.5453); }

void fragment() {
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	float frame = floor(elapsed * frames_per_second);
	float opening = step(0.5, texture(TEXTURE, UV).g);
	vec2 local = (pixel - vec2(95.5,46.0)) / vec2(25.5,25.0);
	float angle = atan(local.y,local.x);
	float radius = 0.69 + 0.18 * sin(angle * 3.0 + frame * 0.32) + 0.045 * sin(angle * 7.0 - frame * 0.21);
	float ring = 1.0 - step(0.037, abs(length(local) - radius));
	float noise = hash(pixel + vec2(frame * 17.0,frame * -9.0));
	float white = max(ring * step(0.23, noise), step(0.972, noise));
	// Strict white pixels or alpha zero: never a dark/opaque portal background.
	COLOR = vec4(1.0,1.0,1.0,opening * white) * vertex_tint;
}
