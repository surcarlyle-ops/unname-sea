shader_type spatial;
// 樱花山谷的柔和卡通着色。
// 在保留 toon 分层光照的前提下，用世界坐标的程序化噪声给表面加细节：
// 明暗斑驳、粗糙度扰动、边缘暗化。不依赖任何外部贴图。
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.80, 0.88, 0.98, 1.0);
uniform float shadow_band : hint_range(0.0, 1.0) = 0.64;
uniform float sun_scale : hint_range(0.0, 4.0) = 1.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.34;

// ---- 新增：表面细节 ----
// 噪声尺度：石头要细密、地面要舒缓、木头要沿轴向拉伸。
uniform float grain_scale : hint_range(0.1, 30.0) = 3.0;
// 明暗斑驳强度：0 是原来的纯色，0.3 左右比较自然。
uniform float grain_strength : hint_range(0.0, 1.0) = 0.18;
// 粗糙度扰动：让高光和暗部不完全均匀。
uniform float grain_rough : hint_range(0.0, 1.0) = 0.16;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.86;
// 噪声往这个色偏移，而不是单纯压暗，避免脏。
uniform vec4 grain_tint : source_color = vec4(0.88, 0.90, 0.86, 1.0);
// 边缘暗化：模拟接触阴影，让物体和地面分得开。
uniform float edge_darken : hint_range(0.0, 1.0) = 0.14;
// 各向异性缩放，用于木纹这类沿一个方向拉长的纹理。
uniform vec3 grain_stretch = vec3(1.0, 1.0, 1.0);
// 0..1，越大越像被露水打湿（降低粗糙度、提高高光）。
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// 顶点色是按 sRGB 十六进制写进网格的，直接当线性反照率用会让整场景发白。
// 1 = 按 sRGB 解释并转线性（默认），0 = 保持原样。
uniform float vertex_srgb : hint_range(0.0, 1.0) = 1.0;
// 细节噪声随距离淡出：远处的高频噪声会变成砂纸和摩尔纹。
uniform float grain_fade_start : hint_range(0.0, 200.0) = 16.0;
uniform float grain_fade_end : hint_range(0.0, 400.0) = 65.0;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.23));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// 三层叠加，低频给大块斑驳、高频给颗粒。
float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 3; i++) {
		value += value_noise(p) * amplitude;
		p *= 2.07;
		amplitude *= 0.48;
	}
	return value;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sample_pos = world_pos * grain_scale * grain_stretch;
	float low = fbm(sample_pos);
	float high = fbm(sample_pos * 5.3);

	// 顶点色按 sRGB 写入网格，直接当线性反照率用会让整场景发白。
	vec3 vertex = COLOR.rgb;
	if (vertex_srgb > 0.5) {
		vertex = pow(vertex, vec3(2.2));
	}
	vec3 base = vertex * tint.rgb;
	// 远距离细节淡出，避免砂纸感和摩尔纹。
	float detail = 1.0 - smoothstep(grain_fade_start, grain_fade_end, length(VERTEX));
	// 低频噪声拉明暗对比，高频噪声做细颗粒。
	float shade = mix(0.62, 1.26, low);
	base *= mix(1.0, shade, grain_strength * detail);
	float grain = (high - 0.5) * grain_strength * 0.95 * detail;
	base *= 1.0 + grain;
	// 往 grain_tint 偏移，而不是单纯压暗，暗部才不会发灰。
	base = mix(base, base * grain_tint.rgb, grain_strength * detail * (1.0 - low) * 0.6);

	ALBEDO = base;
	float rough = base_roughness + (high - 0.5) * grain_rough * detail;
	rough = mix(rough, rough * 0.45, wetness);
	ROUGHNESS = clamp(rough, 0.06, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.16, 0.42, wetness);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float band = smoothstep(0.24, 0.56, wrapped);
	float shade = mix(shadow_band, 1.06, band);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * shade * sun_scale;

	// 边缘光：背光侧勾一层冷色，把物体从背景里剥出来。
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(fresnel, rim_power);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * rim * rim_strength * rim_color.rgb * sun_scale;

	// 边缘暗化：掠射角处压暗，模拟接触与转折处的积影。
	float contact = pow(fresnel, 1.6) * edge_darken;
	DIFFUSE_LIGHT *= 1.0 - contact;
}
