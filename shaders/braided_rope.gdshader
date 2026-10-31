shader_type spatial;
render_mode cull_back;
uniform float strand_repeats = 1.0;
void fragment() {
	float strand = sin(UV.x * 6.283185 * 6.0 + UV.y * strand_repeats * 6.283185);
	float fibre = sin(UV.x * 6.283185 * 24.0 - UV.y * strand_repeats * 12.56637);
	ALBEDO = mix(vec3(0.38, 0.27, 0.16), vec3(0.68, 0.54, 0.36), smoothstep(-0.8, 0.8, strand));
	ALBEDO *= 0.91 + fibre * 0.09;
	ROUGHNESS = 0.96;
}
