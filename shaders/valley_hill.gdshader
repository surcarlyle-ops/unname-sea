shader_type spatial;
// (CodeBuddy) 岸边钓场谷壁：把"塑料球"变成有坡面明暗的低模山丘。
//
// 单纯的 StandardMaterial 球体在低角度阳光下是一整片平色，远看像塑料。
// 这里按世界高度做基色→顶色的渐变，再叠一点大块噪声，
// 远山用 haze 参数直接压进雾色，省掉 unshaded 的剪影感。
render_mode cull_back, diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.31, 0.42, 0.23, 1.0);
uniform vec4 top_color : source_color = vec4(0.50, 0.62, 0.35, 1.0);
uniform vec4 haze_color : source_color = vec4(0.82, 0.88, 0.82, 1.0);
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform float top_height : hint_range(1.0, 60.0) = 18.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.07;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp(world_pos.y / max(top_height, 0.001), 0.0, 1.0);
	vec3 shade = mix(base_color.rgb, top_color.rgb, smoothstep(0.0, 0.9, t));
	// 大块色斑：让坡面不是一整片平色，远看才有体积。
	float blotch = hash12(floor(world_pos.xz * 0.55)) - 0.5;
	shade *= 1.0 + blotch * grain_strength * 2.0;
	ALBEDO = mix(shade, haze_color.rgb, haze);
	ROUGHNESS = 0.96;
}
