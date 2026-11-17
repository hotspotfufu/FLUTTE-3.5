extends Area3D
## A firework rocket shot from the panda cannon. Flies forward trailing sparks
## and bursts into colourful fireworks when it hits something (or after a while).
## Hits: ninjas (defeated in 1 hit), the bear (3 damage), lanterns.

var dir := 1
var speed := 14.0
var damage := 3
var _t := 0.0
var _done := false
var _body: MeshInstance3D
var _trail: CPUParticles3D
var _color := Color(1.0, 0.5, 0.2)
var _base_y := 0.0

const COLORS := [Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.2), Color(0.35, 0.9, 1.0), Color(0.6, 1.0, 0.35), Color(1.0, 0.5, 1.0)]


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4       # world + enemies / lanterns
	monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	cs.shape = sph
	add_child(cs)
	_color = COLORS[randi() % COLORS.size()]
	# rocket body: a little glowing capsule with a hot tip
	var cap := CapsuleMesh.new()
	cap.radius = 0.09
	cap.height = 0.5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = _color.lerp(Color.WHITE, 0.35)
	cap.material = m
	_body = MeshInstance3D.new()
	_body.mesh = cap
	_body.rotation.z = PI * 0.5
	add_child(_body)
	# spark trail
	_trail = CPUParticles3D.new()
	_trail.amount = 40
	_trail.lifetime = 0.4
	_trail.local_coords = false
	_trail.direction = Vector3(-dir, 0, 0)
	_trail.spread = 25.0
	_trail.initial_velocity_min = 1.0
	_trail.initial_velocity_max = 2.5
	_trail.gravity = Vector3(0, -1.5, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	_trail.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_color = Color(1.0, 0.9, 0.5)
	q.material = pm
	_trail.mesh = q
	_trail.position = Vector3(-dir * 0.25, 0, 0)
	add_child(_trail)
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _t == 0.0:
		_base_y = global_position.y
	_t += delta
	global_position.x += dir * speed * delta
	global_position.y = _base_y + sin(_t * 18.0) * 0.06      # little wobble
	_body.rotation.x = _t * 20.0
	if _t > 1.3:
		_explode()


func _on_hit(other: Node) -> void:
	if _done or other.is_in_group("player"):
		return
	_explode.call_deferred()


func _explode() -> void:
	if _done:
		return
	_done = true
	_body.visible = false
	_trail.emitting = false
	set_deferred("monitoring", false)
	# damage everything close by
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 4
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit_ids := {}
	for r in space.intersect_shape(q, 16):
		var c: Object = r["collider"]
		if c == null or hit_ids.has(c.get_instance_id()):
			continue
		hit_ids[c.get_instance_id()] = true
		if c.has_method("take_hit"):
			c.call("take_hit", damage, self)
	var pl := get_tree().get_first_node_in_group("player")
	if pl and "_shake" in pl:
		pl.set("_shake", maxf(float(pl.get("_shake")), 0.1))
	# firework burst: two rings of colourful sparks
	for k in 2:
		var b := CPUParticles3D.new()
		b.one_shot = true
		b.emitting = false
		b.amount = 36
		b.lifetime = 0.8
		b.explosiveness = 1.0
		b.spread = 180.0
		b.initial_velocity_min = 3.5 + k * 2.0
		b.initial_velocity_max = 4.5 + k * 2.0
		b.gravity = Vector3(0, -2.5, 0)
		b.damping_min = 3.0
		b.damping_max = 4.0
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0))
		b.scale_amount_curve = curve
		var bq := QuadMesh.new()
		bq.size = Vector2(0.14, 0.14)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		bm.albedo_color = _color if k == 0 else COLORS[(COLORS.find(_color) + 2) % COLORS.size()]
		bq.material = bm
		b.mesh = bq
		add_child(b)
		b.emitting = true
	# flash
	var fl := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(1.8, 1.8)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = load(get_script().resource_path.get_base_dir() + "/flutte_enemy_base.gd").soft_texture()
	fm.albedo_color = Color(1.0, 0.95, 0.8, 0.9)
	fq.material = fm
	fl.mesh = fq
	add_child(fl)
	var tw := create_tween()
	tw.tween_property(fm, "albedo_color:a", 0.0, 0.25)
	tw.tween_interval(0.7)
	tw.tween_callback(queue_free)
	_pop_sound()


func _pop_sound() -> void:
	var rate := 22050
	var n := int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		lp += (randf_range(-1.0, 1.0) - lp) * 0.5
		var env := exp(-t * 14.0)
		var crackle := randf_range(-1.0, 1.0) * 0.3 * float(randf() < 0.08) * exp(-t * 4.0)
		data.encode_s16(i * 2, int(clampf((lp * 0.9 + crackle) * env, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	var a := AudioStreamPlayer.new()
	a.stream = w
	a.volume_db = -5.0
	add_child(a)
	a.play()
