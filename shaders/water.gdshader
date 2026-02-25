shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.05, 0.15, 0.5, 0.7);
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 2.0) = 0.3;

void vertex() {
	float wave = sin(VERTEX.x * 2.0 + TIME * wave_speed) * cos(VERTEX.z * 2.0 + TIME * wave_speed * 0.7);
	VERTEX += NORMAL * wave * wave_height;
}

void fragment() {
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
}
