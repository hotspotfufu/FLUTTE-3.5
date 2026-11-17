extends Area3D
## Things that fall out of a smashed lantern:
##   kind = "heal"   -> a golden YELLOW bamboo stick: +15 health
##   kind = "cannon" -> a FIREWORK CANNON: +4 firework rockets
## They pop out, fall to the ground, then float there until Flutte grabs them.

@export var kind := "heal"
var velocity := Vector3.ZERO

var _dir := ""
var _landed := false
var _t := 0.0
var _visual: Node3D
var _taken := false

static var _heal_mesh: CylinderMesh


func _ready() -> void:
	_dir = get_script().resource_path.get_base_dir()
	add_to_group("pickups")
	collision_layer = 8      # "Collectibles"
	collision_mask = 2       # "Player"
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.45
	cs.shape = sph
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "cannon":
		var s := Sprite3D.new()
		s.texture = load(_dir + "/firework_cannon.png")
		s.pixel_size = 0.85 / 344.0
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		_visual.add_child(s)
		_add_halo(Color(1.0, 0.8, 0.3, 0.6), 1.3)
	else:
		var m := MeshInstance3D.new()
		m.mesh = _get_heal_mesh()
		m.rotation_degrees = Vector3(0, 0, 22)
		_visual.add_child(m)
		_add_halo(Color(1.0, 0.95, 0.4, 0.55), 1.0)
	body_entered.connect(_on_body)
	_t = randf() * 5.0


func _add_halo(c: Color, size: float) -> void:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	var h := MeshInstance3D.new()
	h.mesh = q
	h.position = Vector3(0, 0, -0.1)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(h)


func _physics_process(delta: float) -> void:
	_t += delta
	if _taken:
		return
	if not _landed:
		velocity.y -= 18.0 * delta
		var next := global_position + velocity * delta
		var from := global_position + Vector3(0, 0.1, 0)
		var q := PhysicsRayQueryParameters3D.create(from, next + Vector3(0, -0.45, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if velocity.y < 0.0 and not hit.is_empty():
			global_position = Vector3(next.x, (hit["position"] as Vector3).y + 0.55, 0)
			_landed = true
		else:
			global_position = Vector3(next.x, next.y, 0)
		if global_position.y < -8.0:
			queue_free()
	_visual.position.y = sin(_t * 3.0) * 0.08 if _landed else 0.0
	_visual.rotation.y = _t * 2.5 if kind == "heal" else sin(_t * 2.0) * 0.4


func _on_body(body: Node) -> void:
	_collect(body)


func on_staff_hit(by: Node) -> void:
	_collect(by)


func _collect(by: Node) -> void:
	if _taken or by == null or not by.is_in_group("player"):
		return
	_taken = true
	set_deferred("monitoring", false)
	if kind == "cannon":
		if by.has_method("add_rockets"):
			by.call("add_rockets", 4)
	else:
		if by.has_method("heal"):
			by.call("heal", 15)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y + 0.7, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3(1.6, 1.6, 1.6), 0.15)
	tw.chain().tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
	tw.chain().tween_callback(queue_free)


static func _get_heal_mesh() -> CylinderMesh:
	if _heal_mesh:
		return _heal_mesh
	var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var c := Color(1.0, 0.82, 0.15)
		if y % 21 < 3:
			c = Color(0.6, 0.38, 0.05)
		elif y % 21 < 5:
			c = Color(1.0, 0.97, 0.6)
		for x in 4:
			img.set_pixel(x, y, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.65, 0.1)
	mat.emission_energy_multiplier = 0.9
	_heal_mesh = CylinderMesh.new()
	_heal_mesh.top_radius = 0.09
	_heal_mesh.bottom_radius = 0.09
	_heal_mesh.height = 0.62
	_heal_mesh.radial_segments = 10
	_heal_mesh.material = mat
	return _heal_mesh
