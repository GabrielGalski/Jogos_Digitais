shader_type canvas_item;
uniform vec4 from_colors[6];
uniform vec4 to_colors[6] : source_color;
uniform int color_count = 3;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
varying vec4 sprite_modulation;

void vertex() {
	sprite_modulation = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	// The sheets contain a baked translucent shadow; the actor supplies a ground shadow.
	if (pixel.a < 0.5) discard;
	vec3 source = round(pixel.rgb * 255.0);
	for (int i = 0; i < 6; i++) {
		if (i < color_count && distance(source, round(from_colors[i].rgb * 255.0)) < 0.5) {
			pixel.rgb = to_colors[i].rgb;
			break;
		}
	}
	pixel.rgb = mix(pixel.rgb, vec3(1.0), flash_amount);
	COLOR = pixel * sprite_modulation;
}
