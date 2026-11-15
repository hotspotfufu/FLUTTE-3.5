extends CharacterBody3D
## Flutte the red panda: the playable character for the 2.5D bamboo forest.
##
## Flutte is built from cut-out pieces of panda_side.png (body, arm, two legs,
## the staff on his back) so he can really walk, jump and swing his staff:
##   * walking / running: legs step, body bobs and leans, arm swings
##   * jumping: legs tuck on the way up, dangle on the way down, squash on landing
##   * attacking: he reaches back, pulls the bamboo staff off his back, swings it
##     in a big arc, then puts it back (press again mid-swing for a second swing)
##
## Controls:  A/D or Left/Right = walk     hold Shift = run
##            Space / W / Up = jump (hold for higher)
##            J / K / F = swing the staff
##            Gamepad: left stick, A = jump, X = attack, RB = run

signal bamboo_changed(total: int)
signal attacked

@export_group("Movement")
@export var walk_speed := 4.2
@export var run_speed := 7.6
@export var ground_accel := 40.0
@export var ground_decel := 48.0
@export var air_accel := 28.0
@export var min_x := -6.0
@export var max_x := 106.0

@export_group("Jump")
@export var jump_velocity := 11.2
@export var gravity := 28.0
@export var fall_multiplier := 1.55
@export var max_fall_speed := 24.0
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export var jump_cut := 0.5

@export_group("Attack")
@export var attack_damage := 1
@export var attack_reach := 0.95

@export_group("Camera")
@export var follow_camera := true
@export var camera_lead := 1.6

@export_group("Respawn")
@export var kill_y := -10.0

# --- art layout (pixels in panda_side.png; the art faces left) ---
const PX := 0.0024602                 # same pixel size as the level's panda reference
const ORIGIN := Vector2(215, 688)     # between the feet, on the ground
const HIPS := Vector2(200, 586)
const HIP_FRONT := Vector2(238, 590)
const HIP_BACK := Vector2(152, 590)
const SHOULDER := Vector2(250, 420)
const PAW := Vector2(222, 505)
const R_BODY := Rect2(0, 0, 515, 678)
const R_ARM := Rect2(175, 392, 136, 146)
const R_LEG_FRONT := Rect2(158, 556, 161, 135)
const R_LEG_BACK := Rect2(118, 556, 68, 122)
const R_STAFF_BACK := Rect2(336, 268, 131, 140)
const R_HIP_FILL := Rect2(140, 570, 165, 79)
const STAFF_LEN := 380.0
const STAFF_SCALE := 1.15
const STAFF_GRIP := 0.28

# attack timing (seconds) and arm angles (degrees, + = forward)
const T_REACH := 0.09
const T_SWING := 0.13
const T_FOLLOW := 0.09
const T_REWIND := 0.09
const T_SHEATHE := 0.15
const T_RETURN := 0.11
const ARM_BACK := 200.0      # arm raised up and back over his head (where the staff is)
const ARM_STRIKE := 50.0     # chopped down in front of him
const ARM_FOLLOW := 38.0

enum Atk { NONE, REACH, SWING, FOLLOW, REWIND, SHEATHE, RETURN }

var bamboo := 0
var facing := 1                 # 1 = right, -1 = left
var spawn_point := Vector3.ZERO

var _dir := ""
var _coyote := 0.0
var _jump_buf := 0.0
var _was_floor := true
var _atk := Atk.NONE
var _atk_t := 0.0
var _atk_from := 0.0
var _atk_queued := false
var _hit_list: Array = []

# animation state
var _phase := 0.0
var _arm := 0.0
var _leg_f := 0.0
var _leg_b := 0.0
var _lift_f := 0.0
var _lift_b := 0.0
var _bob := 0.0
var _lean := 0.0
var _squash := Vector2.ONE
var _turn := 1.0
var _time := 0.0

# nodes
var _rig: Node3D
var _upper: Node3D
var _leg_front: Node3D
var _leg_back: Node3D
var _arm_pivot: Node3D
var _staff_hand: Node3D
var _staff_back: Sprite3D
var _hitbox: Area3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array = []
var _sfx: AudioStreamPlayer
var _cam: Camera3D
var _cam_base := Vector3.ZERO
var _passing := {}


func _ready() -> void:
	add_to_group("player")
	_dir = get_script().resource_path.get_base_dir()
	spawn_point = global_position
	collision_layer = 2            # "Player"
	collision_mask = 1             # "World"
	floor_snap_length = 0.25
	axis_lock_linear_z = true
	_setup_input()
	_build_collision()
	_build_rig()
	_build_hitbox()
	_build_trail()
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = _make_whoosh()
	_sfx.volume_db = -7.0
	add_child(_sfx)
	if follow_camera:
		_grab_camera.call_deferred()


# ======================================================================= build
func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.5
	col.shape = cap
	col.position = Vector3(0, 0.75, 0)
	add_child(col)


func _p(point: Vector2, rel: Vector2) -> Vector3:
	return Vector3((point.x - rel.x) * PX, (rel.y - point.y) * PX, 0.0)


func _sprite(file: String, rect: Rect2, pivot: Vector2, z: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(_dir + "/" + file)
	s.pixel_size = PX
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.position = _p(rect.get_center(), pivot) + Vector3(0, 0, z)
	return s


func _pivot(parent: Node3D, point: Vector2, rel: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = _p(point, rel)
	parent.add_child(n)
	return n


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	_leg_back = _pivot(_rig, HIP_BACK, ORIGIN)
	_leg_back.add_child(_sprite("flutte_leg_back.png", R_LEG_BACK, HIP_BACK, -0.030))
	_leg_front = _pivot(_rig, HIP_FRONT, ORIGIN)
	_leg_front.add_child(_sprite("flutte_leg_front.png", R_LEG_FRONT, HIP_FRONT, -0.020))

	_upper = _pivot(_rig, HIPS, ORIGIN)
	_upper.add_child(_sprite("flutte_hip_fill.png", R_HIP_FILL, HIPS, -0.040))
	_upper.add_child(_sprite("flutte_body.png", R_BODY, HIPS, 0.0))
	_staff_back = _sprite("flutte_staff_back.png", R_STAFF_BACK, HIPS, 0.004)
	_upper.add_child(_staff_back)

	_arm_pivot = _pivot(_upper, SHOULDER, HIPS)
	_arm_pivot.add_child(_sprite("flutte_arm.png", R_ARM, SHOULDER, 0.010))

	# staff held in the paw, pointing along the arm
	_staff_hand = _pivot(_arm_pivot, PAW, SHOULDER)
	var d := Vector2(PAW.x - SHOULDER.x, SHOULDER.y - PAW.y)
	_staff_hand.rotation.z = atan2(d.y, d.x)
	var st := Sprite3D.new()
	st.texture = load(_dir + "/flutte_staff_hand.png")
	st.pixel_size = PX * STAFF_SCALE
	st.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	st.position = Vector3((0.5 - STAFF_GRIP) * STAFF_LEN * PX * STAFF_SCALE, 0, 0.004)
	_staff_hand.add_child(st)
	_staff_hand.visible = false


func _build_hitbox() -> void:
	_hitbox = Area3D.new()
	_hitbox.name = "StaffHitbox"
	_hitbox.collision_layer = 16        # "PlayerAttack"
	_hitbox.collision_mask = 4 | 8      # "Enemies" + "Collectibles"
	_hitbox.monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = attack_reach
	cs.shape = sph
	_hitbox.add_child(cs)
	add_child(_hitbox)


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = m
	_trail.top_level = true
	add_child(_trail)


func _grab_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	# the Stage 1 preview camera pans with A/D - stop that, we follow Flutte instead
	_cam.set_process(false)
	_cam.set_process_unhandled_input(false)
	_cam_base = _cam.global_position
	_cam.global_position.x = global_position.x


# ======================================================================= physics
func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("flutte_left", "flutte_right")
	var running := Input.is_action_pressed("flutte_run")
	var on_floor := is_on_floor()

	_coyote = coyote_time if on_floor else _coyote - delta
	_jump_buf = jump_buffer_time if Input.is_action_just_pressed("flutte_jump") else _jump_buf - delta

	if not on_floor:
		var g := gravity * (fall_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buf = 0.0
		_coyote = 0.0
		_squash = Vector2(0.86, 1.16)
	if Input.is_action_just_released("flutte_jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	var target := dir * (run_speed if running else walk_speed)
	if dir != 0.0:
		var acc := ground_accel if on_floor else air_accel
		velocity.x = move_toward(velocity.x, target, acc * delta)
		if _atk != Atk.SWING and _atk != Atk.FOLLOW:
			facing = 1 if dir > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, (ground_decel if on_floor else air_accel * 0.5) * delta)

	velocity.z = 0.0
	_update_one_way()
	move_and_slide()
	global_position.z = 0.0
	if global_position.x < min_x or global_position.x > max_x:
		global_position.x = clampf(global_position.x, min_x, max_x)
		velocity.x = 0.0

	if is_on_floor() and not _was_floor:
		_squash = Vector2(1.18, 0.82)
	_was_floor = is_on_floor()

	_update_attack(delta)

	if global_position.y < kill_y:
		respawn()


## Floating platforms are "one-way": Flutte walks under them and jumps up
## through them, and lands on top when coming down.
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


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO


func add_bamboo(amount: int = 1) -> void:
	bamboo += amount
	bamboo_changed.emit(bamboo)


func is_attacking() -> bool:
	return _atk != Atk.NONE


# ======================================================================= attack
func _update_attack(delta: float) -> void:
	var pressed := Input.is_action_just_pressed("flutte_attack")
	if pressed:
		if _atk == Atk.NONE:
			_start(Atk.REACH)
			attacked.emit()
		elif _atk == Atk.SWING or _atk == Atk.FOLLOW or _atk == Atk.REWIND:
			_atk_queued = true
		elif _atk == Atk.SHEATHE or _atk == Atk.RETURN:
			_start(Atk.REWIND)

	if _atk == Atk.NONE:
		return
	_atk_t += delta
	match _atk:
		Atk.REACH:
			_arm = lerpf(_atk_from, ARM_BACK, _ease_out(_atk_t / T_REACH))
			if _atk_t >= T_REACH:
				_set_staff_in_hand(true)
				_start(Atk.SWING)
		Atk.SWING:
			var k := clampf(_atk_t / T_SWING, 0.0, 1.0)
			_arm = lerpf(ARM_BACK, ARM_STRIKE, k * k * (3.0 - 2.0 * k))
			if k > 0.25:
				_check_hits()
			if _atk_t >= T_SWING:
				_start(Atk.FOLLOW)
		Atk.FOLLOW:
			_arm = lerpf(ARM_STRIKE, ARM_FOLLOW, _ease_out(_atk_t / T_FOLLOW))
			_check_hits()
			if _atk_t >= T_FOLLOW:
				if _atk_queued:
					_atk_queued = false
					_start(Atk.REWIND)
				else:
					_start(Atk.SHEATHE)
		Atk.REWIND:
			_arm = lerpf(_atk_from, ARM_BACK, _ease_out(_atk_t / T_REWIND))
			if _atk_t >= T_REWIND:
				_set_staff_in_hand(true)
				_start(Atk.SWING)
		Atk.SHEATHE:
			_arm = lerpf(ARM_FOLLOW, ARM_BACK, _ease_in_out(_atk_t / T_SHEATHE))
			if _atk_t >= T_SHEATHE:
				_set_staff_in_hand(false)   # staff goes back on his back
				_start(Atk.RETURN)
		Atk.RETURN:
			# lower the arm down his back to rest (360 degrees == hanging down)
			_arm = lerpf(ARM_BACK, 360.0, _ease_out(_atk_t / T_RETURN))
			if _atk_t >= T_RETURN:
				_arm = 0.0
				_atk = Atk.NONE


func _start(state: Atk) -> void:
	_atk = state
	_atk_t = 0.0
	_atk_from = _arm
	if state == Atk.SWING:
		_hit_list.clear()
		_trail_pts.clear()
		_sfx.pitch_scale = randf_range(0.92, 1.12)
		_sfx.play()
		if is_on_floor():
			velocity.x += facing * 1.6


func _set_staff_in_hand(in_hand: bool) -> void:
	_staff_hand.visible = in_hand
	_staff_back.visible = not in_hand


func _check_hits() -> void:
	for b in _hitbox.get_overlapping_bodies():
		_hit(b)
	for a in _hitbox.get_overlapping_areas():
		_hit(a)


func _hit(target: Node) -> void:
	if target == self or target in _hit_list:
		return
	_hit_list.append(target)
	if target.has_method("on_staff_hit"):
		target.call("on_staff_hit", self)
	elif target.has_method("take_hit"):
		target.call("take_hit", attack_damage, self)


static func _ease_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)


static func _ease_in_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


# ======================================================================= animation
func _process(delta: float) -> void:
	_time += delta
	var speed := absf(velocity.x)
	var on_floor := is_on_floor()
	var running := speed > walk_speed + 0.4
	var k := minf(1.0, delta * 14.0)

	var t_leg_f := 0.0
	var t_leg_b := 0.0
	var t_lift_f := 0.0
	var t_lift_b := 0.0
	var t_arm := sin(_time * 2.2) * 3.0
	var t_bob := sin(_time * 2.2) * 0.012
	var t_lean := 0.0

	if not on_floor:
		if velocity.y > 0.0:
			t_leg_f = 28.0
			t_leg_b = -22.0
			t_lift_f = 0.10
			t_lift_b = 0.05
			t_arm = -55.0
			t_lean = 6.0
		else:
			t_leg_f = 12.0
			t_leg_b = -12.0
			t_arm = -95.0
			t_lean = -2.0
	elif speed > 0.3:
		_phase += delta * (8.5 + speed * 1.7)
		var amp := 34.0 if running else 26.0
		var s := sin(_phase)
		var c := cos(_phase)
		t_leg_f = amp * s
		t_leg_b = -amp * s
		t_lift_f = maxf(0.0, c) * 0.09
		t_lift_b = maxf(0.0, -c) * 0.09
		t_bob = (1.0 - absf(s)) * (0.07 if running else 0.05)
		t_arm = -s * (30.0 if running else 20.0)
		t_lean = 10.0 if running else 4.0
		k = 1.0     # follow the walk cycle exactly
	else:
		_phase = 0.0

	if _atk != Atk.NONE:
		t_arm = _arm
		match _atk:
			Atk.REACH, Atk.REWIND, Atk.SHEATHE:
				t_lean = -6.0
			Atk.SWING, Atk.FOLLOW:
				t_lean = 12.0
			_:
				t_lean = 0.0

	_leg_f = lerpf(_leg_f, t_leg_f, k)
	_leg_b = lerpf(_leg_b, t_leg_b, k)
	_lift_f = lerpf(_lift_f, t_lift_f, k)
	_lift_b = lerpf(_lift_b, t_lift_b, k)
	_bob = lerpf(_bob, t_bob, k)
	_lean = lerpf(_lean, t_lean, minf(1.0, delta * 10.0))
	_arm = t_arm if _atk != Atk.NONE else lerpf(_arm, t_arm, minf(1.0, delta * 16.0))

	# + angles mean "forward"; the art faces left, so forward is clockwise on screen
	_leg_front.rotation.z = -deg_to_rad(_leg_f)
	_leg_back.rotation.z = -deg_to_rad(_leg_b)
	_leg_front.position.y = (ORIGIN.y - HIP_FRONT.y) * PX + _lift_f
	_leg_back.position.y = (ORIGIN.y - HIP_BACK.y) * PX + _lift_b
	_upper.position.y = (ORIGIN.y - HIPS.y) * PX + _bob
	_upper.rotation.z = -deg_to_rad(_lean)
	_arm_pivot.rotation.z = -deg_to_rad(_arm)

	# turn around with a quick "paper flip"; squash & stretch from the feet
	_turn = move_toward(_turn, float(facing), delta * 12.0)
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, delta * 10.0))
	var sx := _turn if absf(_turn) > 0.08 else 0.08 * signf(_turn + 0.0001)
	_rig.scale = Vector3(-sx * _squash.x, _squash.y, 1.0)

	_hitbox.position = Vector3(facing * 0.75, 0.95, 0.0)
	_update_trail(delta)
	_update_camera(delta)


func _update_trail(_delta: float) -> void:
	var swinging := _atk == Atk.SWING or _atk == Atk.FOLLOW
	if swinging and _staff_hand.visible:
		var tip := _staff_hand.to_global(Vector3((1.0 - STAFF_GRIP) * STAFF_LEN * PX * STAFF_SCALE, 0, 0.02))
		var mid := _staff_hand.to_global(Vector3(0.4 * STAFF_LEN * PX * STAFF_SCALE, 0, 0.02))
		_trail_pts.append([tip, mid, 1.0])
	for p in _trail_pts:
		p[2] -= 0.16
	while _trail_pts.size() > 0 and _trail_pts[0][2] <= 0.0:
		_trail_pts.pop_front()
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _trail_pts:
		var a: float = p[2]
		_trail_mesh.surface_set_color(Color(1.0, 1.0, 0.9, 0.6 * a))
		_trail_mesh.surface_add_vertex(p[0])
		_trail_mesh.surface_set_color(Color(0.75, 1.0, 0.55, 0.0))
		_trail_mesh.surface_add_vertex(p[1])
	_trail_mesh.surface_end()


func _update_camera(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var lo := -1000.0
	var hi := 1000.0
	if "min_x" in _cam:
		lo = float(_cam.get("min_x"))
		hi = float(_cam.get("max_x"))
	var tx := clampf(global_position.x + facing * camera_lead, lo, hi)
	var ty := _cam_base.y + maxf(0.0, global_position.y - 2.5) * 0.7
	_cam.global_position.x = lerpf(_cam.global_position.x, tx, minf(1.0, delta * 4.0))
	_cam.global_position.y = lerpf(_cam.global_position.y, ty, minf(1.0, delta * 3.0))


# ======================================================================= input
func _setup_input() -> void:
	_add_action("flutte_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("flutte_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("flutte_jump", [KEY_SPACE, KEY_W, KEY_UP], [JOY_BUTTON_A])
	_add_action("flutte_run", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("flutte_attack", [KEY_J, KEY_K, KEY_F], [JOY_BUTTON_X])


static func _add_action(action: String, keys: Array, joy: Array, axis: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	if InputMap.action_get_events(action).size() > 0:
		return
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for j in joy:
		var jb := InputEventJoypadButton.new()
		jb.button_index = j
		InputMap.action_add_event(action, jb)
	if axis.size() == 2:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis[0]
		jm.axis_value = axis[1]
		InputMap.action_add_event(action, jm)


static func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.2)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.5)
		lp += (randf_range(-1.0, 1.0) - lp) * lerpf(0.08, 0.35, sin(t * PI))
		data.encode_s16(i * 2, int(clampf(lp * env * 1.6, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
