extends CanvasLayer
## Bamboo counter shown in the top-right corner.

var _label: Label
var _box: HBoxContainer


func _ready() -> void:
	layer = 20
	add_to_group("bamboo_hud")
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.position = Vector2(-230, 22)
	add_child(anchor)

	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	anchor.add_child(_box)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(34, 46)
	icon.draw.connect(func(): _draw_icon(icon))
	_box.add_child(icon)

	_label = Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 38
	ls.font_color = Color(1, 1, 1)
	ls.outline_size = 10
	ls.outline_color = Color(0.45, 0.12, 0.2)
	_label.label_settings = ls
	_label.text = "x 0"
	_box.add_child(_label)
	_connect_player.call_deferred()


func _connect_player() -> void:
	for i in 10:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_signal("bamboo_changed"):
			p.connect("bamboo_changed", _on_bamboo_changed)
			return
		await get_tree().process_frame


func _on_bamboo_changed(total: int) -> void:
	_label.text = "x %d" % total
	_box.pivot_offset = Vector2(40, 23)
	_box.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(_box, "scale", Vector2.ONE, 0.18)


func _draw_icon(c: Control) -> void:
	var dark := Color(0.22, 0.38, 0.10)
	c.draw_set_transform(Vector2(17, 23), deg_to_rad(20.0), Vector2.ONE)
	c.draw_rect(Rect2(-7.5, -21.5, 15, 43), dark)
	c.draw_rect(Rect2(-5.5, -19.5, 11, 39), Color(0.55, 0.78, 0.26))
	c.draw_rect(Rect2(-3.5, -19.5, 3, 39), Color(0.82, 0.94, 0.5))
	c.draw_rect(Rect2(-7.5, -7.5, 15, 3.5), dark)
	c.draw_rect(Rect2(-7.5, 5.5, 15, 3.5), dark)
	c.draw_colored_polygon(PackedVector2Array([Vector2(5, -7), Vector2(18, -16), Vector2(9, -2)]), Color(0.36, 0.68, 0.22))
