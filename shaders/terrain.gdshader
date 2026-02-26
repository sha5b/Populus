shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

uniform float planet_radius = 500.0;

varying float v_slope;
varying vec3 v_world_pos;

void vertex() {
	vec3 radial = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, radial));
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;

	// Local scale detail noise
	// Pseudo-random noise based on world position
	vec3 pos = v_world_pos * 0.5; // Scale for detail
	float n = fract(sin(dot(pos, vec3(12.9898, 78.233, 45.164))) * 43758.5453123);
	
	// Add subtle grainy detail to break up flat colors up close
	col *= 1.0 - (n * 0.05);

	// Slope darkening: steep faces slightly darker
	col *= 1.0 - v_slope * 0.15;

	// Roughness: steep slopes rougher, flat areas smoother
	float roughness = 0.78 + v_slope * 0.12;

	ALBEDO = col;
	ROUGHNESS = clamp(roughness, 0.5, 0.95);
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
