shader_type canvas_item;
render_mode unshaded;
varying vec4 vertex_tint;

void vertex() { vertex_tint = COLOR; }

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec3 rgb = round(pixel.rgb * 255.0);
	// Leave the authored dark portal arch unchanged; map only sandstone and moss.
	if (distance(rgb, vec3(189.0,177.0,138.0)) < 0.5) pixel.rgb = vec3(158.0,132.0,153.0)/255.0;
	else if (distance(rgb, vec3(157.0,135.0,112.0)) < 0.5) pixel.rgb = vec3(107.0,80.0,104.0)/255.0;
	else if (distance(rgb, vec3(180.0,159.0,125.0)) < 0.5) pixel.rgb = vec3(133.0,105.0,128.0)/255.0;
	else if (distance(rgb, vec3(133.0,101.0,85.0)) < 0.5) pixel.rgb = vec3(79.0,56.0,77.0)/255.0;
	else if (distance(rgb, vec3(99.0,54.0,52.0)) < 0.5) pixel.rgb = vec3(46.0,34.0,47.0)/255.0;
	else if (distance(rgb, vec3(150.0,158.0,96.0)) < 0.5) pixel.rgb = vec3(117.0,110.0,128.0)/255.0;
	else if (distance(rgb, vec3(90.0,123.0,80.0)) < 0.5) pixel.rgb = vec3(69.0,63.0,81.0)/255.0;
	else if (distance(rgb, vec3(118.0,143.0,93.0)) < 0.5) pixel.rgb = vec3(91.0,85.0,105.0)/255.0;
	COLOR = pixel * vertex_tint;
}
