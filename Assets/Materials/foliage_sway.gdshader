shader_type spatial;
// Soft, rounded "storybook 3D" look for bamboo, leaves, bushes, flowers and blossoms.
// Works with MultiMeshInstance3D: per-instance colour arrives through COLOR.
// world_vertex_coords lets the sway depend on height above the ground,
// so tall bamboo bends at the top while the base stays planted.
render_mode world_vertex_coords, cull_disabled;

uniform float sway_strength = 0.004;
uniform float sway_speed = 1.1;
uniform float ground_y = 0.0;
uniform float roughness_value = 0.85;
// darker near the ground (fake contact shadow), brighter toward the top
uniform float ground_shade = 0.22;
uniform float shade_height = 0.8;
// soft light around the silhouette, like Kirby's rounded scenery
uniform float rim_amount = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.95, 1.0);
// lets light through thin things (leaves, petals)
uniform float backlight_amount = 0.0;

varying float v_height;

void vertex() {
	float h = max(VERTEX.y - ground_y, 0.0);
	v_height = h;
	float phase = VERTEX.x * 0.35 + VERTEX.z * 0.6;
	float wave = sin(TIME * sway_speed + phase) + 0.35 * sin(TIME * sway_speed * 2.3 + phase * 1.7);
	VERTEX.x += wave * sway_strength * h * h;
}

void fragment() {
	float near_ground = 1.0 - clamp(v_height / max(shade_height, 0.001), 0.0, 1.0);
	ALBEDO = COLOR.rgb * (1.0 - ground_shade * near_ground * near_ground);
	ROUGHNESS = roughness_value;
	RIM = rim_amount;
	RIM_TINT = 0.6;
	BACKLIGHT = vec3(backlight_amount) * COLOR.rgb;
}
