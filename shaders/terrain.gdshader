shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 world_normal;

void vertex() {
	world_normal = NORMAL;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
