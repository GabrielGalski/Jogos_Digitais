shader_type canvas_item;

#include "res://shaders/scenery_asset_palette.gdshaderinc"

void fragment() {
	COLOR.rgb = asset_colour(COLOR.rgb);
}
