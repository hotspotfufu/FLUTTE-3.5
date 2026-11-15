extends Area3D
## A floating, spinning bamboo stick Flutte collects (like rings in Sonic).
## Touch it, or whack it with the staff, to collect it.

signal collected(stick: Area3D)

@export var value := 1
@export var bob_height := 0.08
@export var bob_speed := 2.6
@export var spin_speed := 2.8

var _t := 0.0
var _taken := false
var _visual: Node3D
var _base_y := 0.0

static var _stick_mesh: CylinderMesh
static var _halo_mesh: QuadMesh
static var _chime: AudioStreamWAV


func _ready() -> void:
	add_to_group("bamboo")
	collision_layer = 8      # "Collectibles"
	collision_mask = 2       # "Player"
	monitorable = true
	monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.38
	cs.shape = sph
	add_child(cs)

	_visual = Node3D.new()
	add_child(_visual)
	var stick := MeshInstance3D.new()
	stick.mesh = _get_stick_mesh()
	stick.rotation_degrees = Vector3(0, 0, 22)
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(stick)
	var halo := MeshInstance3D.new()
	halo.mesh = _get_halo_mesh()
	halo.position = Vector3(0, 0, -0.08)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	_t = global_position.x * 0.7
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_visual.position.y = sin(_t * bob_speed) * bob_height
	_visual.rotation.y = _t * spin_speed


func _on_body_entered(body: Node) -> void:
	if body.has_method("add_bamboo"):
		collect(body)


func on_staff_hit(by: Node) -> void:
	collect(by)


func collect(by: Node) -> void:
	if _taken:
		return
	_taken = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if by != null and by.has_method("add_bamboo"):
		by.call("add_bamboo", value)
	collected.emit(self)
	_play_chime()
	_burst()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y + 0.55, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3(1.6, 1.6, 1.6), 0.15)
	tw.chain().tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
	tw.chain().tween_callback(queue_free)


func _burst() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -3, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.97, 0.55)
	q.material = m
	p.mesh = q
	get_parent().add_child(p)
	p.global_position = global_position
	p.emitting = true
	p.finished.connect(p.queue_free)


func _play_chime() -> void:
	var a := AudioStreamPlayer.new()
	a.stream = _get_chime()
	a.volume_db = -9.0
	a.pitch_scale = randf_range(0.98, 1.06)
	get_tree().current_scene.add_child(a)
	a.finished.connect(a.queue_free)
	a.play()


static func _get_stick_mesh() -> CylinderMesh:
	if _stick_mesh:
		return _stick_mesh
	# green bamboo with dark rings, drawn into a tiny texture
	var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var c := Color(0.55, 0.78, 0.26)
		if y % 21 < 3:
			c = Color(0.25, 0.42, 0.10)
		elif y % 21 < 5:
			c = Color(0.80, 0.93, 0.48)
		for x in 4:
			img.set_pixel(x, y, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.55, 0.12)
	mat.emission_energy_multiplier = 0.9
	mat.roughness = 0.6
	_stick_mesh = CylinderMesh.new()
	_stick_mesh.top_radius = 0.085
	_stick_mesh.bottom_radius = 0.085
	_stick_mesh.height = 0.62
	_stick_mesh.radial_segments = 10
	_stick_mesh.rings = 1
	_stick_mesh.material = mat
	return _stick_mesh


static func _get_halo_mesh() -> QuadMesh:
	if _halo_mesh:
		return _halo_mesh
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.7, 0.55))
	g.set_color(1, Color(1.0, 0.95, 0.6, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mesh = QuadMesh.new()
	_halo_mesh.size = Vector2(0.95, 0.95)
	_halo_mesh.material = m
	return _halo_mesh


static func _get_chime() -> AudioStreamWAV:
	if _chime:
		return _chime
	var rate := 22050
	var n := int(rate * 0.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := 1318.5 if t < 0.065 else 1975.5
		phase += TAU * f / float(rate)
		var env := exp(-t * 8.0) * minf(1.0, t * 400.0)
		var s := sin(phase) * 0.4 + sin(phase * 2.0) * 0.1
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 32767.0))
	_chime = AudioStreamWAV.new()
	_chime.format = AudioStreamWAV.FORMAT_16_BITS
	_chime.mix_rate = rate
	_chime.data = data
	return _chime
