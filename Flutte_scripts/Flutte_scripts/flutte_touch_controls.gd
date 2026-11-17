extends CanvasLayer
## On-screen controls for FLUTTE.
##   * Virtual joystick (left side): drag anywhere on the left of the screen.
##     Push a little to walk, push all the way to run.
##   * JUMP button (bottom right) - tap again in the air to double jump.
##   * STAFF button - swing the bamboo staff.
##   * Top-left buttons:  ?  = show / hide the instructions
##                        joystick icon = show / hide the touch controls
##                        sun / moon = day / night
## Keyboard shortcuts: H = instructions, T = touch controls, N = day / night.
## Gamepad: Back/Select = instructions, Start = day / night.
## The touch controls start visible on phones/tablets and hidden on computers.

const JOY_RADIUS := 120.0
const KNOB_RADIUS := 52.0
const JUMP_RADIUS := 96.0
const STAFF_RADIUS := 80.0
const TOP_RADIUS := 34.0
const RUN_PUSH := 0.85
const DEAD_ZONE := 0.18

var level: Node = null
var controls_visible := false
var help_visible := true

var _canvas: Control
var _joy_index := -1
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _jump_index := -1
var _staff_index := -1
var _hint: Label = null
var _day_night: Node = null
var _font: Font


func _ready() -> void:
	layer = 30
	add_to_group("flutte_touch_controls")
	controls_visible = DisplayServer.is_touchscreen_available()
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_add_shortcut("flutte_toggle_help", KEY_H, JOY_BUTTON_BACK)
	_add_shortcut("flutte_toggle_touch", KEY_T, -1)
	_add_shortcut("flutte_day_night", KEY_N, JOY_BUTTON_START)
	_hook_level.call_deferred()


func _hook_level() -> void:
	if level == null:
		level = get_tree().current_scene
	if level == null:
		return
	_hint = level.get_node_or_null("HUD/Hint") as Label
	if _hint:
		_hint.offset_top = 96.0
		_hint.offset_right = 1880.0
		_hint.add_theme_font_size_override("font_size", 24)
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_day_night = level.get_node_or_null("DayNight")
	if _day_night:
		# the old "double-tap anywhere" switch fights with the touch buttons,
		# so day / night now lives on its own button (and the N key)
		_day_night.set_process_unhandled_input(false)
	_refresh_hint()


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


# ------------------------------------------------------------------ layout
func _size() -> Vector2:
	return _canvas.size if _canvas.size.x > 10.0 else get_viewport().get_visible_rect().size


func _joy_home() -> Vector2:
	var s := _size()
	return Vector2(230.0, s.y - 230.0)


func _jump_pos() -> Vector2:
	var s := _size()
	return Vector2(s.x - 170.0, s.y - 190.0)


func _staff_pos() -> Vector2:
	var s := _size()
	return Vector2(s.x - 390.0, s.y - 120.0)


func _top_pos(i: int) -> Vector2:
	return Vector2(52.0 + i * 84.0, 52.0)


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("flutte_toggle_help"):
		_toggle_help()
	elif event.is_action_pressed("flutte_toggle_touch"):
		_toggle_controls()
	elif event.is_action_pressed("flutte_day_night"):
		_toggle_day_night()

	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var pos := _to_canvas(t.position)
		if t.pressed:
			if _handle_press(t.index, pos):
				get_viewport().set_input_as_handled()
		else:
			if _handle_release(t.index):
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			_move_joy(_to_canvas(d.position))
			get_viewport().set_input_as_handled()


func _to_canvas(p: Vector2) -> Vector2:
	# touch positions arrive in viewport space; the canvas may be scaled
	return _canvas.get_global_transform_with_canvas().affine_inverse() * p


func _handle_press(index: int, pos: Vector2) -> bool:
	# top-left buttons work even when the touch controls are hidden
	for i in 3:
		if pos.distance_to(_top_pos(i)) <= TOP_RADIUS + 14.0:
			match i:
				0: _toggle_help()
				1: _toggle_controls()
				2: _toggle_day_night()
			return true
	if not controls_visible:
		return false
	if pos.distance_to(_jump_pos()) <= JUMP_RADIUS + 20.0:
		_jump_index = index
		Input.action_press("flutte_jump")
		return true
	if pos.distance_to(_staff_pos()) <= STAFF_RADIUS + 20.0:
		_staff_index = index
		Input.action_press("flutte_attack")
		return true
	var s := _size()
	if pos.x < s.x * 0.45 and pos.y > 140.0 and _joy_index == -1:
		_joy_index = index
		_joy_base = pos
		_joy_knob = pos
		_apply_joy()
		return true
	return false


func _handle_release(index: int) -> bool:
	if index < 0:
		return false
	if index == _jump_index:
		_jump_index = -1
		Input.action_release("flutte_jump")
		return true
	if index == _staff_index:
		_staff_index = -1
		Input.action_release("flutte_attack")
		return true
	if index == _joy_index:
		_joy_index = -1
		_release_move()
		return true
	return false


func _move_joy(pos: Vector2) -> void:
	var v := pos - _joy_base
	if v.length() > JOY_RADIUS:
		# drag the base along so the stick never "runs out"
		_joy_base = pos - v.normalized() * JOY_RADIUS
		v = pos - _joy_base
	_joy_knob = _joy_base + v
	_apply_joy()


func _apply_joy() -> void:
	var v := (_joy_knob - _joy_base) / JOY_RADIUS
	var x := clampf(v.x, -1.0, 1.0)
	if absf(x) < DEAD_ZONE:
		_release_move()
		return
	var strength := clampf((absf(x) - DEAD_ZONE) / (1.0 - DEAD_ZONE) * 1.15, 0.25, 1.0)
	if x > 0.0:
		Input.action_release("flutte_left")
		Input.action_press("flutte_right", strength)
	else:
		Input.action_release("flutte_right")
		Input.action_press("flutte_left", strength)
	if absf(x) >= RUN_PUSH:
		Input.action_press("flutte_run")
	else:
		Input.action_release("flutte_run")


func _release_move() -> void:
	Input.action_release("flutte_left")
	Input.action_release("flutte_right")
	Input.action_release("flutte_run")


# ------------------------------------------------------------------ toggles
func _toggle_help() -> void:
	help_visible = not help_visible
	if _hint:
		_hint.visible = help_visible


func _toggle_controls() -> void:
	controls_visible = not controls_visible
	if not controls_visible:
		_joy_index = -1
		_jump_index = -1
		_staff_index = -1
		_release_move()
		Input.action_release("flutte_jump")
		Input.action_release("flutte_attack")
	_refresh_hint()


func _toggle_day_night() -> void:
	if _day_night and _day_night.has_method("set_night"):
		_day_night.call("set_night", not bool(_day_night.get("_is_night")))


func _refresh_hint() -> void:
	if _hint == null:
		return
	var t := "BAMBOO FOREST\n"
	if controls_visible:
		t += "Joystick: walk (push all the way to run)    JUMP: jump, tap again in the air to double jump    STAFF: swing\n"
	t += "Keys: A/D walk   Shift run   Space jump (twice = double jump)   J or F swing staff   N day/night   H hide help\n"
	t += "Gamepad: stick walk   A jump   X swing   RB run   Start day/night   Select hide help"
	_hint.text = t
	_hint.visible = help_visible


func _add_shortcut(action: String, key: Key, joy: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).size() > 0:
		return
	var e := InputEventKey.new()
	e.physical_keycode = key
	InputMap.action_add_event(action, e)
	if joy >= 0:
		var j := InputEventJoypadButton.new()
		j.button_index = joy as JoyButton
		InputMap.action_add_event(action, j)


# ------------------------------------------------------------------ drawing
func _draw_controls() -> void:
	var c := _canvas
	# top-left buttons
	_round_button(_top_pos(0), TOP_RADIUS, help_visible)
	_text_center("?", _top_pos(0), 40, Color.WHITE)
	_round_button(_top_pos(1), TOP_RADIUS, controls_visible)
	_draw_joy_icon(_top_pos(1))
	_round_button(_top_pos(2), TOP_RADIUS, false)
	_draw_sun_moon(_top_pos(2))

	if not controls_visible:
		return
	# joystick
	var base := _joy_base if _joy_index != -1 else _joy_home()
	var knob := _joy_knob if _joy_index != -1 else _joy_home()
	var a := 0.55 if _joy_index != -1 else 0.3
	c.draw_circle(base, JOY_RADIUS, Color(0.1, 0.05, 0.12, a * 0.6))
	c.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, a + 0.15), 5.0, true)
	c.draw_arc(base, JOY_RADIUS * RUN_PUSH, 0.0, TAU, 48, Color(1, 1, 1, a * 0.4), 2.0, true)
	c.draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, a + 0.3))
	c.draw_circle(knob, KNOB_RADIUS * 0.62, Color(0.95, 0.35, 0.3, a + 0.3))

	# jump
	var jp := _jump_pos()
	var jdown := _jump_index != -1
	c.draw_circle(jp, JUMP_RADIUS, Color(0.15, 0.55, 0.95, 0.85 if jdown else 0.55))
	c.draw_arc(jp, JUMP_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 5.0, true)
	c.draw_colored_polygon(PackedVector2Array([jp + Vector2(0, -42), jp + Vector2(-34, 2), jp + Vector2(34, 2)]), Color.WHITE)
	_text_center("JUMP", jp + Vector2(0, 40), 30, Color.WHITE)

	# staff
	var sp := _staff_pos()
	var sdown := _staff_index != -1
	c.draw_circle(sp, STAFF_RADIUS, Color(0.3, 0.7, 0.2, 0.85 if sdown else 0.55))
	c.draw_arc(sp, STAFF_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 5.0, true)
	c.draw_arc(sp + Vector2(6, 14), 46.0, deg_to_rad(200), deg_to_rad(330), 16, Color(1, 1, 0.8, 0.9), 7.0, true)
	c.draw_line(sp + Vector2(-34, 24), sp + Vector2(30, -40), Color(0.2, 0.35, 0.08), 13.0)
	c.draw_line(sp + Vector2(-34, 24), sp + Vector2(30, -40), Color(0.75, 0.9, 0.35), 8.0)
	_text_center("STAFF", sp + Vector2(0, 46), 26, Color.WHITE)


func _round_button(p: Vector2, r: float, on: bool) -> void:
	_canvas.draw_circle(p, r, Color(0.45, 0.12, 0.2, 0.75) if on else Color(0.1, 0.05, 0.12, 0.45))
	_canvas.draw_arc(p, r, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 3.0, true)


func _text_center(t: String, p: Vector2, size: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_canvas.draw_string_outline(_font, p + Vector2(-w * 0.5, size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.6))
	_canvas.draw_string(_font, p + Vector2(-w * 0.5, size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_joy_icon(p: Vector2) -> void:
	_canvas.draw_arc(p, 18.0, 0.0, TAU, 24, Color.WHITE, 3.0, true)
	_canvas.draw_circle(p + Vector2(5, -4), 8.0, Color.WHITE)


func _draw_sun_moon(p: Vector2) -> void:
	var night := _day_night != null and bool(_day_night.get("_is_night"))
	if night:
		_canvas.draw_circle(p, 16.0, Color(1.0, 0.95, 0.7))
		_canvas.draw_circle(p + Vector2(8, -6), 14.0, Color(0.1, 0.05, 0.12, 0.95))
	else:
		_canvas.draw_circle(p, 11.0, Color(1.0, 0.85, 0.3))
		for i in 8:
			var d := Vector2.from_angle(TAU * i / 8.0)
			_canvas.draw_line(p + d * 15.0, p + d * 22.0, Color(1.0, 0.85, 0.3), 3.0)
