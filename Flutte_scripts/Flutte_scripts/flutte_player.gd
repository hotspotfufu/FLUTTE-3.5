extends CharacterBody2D
## Flutte the panda: walk / run, jump, and swing the bamboo staff.
## Everything (collision, sprite, staff, hitbox, camera, sounds, input keys)
## is created in code, so this script works on an empty CharacterBody2D.
##
## Controls (added automatically, your own project keys are left alone):
##   Move   : A / D  or  Left / Right  or  gamepad left stick
##   Run    : hold Shift  (gamepad: right shoulder)
##   Jump   : Space / W / Up  (gamepad: A)   - hold for higher jumps
##   Attack : J / K / left mouse click  (gamepad: X)
##   Camera : Tab switches between Flutte's camera and the level preview camera

signal bamboo_changed(total: int)
signal attacked

@export_group("Movement")
@export var walk_speed := 260.0
@export var run_speed := 470.0
@export var ground_accel := 2200.0
@export var ground_friction := 2600.0
@export var air_accel := 1500.0

@export_group("Jump")
@export var jump_velocity := -640.0
@export var gravity := 1650.0
@export var fall_gravity_multiplier := 1.6
@export var max_fall_speed := 1150.0
@export var coyote_time := 0.10        ## jump still works just after walking off a ledge
@export var jump_buffer_time := 0.12   ## jump pressed just before landing still counts
@export var jump_cut_multiplier := 0.45 ## letting go of jump early = shorter hop

@export_group("Attack")
@export var attack_duration := 0.30
@export var attack_cooldown := 0.10
@export var attack_damage := 1
@export var staff_length := 78.0

@export_group("Look")
@export var sprite_path := "res://Assets/Characters/Panda/panda_side.png"
@export var character_height := 110.0  ## on-screen height in pixels
@export var sprite_faces_right := true ## untick if panda_side.png faces left
@export var use_own_camera := true
@export var camera_zoom := Vector2.ONE

@export_group("Respawn")
@export var kill_y := 4000.0           ## falling below this y respawns Flutte
var spawn_point := Vector2.ZERO

const STAFF_REST := -1.15
const SWING_START := -2.35
const SWING_END := 0.95

var bamboo := 0
var facing := 1

var _coyote := 0.0
var _jump_buffer := 0.0
var _attack_timer := 0.0
var _cooldown := 0.0
var _hit_this_swing: Array = []
var _walk_t := 0.0
var _squash := Vector2.ONE
var _was_on_floor := true

var _visual: Node2D
var _sprite: Sprite2D
var _staff_pivot: Node2D
var _swoosh: SwooshDrawing
var _hitbox: Area2D
var _hitbox_shape: CollisionShape2D
var _camera: Camera2D
var _other_camera: Camera2D
var _sfx: AudioStreamPlayer
var _hand := Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	z_index = 10
	spawn_point = global_position
	_setup_input()
	_hand = Vector2(character_height * 0.16, -character_height * 0.45)

	# --- collision (feet are at this node's origin) ---
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var cap := CapsuleShape2D.new()
		cap.radius = character_height * 0.26
		cap.height = character_height * 0.9
		col.shape = cap
		col.position = Vector2(0, -cap.height * 0.5)
		add_child(col)

	# --- visuals (flipped left/right as a whole) ---
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var tex: Texture2D = null
	if ResourceLoader.exists(sprite_path):
		tex = load(sprite_path)
	if tex:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		var s := character_height / float(tex.get_height())
		_sprite.scale = Vector2(s, s)
		_sprite.offset = Vector2(0, -tex.get_height() * 0.5)
		_sprite.flip_h = not sprite_faces_right
		_visual.add_child(_sprite)
	else:
		var panda := PandaDrawing.new()
		panda.h = character_height
		_visual.add_child(panda)

	_swoosh = SwooshDrawing.new()
	_swoosh.position = _hand
	_swoosh.radius = staff_length * 0.72
	_visual.add_child(_swoosh)

	_staff_pivot = Node2D.new()
	_staff_pivot.name = "Staff"
	_staff_pivot.position = _hand
	_staff_pivot.rotation = STAFF_REST
	var staff := StaffDrawing.new()
	staff.length = staff_length
	_staff_pivot.add_child(staff)
	_visual.add_child(_staff_pivot)

	# --- staff hitbox (not inside _visual so physics never sees a negative scale) ---
	_hitbox = Area2D.new()
	_hitbox.name = "StaffHitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 0xFF   # layers 1-8: enemies, breakables, bamboo
	_hitbox.monitorable = false
	_hitbox_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = staff_length * 0.62
	_hitbox_shape.shape = circle
	_hitbox.add_child(_hitbox_shape)
	add_child(_hitbox)

	# --- sound ---
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = _make_whoosh()
	_sfx.volume_db = -6.0
	add_child(_sfx)

	# --- camera ---
	if use_own_camera:
		_other_camera = get_viewport().get_camera_2d()
		_camera = Camera2D.new()
		_camera.name = "FlutteCamera"
		_camera.zoom = camera_zoom
		_camera.offset = Vector2(0, -character_height * 0.8)
		_camera.position_smoothing_enabled = true
		_camera.position_smoothing_speed = 7.0
		add_child(_camera)
		_camera.call_deferred("make_current")


func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("flutte_left", "flutte_right")
	var running := Input.is_action_pressed("flutte_run")
	var on_floor := is_on_floor()

	# coyote time + jump buffer
	if on_floor:
		_coyote = coyote_time
	else:
		_coyote -= delta
	if Input.is_action_just_pressed("flutte_jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer -= delta

	# gravity (falls faster than it rises - feels snappier)
	if not on_floor:
		var g := gravity
		if velocity.y > 0.0:
			g *= fall_gravity_multiplier
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)

	# jump
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_squash = Vector2(0.8, 1.22)
	if Input.is_action_just_released("flutte_jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	# walk / run
	var target := (run_speed if running else walk_speed) * dir
	var accel := ground_accel if on_floor else air_accel
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, target, accel * delta)
		if _attack_timer <= 0.0:
			facing = 1 if dir > 0.0 else -1
	else:
		var friction := ground_friction if on_floor else air_accel * 0.4
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.25, 0.78)   # landing squish
	_was_on_floor = is_on_floor()

	_update_attack(delta)

	if global_position.y > kill_y:
		respawn()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flutte_camera") and _camera:
		if _camera.is_current() and is_instance_valid(_other_camera):
			_other_camera.make_current()
		else:
			_camera.make_current()


# ---------------------------------------------------------------- attack
func _update_attack(delta: float) -> void:
	_cooldown -= delta
	if Input.is_action_just_pressed("flutte_attack") and _attack_timer <= 0.0 and _cooldown <= 0.0:
		_attack_timer = attack_duration
		_hit_this_swing.clear()
		_sfx.pitch_scale = randf_range(0.9, 1.15)
		_sfx.play()
		if is_on_floor():
			velocity.x += facing * 90.0   # little lunge
		attacked.emit()

	_hitbox_shape.position = Vector2(facing * (_hand.x + staff_length * 0.45), _hand.y - staff_length * 0.05)

	if _attack_timer > 0.0:
		_attack_timer -= delta
		var t := clampf(1.0 - _attack_timer / attack_duration, 0.0, 1.0)
		var angle: float
		if t < 0.6:
			var k := 1.0 - pow(1.0 - t / 0.6, 3.0)
			angle = lerpf(SWING_START, SWING_END, k)
			_swoosh.show_arc(SWING_START, angle, 1.0)
		else:
			angle = lerpf(SWING_END, STAFF_REST, (t - 0.6) / 0.4)
			_swoosh.show_arc(SWING_START, SWING_END, 1.0 - (t - 0.6) / 0.4)
		_staff_pivot.rotation = angle
		if t > 0.15 and t < 0.8:
			_check_hits()
		if _attack_timer <= 0.0:
			_cooldown = attack_cooldown
			_staff_pivot.rotation = STAFF_REST
			_swoosh.show_arc(0.0, 0.0, 0.0)


func _check_hits() -> void:
	for body in _hitbox.get_overlapping_bodies():
		_hit(body)
	for area in _hitbox.get_overlapping_areas():
		_hit(area)


func _hit(target: Node) -> void:
	if target == self or target in _hit_this_swing:
		return
	_hit_this_swing.append(target)
	if target.has_method("on_staff_hit"):
		target.call("on_staff_hit", self)          # e.g. bamboo sticks, breakable crates
	elif target.has_method("take_hit"):
		target.call("take_hit", attack_damage, self) # enemies you add later


func is_attacking() -> bool:
	return _attack_timer > 0.0


# ---------------------------------------------------------------- bamboo
func add_bamboo(amount: int = 1) -> void:
	bamboo += amount
	bamboo_changed.emit(bamboo)


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector2.ZERO


# ---------------------------------------------------------------- simple animation
func _process(delta: float) -> void:
	var speed_ratio := clampf(absf(velocity.x) / run_speed, 0.0, 1.0)
	if is_on_floor() and absf(velocity.x) > 15.0:
		_walk_t += delta * (9.0 + 11.0 * speed_ratio)
		_visual.position.y = -absf(sin(_walk_t)) * (3.0 + 5.0 * speed_ratio)
		_visual.rotation = sin(_walk_t * 2.0) * 0.03 + facing * 0.08 * speed_ratio
	else:
		_visual.position.y = lerpf(_visual.position.y, 0.0, minf(1.0, 12.0 * delta))
		_visual.rotation = lerpf(_visual.rotation, 0.0, minf(1.0, 10.0 * delta))
	_squash = _squash.lerp(Vector2.ONE, minf(1.0, 10.0 * delta))
	_visual.scale = Vector2(facing * _squash.x, _squash.y)


# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	_add_action("flutte_left", [KEY_A, KEY_LEFT], [], [], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("flutte_right", [KEY_D, KEY_RIGHT], [], [], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("flutte_jump", [KEY_SPACE, KEY_W, KEY_UP], [], [JOY_BUTTON_A])
	_add_action("flutte_run", [KEY_SHIFT], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("flutte_attack", [KEY_J, KEY_K], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X])
	_add_action("flutte_camera", [KEY_TAB], [], [JOY_BUTTON_BACK])


func _add_action(action: String, keys: Array, mouse: Array, joy: Array, axis: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	if InputMap.action_get_events(action).size() > 0:
		return  # already set up in Project Settings - keep the user's choice
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in mouse:
		var m := InputEventMouseButton.new()
		m.button_index = b
		InputMap.action_add_event(action, m)
	for j in joy:
		var jb := InputEventJoypadButton.new()
		jb.button_index = j
		InputMap.action_add_event(action, jb)
	if axis.size() == 2:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis[0]
		jm.axis_value = axis[1]
		InputMap.action_add_event(action, jm)


# ---------------------------------------------------------------- generated whoosh sound
static func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.5)
		var cutoff := lerpf(0.08, 0.35, sin(t * PI))
		lp += (randf_range(-1.0, 1.0) - lp) * cutoff
		data.encode_s16(i * 2, int(clampf(lp * env * 1.6, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ================================================================ drawings
class StaffDrawing extends Node2D:
	var length := 78.0

	func _draw() -> void:
		var a := Vector2(-length * 0.3, 0)
		var b := Vector2(length * 0.7, 0)
		draw_line(a, b, Color(0.22, 0.36, 0.10), 10.0)
		draw_line(a, b, Color(0.55, 0.76, 0.28), 6.0)
		draw_line(a + Vector2(0, -1.5), b + Vector2(0, -1.5), Color(0.80, 0.92, 0.50), 1.5)
		for i in range(1, 5):
			var p := a.lerp(b, i / 5.0)
			draw_line(p + Vector2(0, -5), p + Vector2(0, 5), Color(0.25, 0.42, 0.12), 2.5)


class SwooshDrawing extends Node2D:
	var radius := 56.0
	var a0 := 0.0
	var a1 := 0.0
	var alpha := 0.0

	func show_arc(from_angle: float, to_angle: float, strength: float) -> void:
		a0 = from_angle
		a1 = to_angle
		alpha = strength
		queue_redraw()

	func _draw() -> void:
		if alpha <= 0.01 or absf(a1 - a0) < 0.05:
			return
		draw_arc(Vector2.ZERO, radius, a0, a1, 24, Color(1, 1, 0.9, 0.55 * alpha), 14.0, true)
		draw_arc(Vector2.ZERO, radius + 4.0, a0, a1, 24, Color(0.8, 1.0, 0.6, 0.35 * alpha), 5.0, true)


class PandaDrawing extends Node2D:
	## Fallback drawing used only if panda_side.png can't be found.
	var h := 110.0

	func _draw() -> void:
		var black := Color(0.08, 0.08, 0.1)
		var white := Color(0.97, 0.97, 0.95)
		draw_circle(Vector2(-h * 0.1, -h * 0.07), h * 0.08, black)
		draw_circle(Vector2(h * 0.1, -h * 0.07), h * 0.08, black)
		draw_circle(Vector2(0, -h * 0.32), h * 0.25, white)
		draw_circle(Vector2(-h * 0.13, -h * 0.42), h * 0.08, black)
		draw_circle(Vector2(h * 0.16, -h * 0.45), h * 0.08, black)
		draw_circle(Vector2(-h * 0.12, -h * 0.86), h * 0.07, black)
		draw_circle(Vector2(h * 0.12, -h * 0.86), h * 0.07, black)
		draw_circle(Vector2(0, -h * 0.70), h * 0.20, white)
		draw_circle(Vector2(h * 0.02, -h * 0.72), h * 0.055, black)
		draw_circle(Vector2(h * 0.12, -h * 0.72), h * 0.055, black)
		draw_circle(Vector2(h * 0.03, -h * 0.73), h * 0.018, white)
		draw_circle(Vector2(h * 0.13, -h * 0.73), h * 0.018, white)
		draw_circle(Vector2(h * 0.17, -h * 0.65), h * 0.03, black)
