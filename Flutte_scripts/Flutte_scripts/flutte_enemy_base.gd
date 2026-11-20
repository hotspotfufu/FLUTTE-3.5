extends CharacterBody3D
## Shared code for FLUTTE's opponents (ninjas and the bear boss):
## sprite-sheet animation, gravity, one-way platforms, facing, hit flash,
## and helpers for finding Flutte.

signal defeated(enemy: Node)

const GRAVITY := 28.0

var hp := 2
var facing := -1                 # 1 = right, -1 = left
var dead := false

var _dir := ""
var _sprite: Sprite3D
var _cell := Vector2i(1, 1)
var _cols := 1
var _anims := {}                 # name -> [frames: Array, fps: float, loop: bool]
var _anim := ""
var _anim_t := 0.0
var _anim_done := false
var _flash := 0.0
var _passing := {}
var _art_faces_right := true
var sprite_z := 0.45
var _knock_v := 0.0
var _knock_t := 0.0
var _shadow: MeshInstance3D
var shadow_size := 0.9


func setup_sprite(file: String, cell: Vector2i, cols: int, height_units: float, frame_px_height: float) -> void:
	_dir = get_script().resource_path.get_base_dir()
	_cell = cell
	_cols = cols
	_sprite = Sprite3D.new()
	_sprite.texture = load(_dir + "/" + file)
	_sprite.region_enabled = true
	_sprite.pixel_size = height_units / frame_px_height
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# frames sit on the bottom of their cell (2px margin)
	# drawn a little toward the camera so platforms never cover them
	_sprite.position = Vector3(0, (cell.y * 0.5 - 2.0) * _sprite.pixel_size, sprite_z)
	add_child(_sprite)
	_shadow = make_blob_shadow(shadow_size)
	add_child(_shadow)


## soft dark oval on the ground under a character (keeps them grounded in 3D)
static func make_blob_shadow(size: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = soft_texture()
	m.albedo_color = Color(0.12, 0.08, 0.16, 0.38)
	m.render_priority = -1
	var q := PlaneMesh.new()
	q.size = Vector2(size * 1.6, size * 0.9)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.03, 0)
	mi.top_level = true
	return mi


## keep the shadow on the floor below us (it shrinks while we're in the air)
func update_shadow() -> void:
	if _shadow == null:
		return
	var from := global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8.0, 0), 1)
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or dead:
		_shadow.visible = false
		return
	_shadow.visible = true
	var gy: float = (r.position as Vector3).y
	_shadow.global_position = Vector3(global_position.x, gy + 0.03, 0.15)
	var k := clampf(1.0 - (global_position.y - gy) / 4.0, 0.35, 1.0)
	_shadow.scale = Vector3(k, 1, k)


func add_anim(name: String, frames: Array, fps: float, loop: bool = true) -> void:
	_anims[name] = [frames, fps, loop]


func play(name: String, restart: bool = false) -> void:
	if _anim == name and not restart:
		return
	_anim = name
	_anim_t = 0.0
	_anim_done = false
	_show_frame()


func anim_frame() -> int:
	## index within the current animation
	if not _anims.has(_anim):
		return 0
	var a: Array = _anims[_anim]
	var n: int = (a[0] as Array).size()
	var i := int(_anim_t * float(a[1]))
	return i % n if a[2] else mini(i, n - 1)


func _show_frame() -> void:
	if not _anims.has(_anim):
		return
	var frames: Array = _anims[_anim][0]
	var f: int = frames[anim_frame()]
	_sprite.region_rect = Rect2((f % _cols) * _cell.x, (f / _cols) * _cell.y, _cell.x, _cell.y)


func tick_anim(delta: float) -> void:
	if not _anims.has(_anim):
		return
	_anim_t += delta
	var a: Array = _anims[_anim]
	if not a[2] and _anim_t * float(a[1]) >= (a[0] as Array).size():
		_anim_done = true
	_show_frame()
	_sprite.flip_h = (facing < 0) == _art_faces_right
	_flash = maxf(0.0, _flash - delta * 6.0)
	update_shadow()
	_sprite.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.35, 0.35), _flash)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -24.0)


## a short shove away from whoever hit us; overrides walking for a moment
func knockback(from: Node, strength: float = 4.0, time: float = 0.22) -> void:
	var away := float(-facing)
	if from is Node3D:
		var dx := global_position.x - (from as Node3D).global_position.x
		if absf(dx) > 0.01:
			away = signf(dx)
	_knock_v = away * strength
	_knock_t = time


func move(delta: float) -> void:
	if _knock_t > 0.0:
		_knock_t -= delta
		velocity.x = _knock_v * clampf(_knock_t / 0.22 + 0.3, 0.0, 1.0)
	velocity.z = 0.0
	_update_one_way()
	move_and_slide()
	global_position.z = 0.0


func player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func flash() -> void:
	_flash = 1.0


## same rule as Flutte: floating platforms only hold you up when you're above them
func _update_one_way() -> void:
	for p in get_tree().get_nodes_in_group("one_way_platform"):
		if not (p is PhysicsBody3D):
			continue
		var half := 0.2
		if "thickness" in p:
			half = float(p.get("thickness")) * 0.5
		var top: float = (p as Node3D).global_position.y + half
		var id: int = p.get_instance_id()
		var solid := global_position.y >= top - 0.06 and velocity.y <= 0.5
		if solid and _passing.has(id):
			remove_collision_exception_with(p)
			_passing.erase(id)
		elif not solid and not _passing.has(id):
			add_collision_exception_with(p)
			_passing[id] = true


## floor check a little ahead, so patrolling enemies don't walk off platforms
func ground_ahead(dist: float) -> bool:
	var from := global_position + Vector3(facing * dist, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.0, 0), 1)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


static func soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


## a quick burst of coloured specks (hits, defeats)
func burst(at: Vector3, color: Color, amount: int = 14, speed: float = 3.0, size: float = 0.12) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector3(0, 1, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.mesh = q
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func spawn_bamboo(count: int) -> void:
	var stick_script: Script = load(_dir + "/bamboo_stick.gd")
	for i in count:
		var s: Node3D = stick_script.new()
		get_parent().add_child(s)
		s.global_position = global_position + Vector3((i - (count - 1) * 0.5) * 0.55, 0.9, 0)
