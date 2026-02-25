shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 wind_drift = vec3(0.0);
uniform float morph_t = 0.0;
uniform float weather_darkness = 0.0;

void vertex() {
	vec3 dir = normalize(VERTEX);
	float r = length(VERTEX);

	// Drift along sphere surface: project wind onto tangent plane
	vec3 tangent_drift = wind_drift - dir * dot(wind_drift, dir);
	vec3 new_dir = normalize(dir + tangent_drift / max(r, 0.1));
	VERTEX = new_dir * r;

	// Gentle organic wobble
	float wobble = sin(TIME * 0.5 + VERTEX.x * 1.8 + VERTEX.z * 1.3) * 0.06
	             + sin(TIME * 0.3 + VERTEX.y * 2.5) * 0.04;
	VERTEX += new_dir * wobble;
}

void fragment() {
	vec3 base = COLOR.rgb;

	float ndv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - ndv, 1.5);
	base += vec3(fresnel * 0.12);

	float edge_alpha = smoothstep(0.0, 0.35, ndv);

	// Darken clouds during storms/hurricanes/blizzards
	base = mix(base, base * vec3(0.35, 0.35, 0.4), weather_darkness);

	ALBEDO = base;
	ALPHA = COLOR.a * edge_alpha;
}
