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
##            Space / W / Up = jump, press again in the air = double jump
##            J / F = swing the staff      K / L = tail spin attack
##            Q / E = red beam from the chest diamond (needs 50 bamboo)
##            G / R = fire a firework rocket (pick up firework cannons from lanterns)
##            Gamepad: left stick / D-pad, A = jump, X = staff, B = tail spin,
##                     Y = red beam, RB/LB/RT = run
##            Touch: on-screen joystick + buttons (see flutte_touch_controls.gd)

signal bamboo_changed(total: int)
signal attacked
signal health_changed(current: int, maximum: int)
signal rockets_changed(count: int)

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
@export var air_jumps := 1            ## 1 = double jump
@export var double_jump_velocity := 10.0

@export_group("Attack")
@export var attack_damage := 1
@export var attack_reach := 0.95

@export_group("Health")
@export var max_health := 100
@export var fall_damage := 20

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

const GEM := Vector2(113, 405)          # the red diamond on his chest
const SPECIAL_COST := 50
const T_TAIL := 0.5
const T_CHARGE := 0.55
const T_BEAM := 1.25
const T_BEAM_END := 0.25
const BEAM_LEN := 18.0

var bamboo := 0
var health := 100
var rockets := 0
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
var _spin_root: Node3D
var _air_jumps_left := 0
var _flip_t := -1.0
var _combo := 0
var _sparks: CPUParticles3D
static var _slash_shader: Shader
var _sfx: AudioStreamPlayer
var _cam: Camera3D
var _cam_base := Vector3.ZERO
var _passing := {}
var _cam_pos := Vector3.ZERO
var _shake := 0.0
var _invuln := 0.0
var _sprites: Array = []
var _fall_speed := 0.0
var _dust_t := 0.0
static var _soft_tex: GradientTexture2D

# tail spin
var _tail_t := -1.0
var _tail_hits: Array = []
var _tail_box: Area3D

# red beam: 0 = off, 1 = charging, 2 = firing, 3 = fading
var _beam_state := 0
var _beam_t := 0.0
var _beam_tick := 0.0
var _gem: Node3D
var _gem_glow: MeshInstance3D
var _gem_mat: StandardMaterial3D
var _charge_fx: CPUParticles3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _beam_box: Area3D
var _beam_sfx: AudioStreamPlayer
var _beam_hit_list: Array = []

# firework cannon
var _cannon: Sprite3D
var _cannon_t := 0.0
var _fire_cd := 0.0
var _last_safe := Vector3.ZERO


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
	health = max_health
	_build_rig()
	_build_hitbox()
	_build_sparks()
	_build_tail()
	_build_beam()
	_build_cannon()
	_last_safe = global_position
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
	_sprites.append(s)
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
	_spin_root = Node3D.new()
	_spin_root.name = "SpinRoot"
	_spin_root.position = Vector3(0, 0.85, 0)
	add_child(_spin_root)
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.position = Vector3(0, -0.85, 0)
	_spin_root.add_child(_rig)

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
	_sprites.append(st)
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


func _build_sparks() -> void:
	# little glowing flecks thrown off the staff tip while swinging
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 28
	_sparks.lifetime = 0.35
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 0.6
	_sparks.initial_velocity_max = 1.8
	_sparks.gravity = Vector3(0, -2.0, 0)
	_sparks.scale_amount_min = 0.4
	_sparks.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.92, 1.0, 0.6)
	q.material = m
	_sparks.mesh = q
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_sparks.scale_amount_curve = curve
	_sparks.top_level = true
	add_child(_sparks)


func _grab_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	# the Stage 1 preview camera pans with A/D - stop that, we follow Flutte instead
	_cam.set_process(false)
	_cam.set_process_unhandled_input(false)
	_cam_base = _cam.global_position
	_cam.global_position.x = global_position.x
	_cam_pos = _cam.global_position


# ======================================================================= physics
func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("flutte_left", "flutte_right")
	var running := Input.is_action_pressed("flutte_run")
	var on_floor := is_on_floor()
	var beaming := _beam_state == 1 or _beam_state == 2
	if beaming:
		dir = 0.0
	_invuln = maxf(0.0, _invuln - delta)

	_coyote = coyote_time if on_floor else _coyote - delta
	_jump_buf = jump_buffer_time if Input.is_action_just_pressed("flutte_jump") else _jump_buf - delta

	if beaming and not on_floor:
		velocity.y = move_toward(velocity.y, 0.0, 60.0 * delta)   # hover while firing
	elif not on_floor:
		var g := gravity * (fall_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	if on_floor:
		_air_jumps_left = air_jumps
	if beaming:
		_jump_buf = 0.0
	elif _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buf = 0.0
		_coyote = 0.0
		_squash = Vector2(0.86, 1.16)
	elif not beaming and Input.is_action_just_pressed("flutte_jump") and not on_floor and _coyote <= 0.0 and _air_jumps_left > 0:
		# double jump: a fresh boost upward with a front flip and a puff of air
		_air_jumps_left -= 1
		_jump_buf = 0.0
		velocity.y = double_jump_velocity
		_squash = Vector2(0.8, 1.2)
		_flip_t = 0.0
		_puff()
	if Input.is_action_just_released("flutte_jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	var target := dir * (run_speed if running else walk_speed)
	if dir != 0.0:
		var acc := ground_accel if on_floor else air_accel
		velocity.x = move_toward(velocity.x, target, acc * delta)
		if _atk != Atk.SWING and _atk != Atk.FOLLOW and _tail_t < 0.0:
			facing = 1 if dir > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, (ground_decel if on_floor else air_accel * 0.5) * delta)

	velocity.z = 0.0
	_update_one_way()
	if velocity.y < 0.0:
		_fall_speed = -velocity.y
	move_and_slide()
	global_position.z = 0.0
	if global_position.x < min_x or global_position.x > max_x:
		global_position.x = clampf(global_position.x, min_x, max_x)
		velocity.x = 0.0

	if is_on_floor() and not _was_floor:
		# softer, springier landing; a bigger squash after a big fall
		var f := clampf(_fall_speed / 16.0, 0.0, 1.0)
		_squash = Vector2(1.12 + 0.14 * f, 0.88 - 0.12 * f)
		if f > 0.55:
			_shake = maxf(_shake, 0.05 * f)
			for i in 3:
				_dust(Vector3(randf_range(-0.4, 0.4), 0.08, 0.12), Vector3(randf_range(-1.2, 1.2), 0.5, 0))
		_fall_speed = 0.0
	_was_floor = is_on_floor()

	_update_attack(delta)
	_update_tail(delta)
	_update_beam(delta)
	_update_cannon(delta)
	if is_on_floor() and _invuln <= 0.0:
		_last_safe = global_position

	if global_position.y < kill_y:
		global_position = _last_safe + Vector3(0, 0.5, 0)
		velocity = Vector3.ZERO
		take_damage(fall_damage, null, true)


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


func special_ready() -> bool:
	return bamboo >= SPECIAL_COST


## Call this from enemies / hazards: take_damage(10, self)
func take_damage(amount: int, from: Node = null, ignore_invuln: bool = false) -> void:
	if (_invuln > 0.0 and not ignore_invuln) or _beam_state == 2:
		return
	health = maxi(0, health - amount)
	_invuln = 1.0
	_shake = maxf(_shake, 0.12)
	if from is Node3D:
		var away := signf(global_position.x - (from as Node3D).global_position.x)
		velocity = Vector3((away if away != 0.0 else -float(facing)) * 6.0, 6.0, 0)
	if health <= 0:
		# knocked out: Flutte gets back up with full health and a moment of safety
		health = max_health
		_invuln = 2.2
		velocity = Vector3(0, 7.0, 0)
		_shake = 0.3
	health_changed.emit(health, max_health)


func add_rockets(amount: int) -> void:
	rockets += amount
	rockets_changed.emit(rockets)


func heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)


func is_attacking() -> bool:
	return _atk != Atk.NONE


# ======================================================================= attack
func _update_attack(delta: float) -> void:
	var pressed := Input.is_action_just_pressed("flutte_attack") and _tail_t < 0.0 and _beam_state == 0
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
				_combo = 0
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
		_combo += 1
		_spawn_slash(_combo % 2 == 0)
		_sparks.emitting = true
		_sfx.pitch_scale = randf_range(0.92, 1.12) + (0.12 if _combo % 2 == 0 else 0.0)
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
	_shake = maxf(_shake, 0.035)
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
			# coming down: the faster he falls, the more his legs rise up
			var f := clampf(-velocity.y / 12.0, 0.0, 1.0)
			t_leg_f = lerpf(14.0, 38.0, f)
			t_leg_b = lerpf(-10.0, -30.0, f)
			t_lift_f = 0.03 + 0.15 * f
			t_lift_b = 0.03 + 0.12 * f
			t_arm = lerpf(-60.0, -120.0, f)
			t_lean = lerpf(0.0, -5.0, f)
			k = minf(1.0, delta * 9.0)
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
		t_lean = 16.0 if running else 4.0
		k = 1.0     # follow the walk cycle exactly
		if running:
			_dust_t -= delta
			if _dust_t <= 0.0:
				_dust_t = 0.075
				_dust(Vector3(-facing * 0.32, 0.1, 0.1), Vector3(-facing * randf_range(0.6, 1.4), randf_range(0.2, 0.6), 0))
	else:
		_phase = 0.0

	if _beam_state == 1 or _beam_state == 2:
		t_arm = 85.0 if _beam_state == 2 else 40.0
		t_leg_f = 18.0
		t_leg_b = -24.0
		t_lean = 0.0       # stay level so the beam fires straight
		k = minf(1.0, delta * 12.0)
	if _cannon_t > 0.0:
		t_arm = 80.0
		t_lean = -4.0
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
	_rig.visible = _invuln <= 0.0 or fmod(_invuln, 0.14) > 0.05     # blink after getting hurt
	var tint := Color(1.0, 0.55, 0.55) if _invuln > 0.75 else Color.WHITE
	for sp in _sprites:
		(sp as Sprite3D).modulate = tint
	_update_flip(delta)
	if _sparks.emitting:
		_sparks.global_position = _staff_hand.to_global(Vector3((1.0 - STAFF_GRIP) * STAFF_LEN * PX * STAFF_SCALE, 0, 0.03))
		if _atk != Atk.SWING and _atk != Atk.FOLLOW:
			_sparks.emitting = false
	_update_camera(delta)


func _update_flip(delta: float) -> void:
	if _flip_t < 0.0:
		_spin_root.rotation.z = 0.0
		return
	_flip_t += delta / 0.42
	if _flip_t >= 1.0 or is_on_floor():
		_flip_t = -1.0
		_spin_root.rotation.z = 0.0
		return
	var k := 1.0 - pow(1.0 - _flip_t, 2.2)
	_spin_root.rotation.z = -float(facing) * TAU * k   # forward somersault


func _puff() -> void:
	# a ring of air under his feet for the double jump
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	ring.mesh = q
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float t = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y *= 2.6;
	float r = length(p);
	float e = 0.55 + t * 0.38;
	float ring = smoothstep(e - 0.16, e - 0.05, r) * (1.0 - smoothstep(e, e + 0.04, r));
	ALBEDO = vec3(1.0, 1.0, 0.95);
	ALPHA = ring * (1.0 - t) * 0.9;
}
"""
	m.shader = sh
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.05, 0.05)
	var tw := ring.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("t", v), 0.0, 1.0, 0.35)
	tw.parallel().tween_property(ring, "scale", Vector3(1.8, 1.8, 1.0), 0.35)
	tw.tween_callback(ring.queue_free)


# ======================================================================= swing effect
## A glowing crescent "slash" that sweeps along the path of the staff:
## bright white core on the outside edge, fading through lime and green into
## ragged teal streaks on the inside. The second hit of a combo is pink & gold.
func _spawn_slash(alt: bool) -> void:
	if _slash_shader == null:
		_slash_shader = Shader.new()
		_slash_shader.code = SLASH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _slash_shader
	m.set_shader_parameter("seed", randf() * 100.0)
	if alt:
		m.set_shader_parameter("c_core", Color(1.0, 0.98, 0.9))
		m.set_shader_parameter("c_mid", Color(1.0, 0.75, 0.3))
		m.set_shader_parameter("c_edge", Color(1.0, 0.3, 0.6))
	var q := QuadMesh.new()
	q.size = Vector2(2.5, 2.5)
	var slash := MeshInstance3D.new()
	slash.mesh = q
	slash.material_override = m
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# centred on the shoulder, in front of Flutte; it flips with him
	slash.position = _p(SHOULDER, HIPS) + Vector3(0, 0, 0.08)
	_upper.add_child(slash)
	var tw := slash.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, T_SWING * 1.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.26)
	tw.parallel().tween_property(slash, "scale", Vector3(1.12, 1.12, 1.0), 0.26)
	tw.tween_callback(slash.queue_free)


const SLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress = 0.0;   // how far the slash has swept (0..1)
uniform float fade = 1.0;
uniform float a0 = 1.0;         // start angle (radians) - up behind his head
uniform float a1 = 4.15;        // end angle - down in front of him
uniform float radius = 0.88;
uniform float width = 0.62;
uniform float seed = 0.0;
uniform vec3 c_core : source_color = vec3(1.0, 1.0, 0.9);
uniform vec3 c_mid : source_color = vec3(0.78, 1.0, 0.25);
uniform vec3 c_edge : source_color = vec3(0.05, 0.7, 0.55);

float hash(float n) { return fract(sin(n * 12.9898 + seed) * 43758.5453); }
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float span = a1 - a0;
	float da = mod(a - a0 + 6.2831853, 6.2831853);
	float s = da / span;                         // 0 at the start of the arc, 1 at the end
	if (s > progress || s > 1.0) {
		discard;
	}
	float tail = clamp(s / max(progress, 0.001), 0.0, 1.0);   // 0 = oldest, 1 = staff tip
	float th = width * pow(tail, 0.7) * (1.0 - 0.75 * smoothstep(0.86, 1.0, tail));
	th = max(th, 0.0005);
	float d = (radius - r) / th;                 // 0 on the outer edge, 1 on the inner edge
	float rag = vnoise(s * 24.0) * 0.5 + vnoise(s * 57.0) * 0.3;
	float inner = 1.0 - rag * (0.9 - 0.5 * tail);
	float band = smoothstep(-0.12, 0.04, d) * (1.0 - smoothstep(inner - 0.3, inner, d));
	vec3 col = mix(c_core, c_mid, smoothstep(0.04, 0.35, d));
	col = mix(col, c_edge, smoothstep(0.35, 0.85, d));
	float glow = (1.0 - smoothstep(0.0, 0.09, r - radius)) * step(radius, r) * 0.55;
	col = mix(col, c_mid, step(radius, r));
	float alpha = max(band, glow * tail) * smoothstep(0.0, 0.18, tail) * fade;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""


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
	_cam_pos.x = lerpf(_cam_pos.x, tx, minf(1.0, delta * 4.0))
	_cam_pos.y = lerpf(_cam_pos.y, ty, minf(1.0, delta * 3.0))
	_cam_pos.z = _cam_base.z
	_shake = move_toward(_shake, 0.0, delta * 0.6)
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake
	_cam.global_position = _cam_pos + jitter


# ======================================================================= dust puffs
static func _get_soft_tex() -> GradientTexture2D:
	if _soft_tex:
		return _soft_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_soft_tex = GradientTexture2D.new()
	_soft_tex.gradient = g
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(0.5, 0.0)
	_soft_tex.width = 64
	_soft_tex.height = 64
	return _soft_tex


## little ball of air/dust that drifts away and fades
func _dust(offset: Vector3, drift: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _get_soft_tex()
	m.albedo_color = Color(1.0, 0.97, 0.92, 0.95)
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var puff := MeshInstance3D.new()
	puff.mesh = q
	puff.material_override = m
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(puff)
	puff.global_position = global_position + offset
	puff.scale = Vector3.ONE * randf_range(0.35, 0.55)
	var life := randf_range(0.35, 0.5)
	var tw := puff.create_tween().set_parallel(true)
	tw.tween_property(puff, "global_position", puff.global_position + drift * life, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(puff, "scale", Vector3.ONE * randf_range(0.9, 1.3), life).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(puff.queue_free)


# ======================================================================= tail spin
func _build_tail() -> void:
	_tail_box = Area3D.new()
	_tail_box.collision_layer = 16
	_tail_box.collision_mask = 4 | 8
	_tail_box.monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.25
	cs.shape = sph
	cs.position = Vector3(0, 0.6, 0)
	_tail_box.add_child(cs)
	add_child(_tail_box)


func _update_tail(delta: float) -> void:
	if _tail_t < 0.0:
		if Input.is_action_just_pressed("flutte_tail") and _atk == Atk.NONE and _beam_state == 0:
			_tail_t = 0.0
			_tail_hits.clear()
			_sfx.pitch_scale = 0.8
			_sfx.play()
			if is_on_floor():
				velocity.y = 4.5     # little hop into the spin
			_spawn_tail_ring()
			attacked.emit()
		return
	_tail_t += delta
	var k := clampf(_tail_t / T_TAIL, 0.0, 1.0)
	# two full turns, fast at the start and easing out
	_spin_root.rotation.y = -float(facing) * TAU * 2.0 * _ease_out(k)
	if k > 0.08 and k < 0.85:
		for b in _tail_box.get_overlapping_bodies():
			_tail_hit(b)
		for a in _tail_box.get_overlapping_areas():
			_tail_hit(a)
	if k >= 1.0:
		_tail_t = -1.0
		_spin_root.rotation.y = 0.0


func _tail_hit(target: Node) -> void:
	if target == self or target in _tail_hits:
		return
	_tail_hits.append(target)
	_shake = maxf(_shake, 0.04)
	if target.has_method("on_staff_hit"):
		target.call("on_staff_hit", self)
	elif target.has_method("take_hit"):
		target.call("take_hit", attack_damage, self)


## a striped red-and-cream ring that whips around him at tail height:
## the back half draws behind Flutte and the front half in front of him
func _spawn_tail_ring() -> void:
	var sh := Shader.new()
	sh.code = TAIL_SHADER
	for front in [false, true]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("front", 1.0 if front else 0.0)
		m.set_shader_parameter("dir", float(facing))
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 3.2)
		var ring := MeshInstance3D.new()
		ring.mesh = q
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0, 0.42, 0.12 if front else -0.12)
		add_child(ring)
		var tw := ring.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, T_TAIL * 0.75)
		tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.2)
		tw.tween_callback(ring.queue_free)


const TAIL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float front = 1.0;     // 1 = lower (front) half, 0 = upper (back) half
uniform float dir = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y * 3.4;                     // squash into a flat ellipse
	float r = length(p);
	if ((front > 0.5 && p.y > 0.0) || (front < 0.5 && p.y < 0.0)) { discard; }
	float a = atan(p.y, p.x * dir);       // spin direction follows his facing
	float s = mod(a + 3.14159, 6.28318) / 6.28318;      // 0..1 around the ring
	float reach = progress * 2.0;                       // wraps around twice
	float behind = mod(reach - s, 1.0);                 // distance behind the head
	if (reach < s) { discard; }
	float trail = 1.0 - smoothstep(0.15, 0.95, behind);
	float band = smoothstep(0.52, 0.62, r) * (1.0 - smoothstep(0.88, 0.96, r));
	float glow = smoothstep(0.4, 0.6, r) * (1.0 - smoothstep(0.96, 1.0, r)) * 0.5;
	float stripes = step(0.5, fract(s * 9.0 - TIME * 3.0));
	vec3 col = mix(vec3(0.9, 0.18, 0.12), vec3(1.0, 0.92, 0.82), stripes);
	col = mix(col, vec3(1.0, 1.0, 0.95), (1.0 - behind) * 0.5);
	ALBEDO = col;
	ALPHA = clamp(max(band, glow) * trail * fade, 0.0, 1.0);
}
"""


# ======================================================================= red beam
func _build_beam() -> void:
	# glow on the chest diamond
	_gem = _pivot(_upper, GEM, HIPS)
	_gem.position.z = 0.07
	_gem_mat = StandardMaterial3D.new()
	_gem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gem_mat.albedo_texture = _get_soft_tex()
	_gem_mat.albedo_color = Color(1.0, 0.25, 0.3, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	_gem_glow = MeshInstance3D.new()
	_gem_glow.mesh = q
	_gem_glow.material_override = _gem_mat
	_gem_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gem.add_child(_gem_glow)

	# red sparks sucked into the diamond while charging
	_charge_fx = CPUParticles3D.new()
	_charge_fx.emitting = false
	_charge_fx.amount = 40
	_charge_fx.lifetime = 0.35
	_charge_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_charge_fx.emission_sphere_radius = 0.9
	_charge_fx.gravity = Vector3.ZERO
	_charge_fx.initial_velocity_min = 0.0
	_charge_fx.initial_velocity_max = 0.0
	_charge_fx.radial_accel_min = -22.0
	_charge_fx.radial_accel_max = -16.0
	var pq := QuadMesh.new()
	pq.size = Vector2(0.06, 0.06)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_color = Color(1.0, 0.45, 0.45)
	pq.material = pm
	_charge_fx.mesh = pq
	_gem.add_child(_charge_fx)

	# the beam itself: a long glowing strip that shoots forward from the diamond
	_beam_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_beam_mat.shader = sh
	var bq := QuadMesh.new()
	bq.size = Vector2(BEAM_LEN, 2.4)
	_beam = MeshInstance3D.new()
	_beam.mesh = bq
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(-BEAM_LEN * 0.5, 0, 0.02)   # the art faces -x, so forward is -x here
	_beam.visible = false
	_gem.add_child(_beam)

	_beam_box = Area3D.new()
	_beam_box.collision_layer = 16
	_beam_box.collision_mask = 4 | 8
	_beam_box.monitoring = true
	_beam_box.monitorable = false
	_beam_box.top_level = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BEAM_LEN, 1.6, 2.0)
	cs.shape = box
	_beam_box.add_child(cs)
	add_child(_beam_box)

	_beam_sfx = AudioStreamPlayer.new()
	_beam_sfx.stream = _make_beam_sound()
	_beam_sfx.volume_db = -6.0
	add_child(_beam_sfx)


func _update_beam(delta: float) -> void:
	if _beam_state == 0:
		if Input.is_action_just_pressed("flutte_special") and special_ready() and _atk == Atk.NONE and _tail_t < 0.0:
			add_bamboo(-SPECIAL_COST)
			_beam_state = 1
			_beam_t = 0.0
			_charge_fx.emitting = true
			_beam_sfx.play()
		return
	_beam_t += delta
	match _beam_state:
		1:  # charge up: the diamond glows brighter and brighter
			var k := clampf(_beam_t / T_CHARGE, 0.0, 1.0)
			_gem_mat.albedo_color.a = k
			_gem_glow.scale = Vector3.ONE * (0.4 + 0.8 * k + sin(_beam_t * 40.0) * 0.08)
			_shake = maxf(_shake, 0.02 * k)
			if _beam_t >= T_CHARGE:
				_beam_state = 2
				_beam_t = 0.0
				_charge_fx.emitting = false
				_beam.visible = true
				_beam_tick = 0.0
				_beam_hit_list.clear()
		2:  # FIRE
			var grow := clampf(_beam_t / 0.12, 0.0, 1.0)
			_beam_mat.set_shader_parameter("reach", grow)
			_beam_mat.set_shader_parameter("width", grow)
			_gem_mat.albedo_color.a = 1.0
			_gem_glow.scale = Vector3.ONE * (1.6 + sin(_beam_t * 50.0) * 0.15)
			_shake = maxf(_shake, 0.1)
			_beam_tick -= delta
			if _beam_tick <= 0.0:
				_beam_tick = 0.1
				_beam_hits()
			if _beam_t >= T_BEAM:
				_beam_state = 3
				_beam_t = 0.0
		3:  # fade out
			var k := 1.0 - clampf(_beam_t / T_BEAM_END, 0.0, 1.0)
			_beam_mat.set_shader_parameter("width", k)
			_gem_mat.albedo_color.a = k
			if _beam_t >= T_BEAM_END:
				_beam_state = 0
				_beam.visible = false
				_gem_mat.albedo_color.a = 0.0


func _beam_hits() -> void:
	var start := _gem.global_position
	_beam_box.global_position = Vector3(start.x + facing * BEAM_LEN * 0.5, start.y, 0)
	for b in _beam_box.get_overlapping_bodies():
		if b != self and b.has_method("take_hit") and not (b in _beam_hit_list):
			_beam_hit_list.append(b)
			b.call("take_hit", 8, self)          # one hit from the beam beats a ninja
	for a in _beam_box.get_overlapping_areas():
		if a in _beam_hit_list:
			continue
		_beam_hit_list.append(a)
		if a.has_method("on_staff_hit"):
			a.call("on_staff_hit", self)      # the beam scoops up bamboo and smashes lanterns
		elif a.has_method("take_hit"):
			a.call("take_hit", 8, self)


const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float reach = 0.0;    // how far the beam has shot out (0..1)
uniform float width = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float u = 1.0 - UV.x;                 // 0 at the diamond, 1 at the far end
	float v = (UV.y - 0.5) * 2.0;
	if (u > reach) { discard; }
	float wob = 1.0 + 0.12 * sin(u * 60.0 - TIME * 40.0) + 0.08 * sin(u * 23.0 + TIME * 25.0);
	float w = max(width * wob * (0.55 + 0.45 * smoothstep(0.0, 0.08, u)), 0.001);
	float d = abs(v) / w;
	float core = exp(-d * d * 18.0);
	float body = exp(-d * d * 4.0);
	float halo = exp(-d * d * 2.2) * 0.6;
	float streak = noise(vec2(u * 30.0 - TIME * 18.0, v * 4.0));
	body *= 0.75 + 0.5 * streak;
	vec3 col = vec3(0.55, 0.0, 0.08) * halo + vec3(1.0, 0.12, 0.2) * body + vec3(1.0, 0.9, 0.9) * core;
	float tip = 1.0 - smoothstep(reach - 0.04, reach, u);
	float edge = 1.0 - smoothstep(0.55, 1.0, abs(v));      // fade out well before the strip's edge
	float a = clamp(halo * 0.7 + body + core, 0.0, 1.0) * tip * edge;
	ALBEDO = col / max(a, 0.001);
	ALPHA = a;
}
"""


static func _make_beam_sound() -> AudioStreamWAV:
	var rate := 22050
	var dur := T_CHARGE + T_BEAM + T_BEAM_END
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		if t < T_CHARGE:
			var k := t / T_CHARGE
			ph += TAU * lerpf(220.0, 880.0, k * k) / float(rate)
			s = sin(ph) * 0.25 * k
		else:
			var tt := t - T_CHARGE
			lp += (randf_range(-1.0, 1.0) - lp) * 0.25
			ph += TAU * (110.0 + sin(tt * 30.0) * 8.0) / float(rate)
			var env := minf(1.0, tt * 20.0) * (1.0 - smoothstep(T_BEAM, T_BEAM + T_BEAM_END, tt))
			s = (lp * 0.6 + sin(ph) * 0.35 + sin(ph * 3.01) * 0.12) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ======================================================================= firework cannon
func _build_cannon() -> void:
	_cannon = Sprite3D.new()
	_cannon.texture = load(_dir + "/firework_cannon.png")
	_cannon.pixel_size = 0.8 / 344.0
	_cannon.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	# held in front of his belly; the panda mouth points forward (-x in the art)
	_cannon.position = _p(Vector2(70, 470), HIPS) + Vector3(0, 0, 0.03)
	_cannon.visible = false
	_upper.add_child(_cannon)


func _update_cannon(delta: float) -> void:
	_fire_cd -= delta
	if _cannon_t > 0.0:
		_cannon_t -= delta
		var kick := clampf(_cannon_t - 0.2, 0.0, 0.15) / 0.15     # recoil right after firing
		_cannon.position = _p(Vector2(70, 470), HIPS) + Vector3(0.1 * kick, 0, 0.03)
		if _cannon_t <= 0.0:
			_cannon.visible = false
	if Input.is_action_just_pressed("flutte_fire") and rockets > 0 and _fire_cd <= 0.0 and _beam_state == 0 and _tail_t < 0.0:
		rockets -= 1
		rockets_changed.emit(rockets)
		_fire_cd = 0.3
		_cannon_t = 0.5
		_cannon.visible = true
		var rocket: Area3D = load(_dir + "/firework_rocket.gd").new()
		rocket.set("dir", facing)
		get_parent().add_child(rocket)
		var muzzle := _cannon.global_position + Vector3(facing * 0.45, 0.02, 0.05)
		rocket.global_position = muzzle
		_shake = maxf(_shake, 0.05)
		velocity.x -= facing * 1.5
		_dust(Vector3(facing * 0.9, 0.95, 0.15), Vector3(facing * 1.0, 0.4, 0))


# ======================================================================= input
func _setup_input() -> void:
	_add_action("flutte_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("flutte_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("flutte_jump", [KEY_SPACE, KEY_W, KEY_UP], [JOY_BUTTON_A])
	_add_action("flutte_run", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER], [JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_add_action("flutte_attack", [KEY_J, KEY_F], [JOY_BUTTON_X])
	_add_action("flutte_tail", [KEY_K, KEY_L], [JOY_BUTTON_B])
	_add_action("flutte_special", [KEY_Q, KEY_E], [JOY_BUTTON_Y])
	_add_action("flutte_fire", [KEY_G, KEY_R], [JOY_BUTTON_LEFT_SHOULDER])


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
