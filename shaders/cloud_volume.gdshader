shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

void fragment() {
	vec3 base = COLOR.rgb;

	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	base += vec3(fresnel * 0.15);

	float edge_alpha = smoothstep(0.0, 0.3, abs(dot(NORMAL, VIEW)));

	ALBEDO = base;
	ALPHA = COLOR.a * edge_alpha;
}
