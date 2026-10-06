shader_type canvas_item;
render_mode unshaded, blend_add;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    // Four discrete levels, screen-space grain, no blurred bloom at pixel scale.
    float grain = mod(floor(FRAGCOORD.x) + mod(floor(FRAGCOORD.y), 2.0) * 2.0, 4.0) / 4.0;
    float opacity = floor(tint.a * 16.0 + grain) / 16.0;
    COLOR = vec4(tint.rgb, opacity);
}
