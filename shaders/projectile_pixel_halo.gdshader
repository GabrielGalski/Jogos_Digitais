shader_type canvas_item;
render_mode unshaded, blend_add;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    float intensity = texture(TEXTURE, UV).a;
    float grain = mod(floor(FRAGCOORD.x) + mod(floor(FRAGCOORD.y), 2.0) * 2.0, 4.0) / 4.0;
    float alpha = floor(intensity * 4.0 + grain) / 4.0;
    COLOR = vec4(tint.rgb, alpha * tint.a);
}
