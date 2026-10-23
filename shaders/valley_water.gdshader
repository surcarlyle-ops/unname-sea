shader_type spatial;
// (CodeBuddy) River surface for the cherry valley.
//
// Layer order matters here: the river bed is real geometry now, so the surface can
// stay fairly transparent and let the bed carry the depth. The mesh carries a
// per-vertex "how deep is the channel here" value in COLOR.r, which is what makes
// the middle of the river darker than the edges instead of a uniform blue plate.
//
// Ripples are three non-harmonic sine waves. The vertex displacement and the
// fragment normal are derived from the *same* height function, and the normal is
// built in world space and converted to view space once, so NORMAL and VIEW always
// share a space. Ripple detail fades with distance to stop sub-pixel shimmer.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.055, 0.145, 0.175, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.235, 0.375, 0.375, 1.0);
uniform vec4 sky_color : source_color = vec4(0.52, 0.60, 0.70, 1.0);
uniform vec4 foam_color : source_color = vec4(0.84, 0.90, 0.89, 1.0);
uniform float alpha_base : hint_range(0.0, 1.0) = 0.88;
uniform float wave_strength : hint_range(0.0, 0.2) = 0.03;
// Ripple slope used for the normal. Kept separate from the geometric displacement:
// a flat surface with a perfectly smooth normal just mirrors the sky and reads as
// a pale plate, so the normal needs far more amplitude than the mesh.
uniform float normal_strength : hint_range(0.0, 1.0) = 0.22;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.20;
uniform float fresnel_boost : hint_range(0.0, 2.0) = 0.40;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ripple_fade_start = 25.0;
uniform float ripple_fade_end = 95.0;

varying vec3 world_pos;

const vec2 DIR_A = vec2(0.94, 0.34);
const vec2 DIR_B = vec2(-0.55, 0.84);
const vec2 DIR_C = vec2(0.30, -0.95);
const float FREQ_A = 0.95;
const float FREQ_B = 1.85;
const float FREQ_C = 3.10;

// Height of the ripple field at a world xz position.
float ripple_height(vec2 p, float t) {
	return sin(dot(p, DIR_A) * FREQ_A + t * 0.85)
		+ 0.52 * sin(dot(p, DIR_B) * FREQ_B + t * 1.25)
		+ 0.22 * sin(dot(p, DIR_C) * FREQ_C + t * 1.75);
}

// Analytic gradient of the same field: the normal is derived, never faked.
vec2 ripple_gradient(vec2 p, float t) {
	return DIR_A * FREQ_A * cos(dot(p, DIR_A) * FREQ_A + t * 0.85)
		+ DIR_B * FREQ_B * 0.52 * cos(dot(p, DIR_B) * FREQ_B + t * 1.25)
		+ DIR_C * FREQ_C * 0.22 * cos(dot(p, DIR_C) * FREQ_C + t * 1.75);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = ripple_height(world_pos.xz, TIME * flow_speed);
	VERTEX.y += height * wave_strength;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * flow_speed;
	// Sub-pixel ripples are what makes water shimmer at distance; fade them out.
	float detail = 1.0 - smoothstep(ripple_fade_start, ripple_fade_end, length(VERTEX));
	vec2 slope = ripple_gradient(p, t) * normal_strength * detail;
	// Rain dimples: two offset phases so the drops never line up into a grid.
	slope += rain_amount * 0.10 * vec2(
		cos((p.x * 0.4 - p.y * 0.9) * 6.3 + TIME * 2.6) + 0.6 * cos((p.x * 0.8 + p.y * 0.3) * 9.1 - TIME * 3.4),
		sin((p.x * 0.4 - p.y * 0.9) * 6.3 + TIME * 2.6) + 0.6 * sin((p.x * 0.8 + p.y * 0.3) * 9.1 - TIME * 3.4));

	// World-space normal, converted to view space exactly once.
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// COLOR.r is baked by the mesh builder: 0 at the shoreline, 1 mid-channel.
	float channel = clamp(COLOR.r, 0.0, 1.0);
	float depth = smoothstep(0.05, 0.9, channel);

	// Facing term in view space, matching NORMAL.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);

	vec3 body = mix(shallow_color.rgb, deep_color.rgb, depth);
	// A gentle sky tint at grazing angles reads as reflected sky, not as white paint.
	body = mix(body, sky_color.rgb, fresnel * fresnel_boost * 0.45);
	// A soft shallow tint where the bed meets the surface. Kept wide and faint:
	// a hard bright band along the shore reads as a painted edge.
	float lip = (1.0 - smoothstep(0.0, 0.22, channel)) * (1.0 - fresnel);
	body = mix(body, foam_color.rgb, lip * 0.16);

	ALBEDO = body;
	// A wide, soft highlight: a near-mirror roughness turns the whole river into
	// one flat sky reflection in the Compatibility renderer.
	ROUGHNESS = mix(0.34, 0.16, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.34;
	ALPHA = clamp(alpha_base * mix(0.72, 1.0, depth) + fresnel * 0.08, 0.0, 1.0);
}
