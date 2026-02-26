shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

uniform vec4 fog_color : source_color = vec4(0.85, 0.85, 0.9, 0.4);
uniform bool is_active = true;

varying vec3 v_world_pos;
varying float v_density;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_density = COLOR.a;
}

void fragment() {
	if (!is_active || v_density < 0.01) {
		discard;
	}
	
	float n = sin(v_world_pos.x * 0.2 + TIME * 0.2) * cos(v_world_pos.z * 0.2 + TIME * 0.15);
	float noise = (n + 1.0) * 0.5;
	
	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * v_density * (0.5 + noise * 0.5);
}
