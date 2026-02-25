shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

void fragment() {
	vec3 base = COLOR.rgb;

	float ndv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - ndv, 1.5);
	base += vec3(fresnel * 0.1);

	float edge_alpha = smoothstep(0.0, 0.4, ndv);

	ALBEDO = base;
	ALPHA = COLOR.a * edge_alpha;
}
