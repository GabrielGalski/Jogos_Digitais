shader_type canvas_item;

// Extends the existing animated sprite above every reachable camera position.
// Repeats one complete 188 px link cycle without stretching the links.
uniform float length_pixels = 4800.0;
uniform float cycle_pixels = 188.0;
// The third link contains the authored sway; the first link is static in every frame.
uniform float source_offset_pixels = 376.0;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	float from_bottom = length_pixels - UV.y * 664.0;
	vec2 repeated_uv = vec2(UV.x, (source_offset_pixels + mod(UV.y * 664.0, cycle_pixels)) / 664.0);
	vec4 texel = texture(TEXTURE, repeated_uv);
	float depth = 1.0 - smoothstep(0.0, 240.0, from_bottom);
	texel.rgb *= mix(1.0, 0.48, depth);
	texel.a *= smoothstep(0.0, 40.0, from_bottom);
	COLOR = texel * sprite_tint;
}
