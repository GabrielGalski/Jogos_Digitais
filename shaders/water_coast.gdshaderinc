// Shared by standalone and combined foam passes for equivalent comparisons.
uniform vec4 foam_color : source_color = vec4(0.58, 0.68, 0.66, 1.0);
uniform float foam_width_px = 1.4;
uniform float foam_reach_px = 12.0;
uniform float foam_opacity = 0.7;
uniform float shore_wave_period_s = 5.5;
uniform float foam_coverage = 0.64;
uniform float foam_irregularity = 0.75;
uniform float foam_residue = 0.25;

float coast_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float coast_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(mix(coast_hash(cell), coast_hash(cell + vec2(1.0, 0.0)), local.x),
		mix(coast_hash(cell + vec2(0.0, 1.0)), coast_hash(cell + vec2(1.0)), local.x), local.y);
}

float coast_foam(vec2 p, vec4 field, float t, float aa) {
	float d = max(field.r, 0.0);
	float coarse = coast_noise(p * 0.018 + vec2(3.1, 7.6));
	float patches = coast_noise(p * 0.085 + vec2(t * 0.025, -t * 0.018));
	float coverage = smoothstep(1.0 - foam_coverage, 1.25 - foam_coverage, coarse * 0.55 + patches * 0.45);
	coverage = mix(foam_coverage, coverage, foam_irregularity);
	// At each phase wrap the front is fully invisible on both sides.
	float phase = fract(t / shore_wave_period_s + coarse * 1.7 + 0.045 * sin(p.x * 0.019 + p.y * 0.023 + t * 0.32));
	float envelope = smoothstep(0.0, 0.18, phase) * (1.0 - smoothstep(0.72, 1.0, phase));
	float width = foam_width_px * mix(1.0, 0.5 + patches, foam_irregularity);
	float front = mix(foam_reach_px, width * 0.45, smoothstep(0.0, 1.0, phase));
	float contact = (1.0 - smoothstep(width * 0.15, width + aa, d)) * (0.22 + patches * 0.16);
	float wave = 1.0 - smoothstep(width * 0.25, width * 0.8 + aa, abs(d - front));
	float residual = exp(-max(d - front, 0.0) / max(width * 2.5, 0.5));
	residual *= smoothstep(front - aa, front + width, d) * foam_residue * 0.4;
	float detail_visibility = 1.0 - smoothstep(1.2, 4.0, aa);
	float alpha = max(contact, max(wave * 0.8, residual) * envelope * detail_visibility);
	alpha *= coverage * foam_opacity * field.g;
	alpha *= 1.0 - smoothstep(foam_reach_px - aa, foam_reach_px, d);
	return clamp(alpha * foam_color.a, 0.0, 0.8);
}
