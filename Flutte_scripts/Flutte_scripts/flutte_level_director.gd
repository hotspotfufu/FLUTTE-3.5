extends CanvasLayer
## Runs the bamboo forest's battles:
##   * places 15 ninja opponents and the breakable lanterns
##   * shows "NINJAS LEFT" at the top of the screen
##   * when all 15 are defeated: "THE SHADOW BEAR AWAKENS!" and the boss
##     drops in, with his own health bar at the top of the screen
##   * beat the bear: "STAGE CLEAR!"

const NINJA_COUNT := 15
# x positions for ninjas on the ground; the rest stand on platforms
const GROUND_X := [13.0, 19.0, 27.0, 37.0, 48.0, 56.0, 68.0, 79.0, 87.0, 95.0]
const PLATFORM_NINJAS := ["Platform03", "Platform04", "Platform05", "Platform07", "Platform08"]
const LANTERN_X := [7.0, 17.5, 25.0, 29.0, 36.0, 41.0, 53.5, 57.5, 66.5, 71.0, 85.0, 90.0]

var level: Node3D
var defeated_count := 0
var boss: Node = null
var boss_hp := 0
var boss_max := 1
var _boss_shown := 0.0
var _boss_lag := 1.0
var _dir := ""

var _counter: Label
var _ninja_icon: TextureRect
var _top: HBoxContainer
var _banner: Label
var _sub: Label
var _boss_bar: Control
var _boss_started := false
var _cleared := false


func _ready() -> void:
	layer = 22
	add_to_group("flutte_director")
	_dir = get_script().resource_path.get_base_dir()
	_build_ui()
	_spawn_all.call_deferred()


func _spawn_all() -> void:
	if level == null:
		level = get_tree().current_scene as Node3D
	var holder := Node3D.new()
	holder.name = "Opponents"
	level.add_child(holder)
	var ninja: Script = load(_dir + "/enemy_ninja.gd")
	var platforms := level.get_node_or_null("Platforms")
	var spots: Array = []
	for x in GROUND_X:
		spots.append(Vector3(x, 0.3, 0))
	if platforms:
		for pname in PLATFORM_NINJAS:
			var p := platforms.get_node_or_null(pname) as Node3D
			if p:
				spots.append(p.global_position + Vector3(0, 0.6, 0))
	while spots.size() < NINJA_COUNT:
		spots.append(Vector3(30.0 + spots.size() * 4.0, 0.3, 0))
	for i in NINJA_COUNT:
		var n: CharacterBody3D = ninja.new()
		n.name = "Ninja%02d" % (i + 1)
		holder.add_child(n)
		n.global_position = spots[i]
		n.set("home", spots[i])
		if spots[i].y > 0.5:
			n.set("patrol_range", 1.0)

	var lantern: Script = load(_dir + "/breakable_lantern.gd")
	var li := 0
	for x in LANTERN_X:
		var l: Area3D = lantern.new()
		l.set("drops_cannon", li % 3 == 1)        # every third lantern has a firework cannon
		l.set("yellow_sticks", 2 if li % 2 == 0 else 3)
		holder.add_child(l)
		l.global_position = Vector3(x, 1.75, 0)
		li += 1
	# two high lanterns above the tall platforms
	if platforms:
		for pname in ["Platform06", "Platform09"]:
			var p := platforms.get_node_or_null(pname) as Node3D
			if p:
				var l: Area3D = lantern.new()
				l.set("drops_cannon", true)
				l.set("yellow_sticks", 3)
				holder.add_child(l)
				l.global_position = p.global_position + Vector3(0, 1.55, 0)
	_update_counter()
	_show_banner("DEFEAT THE 15 NINJAS!", "Smash lanterns for health and fireworks", 3.0)


func on_enemy_defeated(_enemy: Node) -> void:
	if _enemy.is_in_group("boss"):
		return
	defeated_count += 1
	_update_counter()
	if defeated_count >= NINJA_COUNT and not _boss_started:
		_boss_started = true
		_start_boss.call_deferred()


func _start_boss() -> void:
	await get_tree().create_timer(1.2).timeout
	_show_banner("THE SHADOW BEAR AWAKENS!", "Jump over his shockwaves!", 3.0)
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var x := 50.0
	var f := 1
	if p:
		f = int(p.get("facing"))
		x = p.global_position.x + f * 8.0
		if x > 98.0 or x < 2.0:
			x = p.global_position.x - f * 8.0
	await get_tree().create_timer(1.0).timeout
	boss = load(_dir + "/boss_bear.gd").new()
	boss.name = "ShadowBear"
	level.add_child(boss)
	(boss as Node3D).global_position = Vector3(clampf(x, 2.0, 98.0), 7.0, 0)
	_top.visible = false
	_boss_bar.visible = true


func on_boss_health(hp: int, max_hp: int) -> void:
	boss_hp = hp
	boss_max = max_hp


func on_boss_defeated(_b: Node) -> void:
	if _cleared:
		return
	_cleared = true
	boss_hp = 0
	await get_tree().create_timer(1.5).timeout
	_show_banner("STAGE CLEAR!", "The bamboo forest is safe again", 6.0)
	await get_tree().create_timer(3.0).timeout
	_boss_bar.visible = false


# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 10)
	_top.position = Vector2(-150, 14)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_top)
	_ninja_icon = TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load(_dir + "/enemy_ninja.png")
	at.region = Rect2(0, 0, 252, 138)
	_ninja_icon.texture = at
	_ninja_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ninja_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ninja_icon.custom_minimum_size = Vector2(110, 62)
	_top.add_child(_ninja_icon)
	_counter = Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 34
	ls.outline_size = 10
	ls.outline_color = Color(0.35, 0.05, 0.08)
	_counter.label_settings = ls
	_top.add_child(_counter)

	_banner = Label.new()
	var bs := LabelSettings.new()
	bs.font_size = 78
	bs.font_color = Color(1.0, 0.92, 0.6)
	bs.outline_size = 22
	bs.outline_color = Color(0.45, 0.05, 0.1)
	_banner.label_settings = bs
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -900
	_banner.offset_right = 900
	_banner.offset_top = -170
	_banner.offset_bottom = -70
	_banner.visible = false
	add_child(_banner)
	_sub = Label.new()
	var ss := LabelSettings.new()
	ss.font_size = 34
	ss.outline_size = 10
	ss.outline_color = Color(0.3, 0.05, 0.1)
	_sub.label_settings = ss
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.offset_left = -900
	_sub.offset_right = 900
	_sub.offset_top = -64
	_sub.offset_bottom = -20
	_sub.visible = false
	add_child(_sub)

	_boss_bar = Control.new()
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.position = Vector2(-430, 16)
	_boss_bar.size = Vector2(860, 100)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.draw.connect(_draw_boss_bar)
	_boss_bar.visible = false
	add_child(_boss_bar)


func _update_counter() -> void:
	var left := maxi(0, NINJA_COUNT - defeated_count)
	_counter.text = "NINJAS LEFT: %d / %d" % [left, NINJA_COUNT]
	_top.pivot_offset = Vector2(150, 30)
	_top.scale = Vector2(1.2, 1.2)
	create_tween().tween_property(_top, "scale", Vector2.ONE, 0.2)


func _show_banner(title: String, sub: String, secs: float) -> void:
	_banner.text = title
	_sub.text = sub
	_banner.visible = true
	_sub.visible = true
	_banner.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_banner.pivot_offset = Vector2(900, 50)
	_banner.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(secs)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(_sub, "modulate:a", 0.0, 0.5)


func _process(delta: float) -> void:
	if _boss_bar.visible:
		var target := float(boss_hp) / float(maxi(boss_max, 1))
		_boss_shown = lerpf(_boss_shown, target, minf(1.0, delta * 8.0))
		_boss_lag = move_toward(_boss_lag, target, delta * (0.3 if _boss_lag > target else 3.0))
		_boss_bar.queue_redraw()


func _draw_boss_bar() -> void:
	var c := _boss_bar
	var font := ThemeDB.fallback_font
	var title := "SHADOW BEAR"
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	c.draw_string_outline(font, Vector2(430 - w * 0.5, 34), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 10, Color(0.15, 0.0, 0.2))
	c.draw_string(font, Vector2(430 - w * 0.5, 34), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.95, 0.8, 1.0))
	var bar := Rect2(30, 48, 800, 34)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.1, 0.02, 0.12, 0.85)
	frame.set_corner_radius_all(17)
	frame.border_color = Color(0.85, 0.6, 1.0)
	frame.set_border_width_all(4)
	c.draw_style_box(frame, bar.grow(5))
	var inner := bar.grow(-2)
	if _boss_lag > _boss_shown:
		var lag := StyleBoxFlat.new()
		lag.bg_color = Color(1, 1, 1, 0.8)
		lag.set_corner_radius_all(15)
		c.draw_style_box(lag, Rect2(inner.position, Vector2(inner.size.x * _boss_lag, inner.size.y)))
	if _boss_shown > 0.003:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.7, 0.15, 0.95).lerp(Color(0.95, 0.1, 0.25), 1.0 - _boss_shown)
		fill.set_corner_radius_all(15)
		c.draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.y, inner.size.x * _boss_shown), inner.size.y)))
		c.draw_rect(Rect2(inner.position + Vector2(14, 5), Vector2(maxf(0.0, inner.size.x * _boss_shown - 28.0), 6)), Color(1, 1, 1, 0.3))
