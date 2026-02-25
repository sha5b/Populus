shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 atmosphere_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	fresnel = smoothstep(0.0, 1.0, fresnel);

	ALBEDO = atmosphere_color.rgb * fresnel * atmosphere_density;
	ALPHA = fresnel * 0.3 * atmosphere_density;
}
