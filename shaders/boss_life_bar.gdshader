shader_type canvas_item;
render_mode unshaded;
uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float damage_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 light_row : source_color = vec4(0.694117647, 0.298039216, 0.278431373, 1.0);
uniform vec4 middle_row : source_color = vec4(0.62745098, 0.145098039, 0.121568627, 1.0);
uniform vec4 dark_row : source_color = vec4(0.517647059, 0.121568627, 0.101960784, 1.0);
void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    vec2 at = floor(UV * vec2(288.0, 32.0));
    // Only authored red pixels are health: ornaments and ASTERION stay intact.
    bool is_fill = pixel.r > pixel.g * 1.7 && pixel.g > 0.10 && pixel.b < pixel.r * 0.55 && pixel.a > 0.5;
    if (is_fill) {
        float fraction = (at.x - 11.0 + 0.5) / 267.0;
        if (fraction >= health_ratio) {
            pixel.rgb = fraction < damage_ratio ? vec3(0.48, 0.27, 0.29) : vec3(0.145, 0.075, 0.102);
        } else {
            pixel = at.y < 22.0 ? light_row : (at.y < 24.0 ? middle_row : dark_row);
        }
    }
    COLOR = pixel;
}
