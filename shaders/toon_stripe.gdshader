shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 stripe_color : source_color = vec3(0.9, 0.9, 0.9);
uniform float stripe_scale = 15.0;
uniform float stripe_width = 0.5;
uniform float stripe_angle = 0.0; // 0.0 for horizontal, 90.0 for vertical, etc.

void fragment() {
	// Generate stripes based on rotated UV
	float rad = radians(stripe_angle);
	vec2 rotated_uv = vec2(
		UV.x * cos(rad) - UV.y * sin(rad),
		UV.x * sin(rad) + UV.y * cos(rad)
	);
	
	float stripe_val = fract(rotated_uv.y * stripe_scale);
	float is_stripe = step(stripe_val, stripe_width);
	
	vec3 base_col = mix(primary_color, stripe_color, is_stripe);
	
	ALBEDO = base_col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
	METALLIC = 0.0;
}
