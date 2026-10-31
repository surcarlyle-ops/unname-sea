shader_type spatial;
// (CodeBuddy) 岸边钓场的静水池塘水面。
//
// 之前用三条固定方向的 sin 叠加，32 米的池子上会露出规则的平行斜带——一眼就是
// "波纹贴图被拉大"。现在换成多尺度值噪声：低频是大面积缓坡涌动，高频是细碎风纹，
// 没有可见的重复方向；法线用中心差分求梯度，配合菲涅尔天空反射与太阳高光，
// 静水在低角度看过去会有一条碎金反光带。
//
// 顶点色 r = 离最近岸边的距离（0 岸边 → 1 池心），由 shore_test_area.gd 烘焙。
// 只有 Compatibility 渲染器也能用的东西：噪声、导数、相机位置，没有屏幕纹理/SSR。
// shadows_disabled：水面不该像漫反射地面那样吃树影（左侧高树会在池子里投出一条
// 硬边黑带）。水的明暗来自法线反射与菲涅尔，关掉阴影图才像水。
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec4 deep_color : source_color = vec4(0.04, 0.29, 0.33, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.42, 0.82, 0.69, 1.0);
// 地平线 / 天顶两段天空色：菲涅尔反射按反射向量的仰角在两者之间取色。
uniform vec4 sky_color : source_color = vec4(0.68, 0.80, 0.84, 1.0);
uniform vec4 sky_zenith_color : source_color = vec4(0.34, 0.56, 0.72, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 0.95, 1.0);
// 指向太阳的方向（世界空间，y 向上），由场景脚本按主光方向设置。
uniform vec3 sun_direction = vec3(-0.42, 0.62, -0.62);
uniform vec4 sun_color : source_color = vec4(1.0, 0.96, 0.86, 1.0);

uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.48;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.94;
uniform float wave_strength : hint_range(0.0, 0.08) = 0.012;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.20;
uniform float flow_speed : hint_range(0.0, 3.0) = 1.0;
uniform float ripple_scale : hint_range(0.2, 4.0) = 1.0;
uniform float fresnel_boost : hint_range(0.0, 2.0) = 1.1;
uniform float sun_glint : hint_range(0.0, 3.0) = 1.0;
uniform float foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform float detail_fade_start = 16.0;
uniform float detail_fade_end = 55.0;
// 运行时生成的可平铺法线纹理：细碎波纹全靠它，程序化噪声叠到第 5 层
// GLES3 编译器会直接 OOM（Program linking failed）。
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 多层：大缓坡 + 风纹 + 细纹 + 顺风拉长的细条 + 碎光。
// 顺风层是压扁的噪声（x 拉长 3 倍），静水在低角度看才有"一条条"的感觉，而不是一锅气泡。
float water_height(vec2 p, float t) {
	float h = 0.0;
	h += vnoise(p * 0.42 + vec2(t * 0.055, -t * 0.042)) * 0.56;
	h += vnoise(p * 0.95 + vec2(-t * 0.105, t * 0.082)) * 0.26;
	h += vnoise(p * 2.10 + vec2(t * 0.190, t * 0.145)) * 0.12;
	h += vnoise(vec2(p.x * 0.55, p.y * 1.90) + vec2(t * 0.240, -t * 0.050)) * 0.10;
	return h;
}

// 法线纹理的坡度：单独包一层，别在表达式里直接对 texture() 取 swizzle，
// GLES3 的编译器偶尔会在这上面报 "invalid atom in swizzle"。
vec2 ripple_slope(vec2 uv) {
	vec4 sample_color = texture(ripple_normal, uv);
	return sample_color.xy * 2.0 - 1.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * flow_speed;
	// 顶点只抬几毫米：静水要平，起伏交给法线。
	VERTEX.y += (water_height(world_pos.xz * ripple_scale, t) - 0.5) * wave_strength;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec2 p = world_pos.xz * ripple_scale;
	float t = TIME * flow_speed;

	// 低频：中心差分求高度梯度，负责大面积的缓慢涌动。
	float e = 0.09;
	float h0 = water_height(p, t);
	float hx = water_height(p + vec2(e, 0.0), t);
	float hz = water_height(p + vec2(0.0, e), t);
	// 低频只留一点：给太多会把太阳碎金糊成一整块白斑。
	vec2 swell = vec2(hx - h0, hz - h0) / e * 0.12;
	// 高频：三层不同尺度、不同漂移方向的法线纹理，叠出细碎风纹；
	// 一层是 1.7 m 的波纹，一层 0.7 m，一层 0.3 m 的碎光。
	vec2 ripple = ripple_slope(world_pos.xz * 0.06 + vec2(t * 0.010, -t * 0.007)) * 0.62;
	ripple += ripple_slope(world_pos.xz * 0.15 + vec2(-t * 0.022, t * 0.016)) * 0.34;
	ripple += ripple_slope(world_pos.xz * 0.36 + vec2(t * 0.040, t * 0.030)) * 0.18;
	float detail = 1.0 - smoothstep(detail_fade_start, detail_fade_end, distance(CAMERA_POSITION_WORLD, world_pos));
	vec3 normal = normalize(vec3(-(swell.x + ripple.x) * normal_strength * detail, 1.0, -(swell.y + ripple.y) * normal_strength * detail));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);

	float channel = clamp(COLOR.r, 0.0, 1.0);
	// 0.10 起才算深水：岸边留一圈透出沙子的清浅区，别整片池子一个颜色。
	float depth = smoothstep(0.10, 0.85, channel);
	float facing = clamp(dot(normal, view_dir), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);

	// 天空反射：反射向量越朝天顶越蓝，地平线附近偏奶白。
	vec3 reflected = reflect(-view_dir, normal);
	float sky_t = clamp(reflected.y * 1.35 + 0.20, 0.0, 1.0);
	vec3 sky = mix(sky_color.rgb, sky_zenith_color.rgb, sky_t);

	vec3 body = mix(shallow_color.rgb, deep_color.rgb, depth);
	// 0.34 封顶，浅滩再减半：低角度看过去整片水面都会吃菲涅尔，不压住就成一块奶白玻璃。
	float sky_mix = clamp(fresnel * fresnel_boost * 1.1, 0.0, 0.34) * mix(0.5, 1.0, depth);
	body = mix(body, sky, sky_mix);
	// 轻微斑驳：纯渐变会让整池子像一块塑料，低频噪声把颜色打散一点点。
	float mottle = vnoise(world_pos.xz * 0.23 + vec2(t * 0.02, -t * 0.013));
	body *= 0.94 + 0.12 * mottle;

	// 太阳高光：一个很锐的碎金点 + 一层窄油光；宽瓣太亮会在水面糊出一块白斑。
	vec3 half_vec = normalize(normalize(sun_direction) + view_dir);
	float facing_sun = clamp(dot(normal, half_vec), 0.0, 1.0);
	float glint = pow(facing_sun, 320.0) * 0.75 + pow(facing_sun, 90.0) * 0.012;
	body += sun_color.rgb * glint * sun_glint * detail;

	// 岸线泡沫：只在最外 10 厘米出现，加一圈贴岸的细白边。
	// 之前 0.22 的宽度在静水池上像一圈洗衣粉，浅滩整片发白。
	float edge = 1.0 - smoothstep(0.0, 0.10, channel);
	float foam_noise = vnoise(p * 3.2 + vec2(t * 0.30, -t * 0.24));
	float foam_noise2 = vnoise(p * 7.4 - vec2(t * 0.46, t * 0.38));
	float foam = smoothstep(0.42, 0.86, foam_noise * 0.62 + foam_noise2 * 0.38) * edge;
	foam += (1.0 - smoothstep(0.0, 0.03, channel)) * 0.45;
	foam = clamp(foam * foam_amount, 0.0, 1.0);
	body = mix(body, foam_color.rgb, foam * 0.65);
	// 极窄的一圈湿边压暗，水面不会像一块浮在沙子上的玻璃。
	body *= mix(0.80, 1.0, smoothstep(0.0, 0.09, channel));

	// 水不是漫反射面：把一半颜色放进 EMISSION，ALBEDO 只留 45%。
	// 直接给满 ALBEDO 会被天光再乘一遍，整池水被顶成奶青色。
	ALBEDO = body * 0.40;
	EMISSION = body * 0.60;
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	ALPHA = clamp(mix(alpha_shallow, alpha_deep, depth) + fresnel * 0.10 + foam * 0.30, 0.08, 1.0);
}
