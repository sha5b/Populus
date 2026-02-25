shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

uniform vec4 day_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform vec4 sunset_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform vec4 night_color : source_color = vec4(0.05, 0.05, 0.15, 1.0);
uniform float atmosphere_density : hint_range(0.0, 2.0) = 1.0;
uniform float time_of_day : hint_range(0.0, 24.0) = 12.0;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	vec3 atmo_color;
	if (time_of_day >= 7.0 && time_of_day < 18.0) {
		atmo_color = day_color.rgb;
	} else if (time_of_day >= 5.0 && time_of_day < 7.0) {
		float t = (time_of_day - 5.0) / 2.0;
		atmo_color = mix(sunset_color.rgb, day_color.rgb, t);
	} else if (time_of_day >= 18.0 && time_of_day < 20.0) {
		float t = (time_of_day - 18.0) / 2.0;
		atmo_color = mix(day_color.rgb, sunset_color.rgb, t);
	} else {
		atmo_color = night_color.rgb;
	}

	ALBEDO = atmo_color * fresnel * atmosphere_density;
	ALPHA = fresnel * 0.6 * atmosphere_density;
}
