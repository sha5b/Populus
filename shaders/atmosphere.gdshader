shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 atmosphere_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform vec4 sunset_color : source_color = vec4(0.8, 0.4, 0.2, 1.0);
uniform vec4 night_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	fresnel = smoothstep(0.0, 1.0, fresnel);

	float sun_dot = dot(NORMAL, -sun_direction);
	
	vec3 day_col = mix(sunset_color.rgb, atmosphere_color.rgb, smoothstep(0.0, 0.3, sun_dot));
	vec3 final_color = mix(night_color.rgb, day_col, smoothstep(-0.2, 0.2, sun_dot));

	ALBEDO = final_color * fresnel * atmosphere_density * 2.0;
	ALPHA = fresnel * 0.3 * atmosphere_density;
}
