shader_type canvas_item;
render_mode unshaded;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() { COLOR = texture(TEXTURE, UV) * tint; }
