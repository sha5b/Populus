shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.12, 0.40, 0.50);
uniform vec3 deep_color : source_color = vec3(0.02, 0.06, 0.22);
uniform float depth_fade : hint_range(0.1, 40.0) = 12.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.75;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float wave_scale : hint_range(0.0, 0.1) = 0.02;
uniform float planet_radius : hint_range(1.0, 2000.0) = 500.0;

varying float vertex_alpha;
varying vec2 flow_dir;

void vertex() {
	vertex_alpha = COLOR.a;
	flow_dir = UV; // UV carries fluid sim flow velocity (flow_vx, flow_vy)

	// Normalize vertex by planet scale so wave frequency stays consistent
	float r_scale = planet_radius / 100.0;
	vec3 nv = VERTEX / r_scale;

	// Flow from fluid simulation influences wave direction
	float flow_mag = length(flow_dir);
	float flow_push = (flow_dir.x * 1.5 + flow_dir.y * 1.2) * min(flow_mag, 1.0);

	// Multi-octave waves driven by flow direction
	float phase = TIME * wave_speed;
	float wave1 = sin(nv.x * 2.5 + phase + flow_push) * cos(nv.z * 2.0 + phase * 0.7);
	float wave2 = sin(nv.y * 3.0 + nv.x * 1.5 + phase * 1.2 + flow_push * 0.5) * 0.5;
	float wave3 = cos(nv.z * 1.8 + nv.y * 2.2 + phase * 0.5) * 0.3;

	// Stronger waves where flow is stronger (stormy areas)
	float flow_boost = 1.0 + flow_mag * 2.0;
	float wave = (wave1 + wave2 + wave3) * wave_scale * r_scale * flow_boost;
	VERTEX += NORMAL * wave;
}

void fragment() {
	if (vertex_alpha < 0.01) {
		discard;
	}

	// Read scene depth behind this water pixel
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_behind = INV_PROJECTION_MATRIX * ndc;
	view_behind.xyz /= view_behind.w;
	float scene_depth = -view_behind.z;
	float water_depth = -VERTEX.z;
	float thickness = max(scene_depth - water_depth, 0.0);

	// Scale depth fade with planet size
	float scaled_depth_fade = depth_fade * (planet_radius / 100.0);
	float depth_t = clamp(thickness / scaled_depth_fade, 0.0, 1.0);

	// Depth-based color: shallow = light teal, deep = dark blue
	vec3 vertex_col = COLOR.rgb;
	vec3 depth_col = mix(shallow_color, deep_color, sqrt(depth_t));
	vec3 water_col = mix(vertex_col, depth_col, 0.5);

	// Fresnel — edges more reflective/opaque
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);

	// Alpha: shallow = very transparent, deep = gradually opaque
	// This lets you see underwater terrain through the water
	float base_alpha = mix(0.08, max_alpha, depth_t * depth_t);
	float alpha = max(vertex_alpha * 0.6, base_alpha);
	alpha = clamp(alpha + fresnel * 0.15, 0.0, max_alpha);

	ALBEDO = water_col;
	ALPHA = alpha;
	SPECULAR = 0.5;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
}
