shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float echo : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    float edge = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.80, 1.0, UV.y));
    float tips = pow(sin(UV.x * PI), 0.45);
    float core = exp(-pow((UV.y - 0.70) * 13.0, 2.0));
    float streak = 0.6 + 0.4 * sin(UV.x * 65.0 - UV.y * 9.0 - TIME * 19.0);
    vec3 teal = mix(vec3(0.04, 0.62, 0.54), vec3(0.16, 0.90, 0.83), streak);
    ALBEDO = mix(teal, vec3(0.78, 1.0, 0.94), core);
    ALPHA = edge * tips * opacity * (0.35 + core * 0.65) * (1.0 - echo * 0.55);
}
