shader_type spatial;
// (CodeBuddy) 岸边钓场的草叶/芦苇/野花：与 Ultimate Stylized Nature 的浓密草丛呼应。
//
// 网格来自 shore_test_area.gd::_grass_mesh()，根部在 y=0、梢部在 y=0.30，
// 顶点色是根暗梢亮的渐变；MultiMesh 的每实例颜色再乘上去做冷暖变化。
// 摆动权重用 (VERTEX.y / 0.30)^2，根不动、梢摆得最厉害，
// 再叠一个低频阵风，整片草才不会同步摆动。
render_mode cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;

uniform float wind_strength : hint_range(0.0, 0.4) = 0.09;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.6;
// 草叶网格的标准高度（米）。芦苇整体放大后 VERTEX.y 会超过它，clamp 即可。
uniform float blade_height : hint_range(0.05, 2.0) = 0.20;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / blade_height, 0.0, 1.0);
	float weight = h * h;
	float gust = 0.55 + 0.45 * sin(TIME * 0.37 + world_pos.x * 0.06 + world_pos.z * 0.05);
	float phase = TIME * wind_speed + world_pos.x * 0.52 + world_pos.z * 0.44;
	VERTEX.x += sin(phase) * wind_strength * weight * gust;
	VERTEX.z += cos(phase * 0.87 + 0.6) * wind_strength * 0.6 * weight;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.96;
	SPECULAR = 0.04;
	// 草梢透光：逆光时边缘会亮一点，接近概念图那种阳光穿过草丛的感觉。
	// 0.35 太亮，整片草会发荧光绿，压到 0.12 只留一层薄光。
	BACKLIGHT = COLOR.rgb * 0.12;
}
