extends CanvasLayer
## HUD:
##   * bamboo counter (top right). At 50+ bamboo the icon turns RED and pulses:
##     the red beam is ready. Tap / click the icon (or press Q, gamepad Y) to fire.
##   * health bar (bottom middle) with Flutte's picture next to it.

const SPECIAL_COST := 50

var _label: Label
var _ready_label: Label
var _box: HBoxContainer
var _icon: Control
var _health: Control
var _portrait: Texture2D
var _player: Node = null
var _bamboo := 0
var _hp := 100.0
var _hp_max := 100.0
var _hp_shown := 1.0      # smooth fill
var _hp_lag := 1.0        # white "damage" bar that catches up slowly
var _flash := 0.0
var _time := 0.0


func _ready() -> void:
	layer = 20
	add_to_group("bamboo_hud")
	var dir: String = get_script().resource_path.get_base_dir()
	if ResourceLoader.exists(dir + "/flutte_portrait.png"):
		_portrait = load(dir + "/flutte_portrait.png")

	# ---- bamboo counter, top right
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.position = Vector2(-250, 22)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_box)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(40, 52)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	_box.add_child(_icon)
	_label = Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 38
	ls.font_color = Color(1, 1, 1)
	ls.outline_size = 10
	ls.outline_color = Color(0.45, 0.12, 0.2)
	_label.label_settings = ls
	_label.text = "x 0"
	_box.add_child(_label)
	_ready_label = Label.new()
	var rs := LabelSettings.new()
	rs.font_size = 20
	rs.font_color = Color(1.0, 0.85, 0.85)
	rs.outline_size = 6
	rs.outline_color = Color(0.5, 0.0, 0.05)
	_ready_label.label_settings = rs
	_ready_label.text = "BEAM READY!  tap / Q"
	_ready_label.position = Vector2(-6, 58)
	_ready_label.visible = false
	anchor.add_child(_ready_label)

	# ---- health bar, bottom middle
	_health = Control.new()
	_health.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_health.custom_minimum_size = Vector2(640, 120)
	_health.size = Vector2(640, 120)
	_health.position = Vector2(-320, -132)
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health.draw.connect(_draw_health)
	add_child(_health)

	_connect_player.call_deferred()


func _connect_player() -> void:
	for i in 10:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_signal("bamboo_changed"):
			_player = p
			p.connect("bamboo_changed", _on_bamboo_changed)
			if p.has_signal("health_changed"):
				p.connect("health_changed", _on_health_changed)
				_hp = float(p.get("health"))
				_hp_max = float(p.get("max_health"))
			return
		await get_tree().process_frame


func _process(delta: float) -> void:
	_time += delta
	var target := _hp / maxf(_hp_max, 1.0)
	_hp_shown = lerpf(_hp_shown, target, minf(1.0, delta * 10.0))
	_hp_lag = move_toward(_hp_lag, target, delta * (0.35 if _hp_lag > target else 5.0))
	_flash = maxf(0.0, _flash - delta * 2.5)
	_health.queue_redraw()
	if _bamboo >= SPECIAL_COST:
		_icon.queue_redraw()


func _input(event: InputEvent) -> void:
	# tap / click the red bamboo icon to fire the beam
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and _bamboo >= SPECIAL_COST:
		var r := Rect2(_box.global_position - Vector2(16, 16), _box.size + Vector2(32, 60))
		if r.has_point((event as InputEventScreenTouch).position):
			Input.action_press("flutte_special")
			_release_special.call_deferred()
			get_viewport().set_input_as_handled()


func _release_special() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("flutte_special")


func _on_bamboo_changed(total: int) -> void:
	var was_ready := _bamboo >= SPECIAL_COST
	_bamboo = total
	_label.text = "x %d" % total
	var now_ready := total >= SPECIAL_COST
	_ready_label.visible = now_ready
	_label.label_settings.outline_color = Color(0.6, 0.0, 0.05) if now_ready else Color(0.45, 0.12, 0.2)
	_box.pivot_offset = Vector2(40, 26)
	_box.scale = Vector2(1.45, 1.45) if (now_ready and not was_ready) else Vector2(1.25, 1.25)
	create_tween().tween_property(_box, "scale", Vector2.ONE, 0.22)
	_icon.queue_redraw()


func _on_health_changed(current: int, maximum: int) -> void:
	if current < _hp:
		_flash = 1.0
	_hp = float(current)
	_hp_max = float(maximum)


func _draw_icon() -> void:
	var c := _icon
	var ready := _bamboo >= SPECIAL_COST
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var dark := Color(0.45, 0.02, 0.05) if ready else Color(0.22, 0.38, 0.10)
	var main := Color(0.95, 0.12, 0.15) if ready else Color(0.55, 0.78, 0.26)
	var hi := Color(1.0, 0.6, 0.6) if ready else Color(0.82, 0.94, 0.5)
	var leaf := Color(0.85, 0.1, 0.12) if ready else Color(0.36, 0.68, 0.22)
	if ready:
		c.draw_circle(Vector2(20, 26), 30.0 + pulse * 6.0, Color(1.0, 0.15, 0.2, 0.25 + 0.2 * pulse))
	c.draw_set_transform(Vector2(20, 26), deg_to_rad(20.0), Vector2.ONE)
	c.draw_rect(Rect2(-8, -24, 16, 48), dark)
	c.draw_rect(Rect2(-6, -22, 12, 44), main)
	c.draw_rect(Rect2(-4, -22, 3.5, 44), hi)
	c.draw_rect(Rect2(-8, -8.5, 16, 4), dark)
	c.draw_rect(Rect2(-8, 6.5, 16, 4), dark)
	c.draw_colored_polygon(PackedVector2Array([Vector2(6, -8), Vector2(20, -18), Vector2(10, -2)]), leaf)


func _draw_health() -> void:
	var c := _health
	var ratio := clampf(_hp_shown, 0.0, 1.0)
	var bar := Rect2(118, 44, 500, 38)
	# frame
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.12, 0.04, 0.08, 0.8)
	frame.set_corner_radius_all(19)
	frame.border_color = Color(1, 1, 1, 0.95)
	frame.set_border_width_all(4)
	c.draw_style_box(frame, bar.grow(6))
	# white lag bar (shows the chunk you just lost)
	var inner := bar.grow(-2)
	if _hp_lag > ratio:
		var lag := StyleBoxFlat.new()
		lag.bg_color = Color(1, 1, 1, 0.85)
		lag.set_corner_radius_all(16)
		c.draw_style_box(lag, Rect2(inner.position, Vector2(inner.size.x * _hp_lag, inner.size.y)))
	# fill: green -> yellow -> red
	if ratio > 0.0:
		var col := Color(0.35, 0.85, 0.3)
		if ratio < 0.6:
			col = Color(0.35, 0.85, 0.3).lerp(Color(1.0, 0.8, 0.15), (0.6 - ratio) / 0.3)
		if ratio < 0.3:
			col = Color(1.0, 0.8, 0.15).lerp(Color(0.95, 0.15, 0.15), (0.3 - ratio) / 0.3)
		col = col.lerp(Color.WHITE, _flash * 0.6)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(16)
		var w := maxf(inner.size.y, inner.size.x * ratio)
		c.draw_style_box(fill, Rect2(inner.position, Vector2(w, inner.size.y)))
		c.draw_rect(Rect2(inner.position + Vector2(14, 5), Vector2(maxf(0.0, w - 28.0), 6)), Color(1, 1, 1, 0.35))
	# segment ticks
	for i in range(1, 10):
		var x := inner.position.x + inner.size.x * i / 10.0
		c.draw_line(Vector2(x, inner.position.y + 6), Vector2(x, inner.end.y - 6), Color(0, 0, 0, 0.25), 2.0)
	# label
	var font := ThemeDB.fallback_font
	var txt := "%d / %d" % [int(_hp), int(_hp_max)]
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var tp := Vector2(bar.get_center().x - tw * 0.5, bar.get_center().y + 9)
	c.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color(0.2, 0.05, 0.1))
	c.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	# portrait
	var center := Vector2(62, 62)
	var shake := Vector2(randf_range(-4, 4), randf_range(-4, 4)) * _flash
	c.draw_circle(center + shake, 58.0, Color.WHITE)
	c.draw_circle(center + shake, 54.0, Color(0.9, 0.25, 0.2).lerp(Color(1, 0.4, 0.4), _flash))
	if _portrait:
		c.draw_texture_rect(_portrait, Rect2(center + shake - Vector2(52, 52), Vector2(104, 104)), false, Color(1, 1, 1).lerp(Color(1, 0.5, 0.5), _flash))
	c.draw_arc(center + shake, 56.0, 0.0, TAU, 48, Color(0.45, 0.12, 0.2), 4.0, true)
