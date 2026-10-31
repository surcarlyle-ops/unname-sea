shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
varying vec3 blade_pos;
void vertex() {
    blade_pos = VERTEX;
    VERTEX += NORMAL * 0.0008;
}
void fragment() {
    float along = blade_pos.y;
    float across = blade_pos.z;
    float blade = smoothstep(0.48, 0.54, along);
    float branch = sin(along * 23.0) * 0.008 + sin(along * 47.0) * 0.003;
    float spine = 1.0 - smoothstep(0.001, 0.004, abs(across - branch));
    float veins = 1.0 - smoothstep(0.001, 0.0035, abs(abs(across) - 0.027 - branch));
    float pulse = pow(0.5 + 0.5 * sin(along * 19.0 - TIME * 6.0), 5.0);
    float mask = blade * (spine * (0.65 + pulse * 0.35) + veins * (0.45 + pulse * 0.50));
    ALBEDO = mix(vec3(0.01, 0.48, 0.43), vec3(0.28, 1.0, 0.85), pulse);
    ALPHA = clamp(mask * charge * 0.95, 0.0, 0.95);
}
