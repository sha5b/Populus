shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec4 cloud_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.7;
uniform vec3 sun_direction = vec3(0.5, 0.8, 0.3);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 6; i++) {
		value += amp * noise(p);
		p *= 2.1;
		amp *= 0.48;
	}
	return value;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Soft circular shape
	float circle = 1.0 - smoothstep(0.3, 1.0, dist);
	if (circle < 0.01) discard;

	// Puffy noise - animates slowly for organic feel
	float slow_time = TIME * 0.03;
	vec2 noise_uv = UV * 3.0 + vec2(slow_time * 0.5, slow_time * 0.3);
	float n1 = fbm(noise_uv);
	float n2 = fbm(noise_uv * 2.3 + vec2(5.2, 1.3));
	float detail = n1 * 0.6 + n2 * 0.4;

	// Cloud density: thick center, wispy edges
	float density = circle * smoothstep(0.3, 0.6, detail);
	density *= smoothstep(0.0, 0.4, circle);

	// Fake volumetric lighting
	vec2 light_uv = uv - normalize(sun_direction.xz) * 0.15;
	float light_dist = length(light_uv);
	float lit_side = 1.0 - smoothstep(0.0, 0.8, light_dist);

	// Self-shadowing: darker in thick parts away from sun
	float shadow = 1.0 - (1.0 - detail) * 0.4;
	float rim_light = pow(1.0 - circle, 2.0) * 0.5;

	// Final color: bright lit side, grey shadowed core, silver lining
	vec3 base_col = cloud_tint.rgb;
	vec3 lit_col = base_col * (0.85 + lit_side * 0.25);
	vec3 dark_col = base_col * 0.55;
	vec3 col = mix(dark_col, lit_col, shadow);
	col += vec3(rim_light);

	float final_alpha = density * cloud_alpha;
	final_alpha = clamp(final_alpha, 0.0, 0.75);

	ALBEDO = col;
	ALPHA = final_alpha;
}
