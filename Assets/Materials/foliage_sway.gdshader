shader_type spatial;
// Gentle wind sway for bamboo, leaves and blossoms.
// Works with MultiMeshInstance3D: per-instance colour arrives through COLOR.
// world_vertex_coords lets the sway depend on height above the ground,
// so tall bamboo bends at the top while the base stays planted.
render_mode world_vertex_coords, cull_disabled;

uniform float sway_strength = 0.004;
uniform float sway_speed = 1.1;
uniform float ground_y = 0.0;
uniform float roughness_value = 0.85;

void vertex() {
	float h = max(VERTEX.y - ground_y, 0.0);
	float phase = VERTEX.x * 0.35 + VERTEX.z * 0.6;
	float wave = sin(TIME * sway_speed + phase) + 0.35 * sin(TIME * sway_speed * 2.3 + phase * 1.7);
	VERTEX.x += wave * sway_strength * h * h;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
}
