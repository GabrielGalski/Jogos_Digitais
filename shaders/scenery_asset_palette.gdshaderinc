// Exact source-palette substitution: preserve source art, alpha and pixel clusters.
// 0=original; 1=grass/borders; 2=stone paths; 3=tree; 4=solid floor; 5=cliff.
uniform int asset_palette : hint_range(0, 5) = 0;

bool palette_match(vec3 color, vec3 bytes) {
	return all(lessThan(abs(color - bytes / 255.0), vec3(0.0025)));
}

vec3 asset_colour(vec3 color) {
	if (asset_palette == 1) {
		if (palette_match(color, vec3(83.0,48.0,72.0))) return vec3(67.0,40.0,62.0)/255.0;
		if (palette_match(color, vec3(69.0,40.0,60.0))) return vec3(54.0,32.0,48.0)/255.0;
		if (palette_match(color, vec3(135.0,69.0,113.0))) return vec3(106.0,65.0,98.0)/255.0;
		if (palette_match(color, vec3(164.0,87.0,140.0))) return vec3(132.0,85.0,122.0)/255.0;
		if (palette_match(color, vec3(185.0,104.0,157.0))) return vec3(157.0,114.0,148.0)/255.0;
	} else if (asset_palette == 2) {
		if (palette_match(color, vec3(48.0,29.0,45.0))) return vec3(37.0,19.0,26.0)/255.0;
		if (palette_match(color, vec3(101.0,88.0,111.0))) return vec3(94.0,69.0,108.0)/255.0;
		if (palette_match(color, vec3(147.0,134.0,155.0))) return vec3(133.0,113.0,143.0)/255.0;
	} else if (asset_palette == 3) {
		if (palette_match(color, vec3(232.0,94.0,84.0))) return vec3(147.0,101.0,166.0)/255.0;
		if (palette_match(color, vec3(173.0,63.0,82.0))) return vec3(119.0,75.0,143.0)/255.0;
		if (palette_match(color, vec3(120.0,43.0,85.0))) return vec3(87.0,50.0,82.0)/255.0;
		if (palette_match(color, vec3(79.0,38.0,77.0))) return vec3(68.0,40.0,63.0)/255.0;
		if (palette_match(color, vec3(28.0,33.0,61.0))) return vec3(37.0,27.0,49.0)/255.0;
		if (palette_match(color, vec3(125.0,76.0,72.0))) return vec3(87.0,56.0,69.0)/255.0;
		if (palette_match(color, vec3(173.0,118.0,98.0))) return vec3(134.0,97.0,116.0)/255.0;
		if (palette_match(color, vec3(56.0,36.0,41.0))) return vec3(56.0,36.0,56.0)/255.0;
		if (palette_match(color, vec3(36.0,31.0,32.0))) return vec3(37.0,19.0,26.0)/255.0;
	}
	return color;
}
