shader_type canvas_item;
render_mode unshaded;
uniform float reveal : hint_range(0.0,1.0) = 1.0;
uniform float whiten : hint_range(0.0,1.0) = 0.0;
varying vec4 tint;
void vertex(){tint=COLOR;}
void fragment(){
	vec4 pixel = texture(TEXTURE,UV)*tint;
	vec2 cell = floor(UV/TEXTURE_PIXEL_SIZE);
	float grain = fract(sin(dot(cell,vec2(37.1,17.7)))*43758.5453);
	// A vertical pixel scan follows the beam; grain only breaks the advancing edge.
	float row_edge = (cell.y+grain)*TEXTURE_PIXEL_SIZE.y;
	pixel.a *= step(row_edge,clamp(reveal,0.0,1.0));
	if(reveal<=0.0){pixel.a=0.0;}
	pixel.rgb = mix(pixel.rgb,vec3(1.0,0.98,0.98),whiten);
	COLOR=pixel;
}
