extends Area3D
## A hanging red lantern. Hit it (staff, tail spin, beam or firework) to smash it:
## yellow bamboo sticks fall out (each heals Flutte), and some lanterns also
## drop a FIREWORK CANNON (4 rocket shots).

@export var drops_cannon := false
@export var yellow_sticks := 2

const PX := 1.5 / 150.0
var _dir := ""
var _sprite: Sprite3D
var _t := 0.0
var _broken := false
var _break_t := 0.0
var _rope: MeshInstance3D


func _ready() -> void:
	_dir = get_script().resource_path.get_base_dir()
	add_to_group("lanterns")
	collision_layer = 4          # "Enemies" layer so all of Flutte's attacks reach it
	collision_mask = 0
	monitorable = true
	monitoring = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.65
	cs.shape = sph
	add_child(cs)
	_sprite = Sprite3D.new()
	_sprite.texture = load(_dir + "/lantern.png")
	_sprite.region_enabled = true
	_sprite.pixel_size = PX
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.position = Vector3(0, -0.05, 0.3)
	add_child(_sprite)
	_frame(0)
	# a little string it hangs from
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(0.025, 1.4, 0.025)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.35, 0.12, 0.1)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mesh.material = rm
	_rope = MeshInstance3D.new()
	_rope.mesh = rope_mesh
	_rope.position = Vector3(0, 1.4, 0.28)
	add_child(_rope)
	_t = randf() * 10.0


func _frame(i: int) -> void:
	_sprite.region_rect = Rect2((i % 8) * 140, (i / 8) * 166, 140, 166)


func _process(delta: float) -> void:
	_t += delta
	if not _broken:
		_frame(int(_t * 3.0) % 2)
		rotation.z = sin(_t * 1.6) * 0.08          # gentle sway
		return
	_break_t += delta
	var seq := [2, 4, 9, 10, 6, 7, 8]
	var i := int(_break_t * 18.0)
	if i < seq.size():
		_frame(seq[i])
	_sprite.modulate.a = clampf(1.4 - _break_t * 2.0, 0.0, 1.0)
	if _break_t > 0.75:
		queue_free()


func on_staff_hit(by: Node) -> void:
	smash()


func take_hit(_amount: int, _from: Node = null) -> void:
	smash()


func smash() -> void:
	if _broken:
		return
	_broken = true
	set_deferred("monitorable", false)
	_rope.visible = false
	rotation.z = 0.0
	var pickup: Script = load(_dir + "/power_pickup.gd")
	for i in yellow_sticks:
		var s: Area3D = pickup.new()
		s.set("kind", "heal")
		get_parent().add_child(s)
		s.global_position = global_position
		s.set("velocity", Vector3(randf_range(-2.5, 2.5), randf_range(3.5, 5.5), 0))
	if drops_cannon:
		var c: Area3D = pickup.new()
		c.set("kind", "cannon")
		get_parent().add_child(c)
		c.global_position = global_position
		c.set("velocity", Vector3(0, 5.5, 0))
	_sparks()


func _sparks() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -7, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.75, 0.2)
	q.material = m
	p.mesh = q
	get_parent().add_child(p)
	p.global_position = global_position
	p.emitting = true
	p.finished.connect(p.queue_free)
