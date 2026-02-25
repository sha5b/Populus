shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.02;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float brightness : hint_range(0.0, 1.5) = 1.0;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 storm_color : source_color = vec4(0.4, 0.4, 0.45, 1.0);

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
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float lat_fade = 1.0 - pow(abs(uv.y - 0.5) * 2.0, 2.0);

	vec2 scroll = wind_direction * TIME * cloud_speed;
	float n1 = fbm(uv * 8.0 + scroll);
	float n2 = fbm(uv * 16.0 + scroll * 1.3 + vec2(5.0, 3.0));
	float cloud = n1 * 0.7 + n2 * 0.3;

	float threshold = 1.0 - cloud_coverage;
	float alpha = smoothstep(threshold - 0.1, threshold + 0.1, cloud) * lat_fade;

	vec3 col = mix(cloud_color.rgb, storm_color.rgb, cloud_coverage);
	col *= brightness;

	ALBEDO = col;
	ALPHA = alpha * 0.45;
}
