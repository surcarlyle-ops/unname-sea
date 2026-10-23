shader_type spatial;
// (CodeBuddy) Mirrored copy used as a cheap planar reflection for the river.
//
// The copy is the scene flipped about y = plane_y, so anything the source has
// *below* the plane (the carved river bed, the channel walls) ends up *above* it
// after the flip and gets drawn over the bank. That is what produced the hard dark
// band along the waterline. Fragments above the plane are therefore discarded:
// a reflection can only ever be seen through the water, never beside it.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.36, 0.42, 0.46, 0.55);
uniform float plane_y = 0.0;
// Fade the reflection out with distance so the far end of the river does not turn
// into a flat dark stripe.
uniform float fade_start = 60.0;
uniform float fade_end = 190.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_pos.y > plane_y) {
		discard;
	}
	float depth_fade = 1.0 - smoothstep(fade_start, fade_end, length(VERTEX));
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = tint.a * depth_fade;
}
