extends CanvasLayer
## Title screen. Shows the painted FLUTTE title picture over the level and pauses
## the game until "Start Game" is tapped. The three menu words are part of the
## picture, so this script only places invisible tap areas on top of them.

const IMG := Vector2(1672.0, 941.0)
const START := Rect2(800, 430, 450, 100)
const SETTINGS := Rect2(900, 528, 260, 62)
const QUIT := Rect2(940, 604, 180, 62)

var _pic: TextureRect
var _glow: Panel
var _panel: PanelContainer
var _t := 0.0
var _closing := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_pic = TextureRect.new()
	_pic.texture = load(get_script().resource_path.get_base_dir() + "/flutte_title.jpg")
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)

	_glow = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.9, 0.7, 0.10)
	sb.border_color = Color(1.0, 0.92, 0.75, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(1.0, 0.5, 0.4, 0.55)
	sb.shadow_size = 18
	_glow.add_theme_stylebox_override("panel", sb)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	_build_settings()


func _map() -> Array:
	var v := get_viewport().get_visible_rect().size
	var sc := maxf(v.x / IMG.x, v.y / IMG.y)
	return [sc, (v - IMG * sc) * 0.5]


func _process(delta: float) -> void:
	_t += delta
	var m := _map()
	var sc: float = m[0]
	_glow.position = START.position * sc + (m[1] as Vector2)
	_glow.size = START.size * sc
	_glow.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 3.2))
	_glow.visible = not _panel.visible


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo and not _panel.visible:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_KP_ENTER:
			_start()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _panel.visible:
		return                     # the settings buttons handle their own taps
	var m := _map()
	var p: Vector2 = (event.position - (m[1] as Vector2)) / float(m[0])
	if START.has_point(p):
		_start()
	elif SETTINGS.has_point(p):
		_panel.visible = true
	elif QUIT.has_point(p):
		if OS.has_feature("web"):
			return                 # a browser tab can't be closed by the game
		get_tree().quit()
	get_viewport().set_input_as_handled()


func _start() -> void:
	_closing = true
	_glow.visible = false
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_pic, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _build_settings() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.05, 0.12, 0.94)
	sb.border_color = Color(1.0, 0.85, 0.6)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(36)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sound := _button("Sound: ON")
	sound.pressed.connect(func():
		var mute := not AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, mute)
		sound.text = "Sound: OFF" if mute else "Sound: ON")
	box.add_child(sound)
	var full := _button("Fullscreen: OFF")
	full.pressed.connect(func():
		var on := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		full.text = "Fullscreen: ON" if on else "Fullscreen: OFF")
	box.add_child(full)
	var back := _button("Back")
	back.pressed.connect(func(): _panel.visible = false)
	box.add_child(back)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 96)
	b.add_theme_font_size_override("font_size", 44)
	return b
