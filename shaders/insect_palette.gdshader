shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shell_light : source_color = vec4(0.823529, 0.682353, 0.784314, 1.0);
uniform vec4 shell_shade : source_color = vec4(0.439216, 0.321569, 0.435294, 1.0);
uniform vec4 cloth : source_color = vec4(0.658824, 0.537255, 0.639216, 1.0);
uniform vec4 blade : source_color = vec4(0.941176, 0.890196, 0.921569, 1.0);
varying vec4 sprite_modulation;

void vertex() {
	sprite_modulation = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec3 source = round(pixel.rgb * 255.0);
	if (distance(source, vec3(64.0, 39.0, 81.0)) < 0.5) {
		pixel.rgb = shell_light.rgb;
	} else if (distance(source, vec3(30.0, 29.0, 57.0)) < 0.5) {
		pixel.rgb = shell_shade.rgb;
	} else if (distance(source, vec3(59.0, 26.0, 60.0)) < 0.5) {
		pixel.rgb = cloth.rgb;
	} else if (distance(source, vec3(148.0, 148.0, 185.0)) < 0.5) {
		pixel.rgb = blade.rgb;
	}
	pixel.rgb = mix(pixel.rgb, vec3(1.0), flash_amount);
	COLOR = pixel * sprite_modulation;
}
