shader_type spatial;
// (Claude Code) Horizon ridge card.
//
// The ridges are drawn past the depth-fog end (roughly 430 m), where a normal
// unshaded material would be blended away into the fog colour and disappear.
// The whole point of the tier is the silhouette against the sky, so this shader
// opts out of fog and carries the aerial perspective in its own tint instead.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, blend_mix;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ALPHA = COLOR.a * tint.a;
}
