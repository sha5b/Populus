shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float drop_speed = 6.0;
uniform vec4 rain_color : source_color = vec4(0.7, 0.8, 0.9, 0.7);
uniform bool is_snow = false;
uniform bool is_active = true;

varying float v_rnd;
varying float v_intensity;

void vertex() {
	v_rnd = COLOR.r;
	v_intensity = COLOR.a;

	if (is_snow) {
		float sway = sin(TIME * 2.0 + v_rnd * 10.0) * 2.0;
		VERTEX.x += sway * (1.0 - UV.y);
		VERTEX.z += cos(TIME * 1.5 + v_rnd * 10.0) * 2.0 * (1.0 - UV.y);
	}
}

void fragment() {
	if (!is_active || v_intensity < 0.05) {
		discard;
	}

	float speed = is_snow ? (drop_speed * 0.3) : drop_speed;
	float t = fract(UV.y - TIME * speed + v_rnd);

	float drop = 0.0;
	if (is_snow) {
		drop = smoothstep(0.15, 0.0, length(vec2(UV.x - 0.5, t - 0.05) * vec2(2.0, 1.0)));
	} else {
		drop = smoothstep(0.4, 0.0, t) * smoothstep(0.0, 0.1, t);
	}

	float w = abs(UV.x - 0.5) * 2.0;
	float width_profile = smoothstep(1.0, 0.0, w);

	ALBEDO = is_snow ? vec3(1.0) : rain_color.rgb;

	float alpha_boost = is_snow ? 3.0 : 4.0;
	ALPHA = clamp(drop * width_profile * rain_color.a * v_intensity * alpha_boost, 0.0, 1.0);
}
