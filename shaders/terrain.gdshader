shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float planet_radius = 500.0;

varying float v_slope;

void vertex() {
	vec3 radial = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, radial));
}

void fragment() {
	vec3 col = COLOR.rgb;

	// Slope darkening: steep faces slightly darker
	col *= 1.0 - v_slope * 0.15;

	// Roughness: steep slopes rougher, flat areas smoother
	float roughness = 0.78 + v_slope * 0.12;

	ALBEDO = col;
	ROUGHNESS = clamp(roughness, 0.5, 0.95);
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
