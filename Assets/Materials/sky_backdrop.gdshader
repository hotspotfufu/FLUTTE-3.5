shader_type spatial;
// Painted sky gradient with a soft sun/moon disc.
// An orthographic camera sees the built-in sky as one flat colour,
// so the sky is drawn on a large quad attached behind the camera instead.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 top_color : source_color = vec4(0.93, 0.45, 0.66, 1.0);
uniform vec4 horizon_color : source_color = vec4(1.0, 0.82, 0.78, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform vec2 sun_position = vec2(0.78, 0.22);
uniform float sun_size = 0.05;
uniform float aspect = 2.0;

void fragment() {
	float t = smoothstep(0.0, 1.0, UV.y);
	vec3 c = mix(top_color.rgb, horizon_color.rgb, t);
	vec2 p = UV * vec2(aspect, 1.0);
	vec2 s = sun_position * vec2(aspect, 1.0);
	float d = distance(p, s);
	float disc = 1.0 - smoothstep(sun_size * 0.85, sun_size, d);
	float glow = (1.0 - smoothstep(0.0, sun_size * 5.0, d)) * 0.35;
	c = mix(c, sun_color.rgb, clamp(disc + glow, 0.0, 1.0) * sun_color.a);
	ALBEDO = c;
}
