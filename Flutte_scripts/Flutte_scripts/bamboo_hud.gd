extends CanvasLayer
## Bamboo counter (top-left) + a controls hint that fades out after a few seconds.

@export var show_controls_hint := true
@export var hint_seconds := 8.0

var _label: Label
var _box: HBoxContainer


func _ready() -> void:
	layer = 20
	add_to_group("bamboo_hud")

	_box = HBoxContainer.new()
	_box.position = Vector2(24, 18)
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(34, 40)
	icon.draw.connect(func(): _draw_icon(icon))
	_box.add_child(icon)

	_label = Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 34
	ls.font_color = Color(1, 0.98, 0.85)
	ls.outline_size = 8
	ls.outline_color = Color(0.12, 0.22, 0.06)
	_label.label_settings = ls
	_label.text = "x 0"
	_box.add_child(_label)

	if show_controls_hint:
		var hint := Label.new()
		var hs := LabelSettings.new()
		hs.font_size = 18
		hs.outline_size = 6
		hs.outline_color = Color(0, 0, 0, 0.8)
		hint.label_settings = hs
		hint.text = "A/D or Arrows: walk   Shift: run   Space: jump   J or Click: swing staff   Tab: camera"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		hint.offset_top = -52
		hint.offset_bottom = -16
		add_child(hint)
		var tw := create_tween()
		tw.tween_interval(hint_seconds)
		tw.tween_property(hint, "modulate:a", 0.0, 1.2)
		tw.tween_callback(hint.queue_free)

	_connect_player.call_deferred()


func _connect_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		await get_tree().process_frame
		p = get_tree().get_first_node_in_group("player")
	if p and p.has_signal("bamboo_changed"):
		p.connect("bamboo_changed", _on_bamboo_changed)
		_label.text = "x %d" % int(p.get("bamboo"))


func _on_bamboo_changed(total: int) -> void:
	_label.text = "x %d" % total
	_box.pivot_offset = Vector2(20, 20)
	_box.scale = Vector2(1.25, 1.25)
	create_tween().tween_property(_box, "scale", Vector2.ONE, 0.18)


func _draw_icon(c: Control) -> void:
	var dark := Color(0.24, 0.42, 0.12)
	c.draw_set_transform(Vector2(17, 20), deg_to_rad(18.0), Vector2.ONE)
	c.draw_rect(Rect2(-6.5, -18.5, 13, 37), dark)
	c.draw_rect(Rect2(-5, -17, 10, 34), Color(0.50, 0.75, 0.27))
	c.draw_rect(Rect2(-3.5, -17, 2.5, 34), Color(0.80, 0.93, 0.50))
	c.draw_rect(Rect2(-7, -6.5, 14, 3), dark)
	c.draw_rect(Rect2(-7, 4.5, 14, 3), dark)
	c.draw_colored_polygon(PackedVector2Array([Vector2(5, -6), Vector2(16, -14), Vector2(8, -2)]), Color(0.36, 0.68, 0.22))
