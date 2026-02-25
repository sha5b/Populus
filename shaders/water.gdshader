shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.15, 0.45, 0.55);
uniform vec3 deep_color : source_color = vec3(0.02, 0.06, 0.2);
uniform float depth_fade : hint_range(0.1, 20.0) = 6.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.88;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float wave_scale : hint_range(0.0, 0.1) = 0.02;

void vertex() {
	// Multi-octave wave displacement on sphere surface
	float wave1 = sin(VERTEX.x * 2.5 + TIME * wave_speed) * cos(VERTEX.z * 2.0 + TIME * wave_speed * 0.7);
	float wave2 = sin(VERTEX.y * 3.0 + VERTEX.x * 1.5 + TIME * wave_speed * 1.2) * 0.5;
	float wave3 = cos(VERTEX.z * 1.8 + VERTEX.y * 2.2 + TIME * wave_speed * 0.5) * 0.3;
	float wave = (wave1 + wave2 + wave3) * wave_scale;
	VERTEX += NORMAL * wave;
}

void fragment() {
	// Read scene depth behind this water pixel
	float raw_depth = texture(depth_texture, SCREEN_UV).r;

	// Reconstruct linear depth from depth buffer
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_behind = INV_PROJECTION_MATRIX * ndc;
	view_behind.xyz /= view_behind.w;
	float scene_depth = -view_behind.z;

	// Water surface depth in view space
	float water_depth = -VERTEX.z;

	// Thickness = how far the terrain is behind the water surface
	float thickness = max(scene_depth - water_depth, 0.0);

	// Depth-based color: shallow = light teal, deep = dark blue
	float depth_t = clamp(thickness / depth_fade, 0.0, 1.0);
	vec3 water_col = mix(shallow_color, deep_color, depth_t);

	// Fresnel — edges more reflective/opaque
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);

	// Alpha: shallow = see-through, deep = opaque
	float alpha = mix(0.15, max_alpha, depth_t);
	alpha = clamp(alpha + fresnel * 0.2, 0.0, max_alpha);

	// Subtle animated caustic highlights in shallow water
	float caustic = sin(UV.x * 40.0 + TIME * 0.6) * cos(UV.y * 35.0 + TIME * 0.4);
	caustic = caustic * 0.04 * (1.0 - depth_t);

	ALBEDO = water_col + vec3(caustic);
	ALPHA = alpha;
	SPECULAR = 0.5;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
}
