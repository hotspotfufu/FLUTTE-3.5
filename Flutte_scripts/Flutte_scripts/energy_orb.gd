extends Area3D
## Flutte's special: a ball of red energy from his chest diamond, thrown forward.
## It flies straight, leaves a glowing trail, and bursts on the first opponent
## it touches. The burst hurts everything close by (8 damage: beats a ninja in
## one hit, takes a big chunk off the bear). Bamboo it passes is collected and
## lanterns it touches are smashed.

const SPEED := 15.0
const MAX_DIST := 20.0
const DAMAGE := 8
const BLAST_R := 1.8

var dir := 1.0
var thrower: Node = null

var _travel := 0.0
var _t := 0.0
var _done := false
var _ball: MeshInstance3D
var _ball_mat: ShaderMaterial
var _trail: CPUParticles3D
var _light: OmniLight3D
var _hit: Array = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 | 8          # "Enemies" + "Collectibles"
	monitoring = true
	monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.45
	cs.shape = sph
	add_child(cs)

	_ball_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ORB_SHADER
	_ball_mat.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	_ball = MeshInstance3D.new()
	_ball.mesh = q
	_ball.material_override = _ball_mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.position.z = 0.2
	add_child(_ball)

	_trail = CPUParticles3D.new()
	_trail.amount = 50
	_trail.lifetime = 0.4
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 0.22
	_trail.direction = Vector3(-dir, 0, 0)
	_trail.spread = 25.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 1.5
	_trail.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	_trail.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.85, 1.0))
	grad.set_color(1, Color(0.8, 0.0, 0.1, 0.0))
	_trail.color_ramp = grad
	var pq := QuadMesh.new()
	pq.size = Vector2(0.3, 0.3)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = _soft_tex()
	pq.material = pm
	_trail.mesh = pq
	_trail.position.z = 0.15
	add_child(_trail)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.25, 0.25)
	_light.light_energy = 2.0
	_light.omni_range = 4.0
	_light.position.z = 0.6
	add_child(_light)
	body_entered.connect(_on_body)
	area_entered.connect(_on_area)


func _physics_process(delta: float) -> void:
	_t += delta
	if _done:
		return
	var step := SPEED * delta
	global_position.x += dir * step
	_travel += step
	_ball.rotation.z = _t * 9.0
	var pulse := 1.0 + sin(_t * 30.0) * 0.07
	_ball.scale = Vector3.ONE * minf(1.0, _t * 8.0 + 0.3) * pulse
	if _travel >= MAX_DIST or _hits_wall():
		_burst()


func _hits_wall() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(dir * 0.5, 0, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	# only real walls stop it; one-way floating platforms let it fly through
	return not r.is_empty() and not (r.collider as Node).is_in_group("one_way_platform") and absf((r.normal as Vector3).x) > 0.7


func _on_body(b: Node) -> void:
	if _done or b == thrower:
		return
	if b.has_method("take_hit") and not ("dead" in b and b.get("dead")):
		_burst()


func _on_area(a: Area3D) -> void:
	if _done or a in _hit:
		return
	_hit.append(a)
	if a.has_method("on_staff_hit"):
		a.call("on_staff_hit", thrower)
	elif a.has_method("take_hit"):
		a.call("take_hit", DAMAGE, thrower)


func _burst() -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	# everything inside the blast takes the hit
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not e.has_method("take_hit"):
			continue
		var c: Vector3 = (e as Node3D).global_position + Vector3(0, 0.8, 0)
		if Vector2(c.x - global_position.x, (c.y - global_position.y) * 0.7).length() < BLAST_R + (1.0 if e.is_in_group("boss") else 0.0):
			e.call("take_hit", DAMAGE, self)
	if thrower and "_shake" in thrower:
		thrower.set("_shake", maxf(float(thrower.get("_shake")), 0.12))
	_trail.emitting = false
	_explosion()
	var tw := create_tween()
	tw.tween_method(func(v: float): _ball_mat.set_shader_parameter("pop", v), 0.0, 1.0, 0.3)
	tw.parallel().tween_property(_ball, "scale", Vector3.ONE * 2.6, 0.3)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.4)
	tw.tween_interval(0.3)
	tw.tween_callback(queue_free)


func _explosion() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 36
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector3(0, 1, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -5, 0)
	p.damping_min = 4.0
	p.damping_max = 6.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.9, 1.0))
	grad.set_color(1, Color(0.9, 0.05, 0.12, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	p.mesh = q
	p.position.z = 0.3
	add_child(p)
	p.emitting = true


static var _tex: GradientTexture2D
static func _soft_tex() -> GradientTexture2D:
	if _tex:
		return _tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(0.5, 0.0)
	_tex.width = 64
	_tex.height = 64
	return _tex


const ORB_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float pop = 0.0;     // 0 = flying ball, 1 = fully burst
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// swirling energy inside the ball
	float swirl = noise(vec2(a * 2.0 + r * 6.0 - TIME * 9.0, r * 5.0 - TIME * 4.0));
	float ball_r = 0.42 + 0.05 * swirl;
	float ball = 1.0 - smoothstep(ball_r - 0.06, ball_r + 0.02, r);
	float core = exp(-r * r * 30.0);
	float halo = exp(-r * r * 5.0) * 0.8;
	// ring that expands when it bursts
	float ring_r = mix(0.4, 0.95, pop);
	float ring = exp(-pow((r - ring_r) * 9.0, 2.0)) * pop;
	vec3 col = vec3(0.6, 0.0, 0.08) * halo
		+ mix(vec3(0.95, 0.08, 0.15), vec3(1.0, 0.45, 0.4), swirl) * ball
		+ vec3(1.0, 0.95, 0.9) * core
		+ vec3(1.0, 0.6, 0.55) * ring;
	float alpha = clamp(halo * 0.8 + ball + core + ring, 0.0, 1.0);
	alpha *= (1.0 - pop * pop) + ring;
	alpha *= 1.0 - smoothstep(0.85, 1.0, r);
	ALBEDO = col / max(alpha, 0.001);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
