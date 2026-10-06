shader_type canvas_item;
render_mode unshaded;
uniform vec4 shadow_color : source_color = vec4(0.09, 0.059, 0.106, 1.0);
uniform vec4 midtone_color : source_color = vec4(0.412, 0.251, 0.322, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.965, 0.929, 0.898, 1.0);
uniform float world_palette_mix : hint_range(0.0, 0.4) = 0.18;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    vec4 pixel = texture(TEXTURE, UV) * tint;
    float value = max(pixel.r, max(pixel.g, pixel.b));
    float chroma = value - min(pixel.r, min(pixel.g, pixel.b));
    float dark = 1.0 - smoothstep(0.12, 0.40, value);
    // Hue remains the gameplay accent; only dark and secondary tones join the world.
    vec3 integrated = mix(pixel.rgb, midtone_color.rgb, world_palette_mix * (1.0 - smoothstep(0.4, 0.82, value)));
    integrated = mix(integrated, shadow_color.rgb, dark * 0.72);
    float highlight = smoothstep(0.83, 0.99, value) * (1.0 - smoothstep(0.05, 0.32, chroma));
    integrated = mix(integrated, highlight_color.rgb, highlight * 0.65);
    COLOR = vec4(integrated, pixel.a);
}
