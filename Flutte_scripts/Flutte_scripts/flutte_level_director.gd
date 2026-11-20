extends CanvasLayer
## Runs the bamboo forest's battles:
##   * places 15 ninja opponents and the breakable lanterns
##   * shows "NINJAS LEFT" at the top of the screen
##     (some patrol, some stand guard and block, some ambush from the bamboo)
##   * lights the checkpoints Flutte passes; a knock-out sends him back to the last one
##   * at the end of the path is the boss arena: walk in and CLAUS THE BEAR
##     drops down, with his own health bar; the camera holds on the arena
##   * beat Claus: "STAGE CLEAR!" and Flutte's victory hops

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

## the boss waits in his own arena at the far end of the path
const ARENA_X0 := 108.0
const ARENA_X1 := 127.0
const CHECK_X := [33.0, 73.0]
const AMBUSH_SPOTS := [2, 5, 8]      # which ground ninjas drop from the bamboo
const GUARD_SPOTS := [3, 6, 9]       # which ones stand guard and block a lot
var _checks: Array = []
var _check_on: Array = []
var _hop_t := -1.0


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
		if i in AMBUSH_SPOTS:
			n.set("role", "ambush")
			spots[i] = spots[i] + Vector3(0, 8.5, 0)
		elif i in GUARD_SPOTS:
			n.set("role", "guard")
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
	for cx in CHECK_X:
		_checks.append(_make_checkpoint(cx))
		_check_on.append(false)
	_make_arena_gate(ARENA_X0 - 1.2)
	_make_arena_gate(ARENA_X1 + 0.6)
	_update_counter()
	_show_banner("THE BAMBOO FOREST", "Fight through the ninjas - Claus the Bear waits at the end!", 3.5)


func on_enemy_defeated(_enemy: Node) -> void:
	if _enemy.is_in_group("boss"):
		return
	defeated_count += 1
	_update_counter()
	if defeated_count >= NINJA_COUNT and not _boss_started:
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("heal"):
			p.call("heal", 999)
		_show_banner("ALL 15 NINJAS DEFEATED!", "Full health! Now find Claus at the end of the path", 3.0)


func _start_boss() -> void:
	# lock Flutte into the arena, hold the camera on it and pull back a little
	var p := get_tree().get_first_node_in_group("player") as Node3D
	for wx in [ARENA_X0 - 1.0, ARENA_X1 + 0.4]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 30.0, 4.0)
		cs.shape = box
		wall.add_child(cs)
		level.add_child(wall)
		wall.global_position = Vector3(wx, 14.0, 0)
	if p:
		p.set("min_x", ARENA_X0 - 0.2)
		p.set("max_x", ARENA_X1 - 0.4)
		p.set("spawn_point", Vector3(ARENA_X0 + 1.5, 0.2, 0))
		p.set("cam_lock", true)
		p.set("cam_lock_x", (ARENA_X0 + ARENA_X1) * 0.5)
		p.set("cam_zoom", 4.5)
	_show_banner("CLAUS THE BEAR!", "Jump over his shockwaves!", 3.0)
	var x := ARENA_X1 - 5.0
	await get_tree().create_timer(1.6).timeout
	boss = load(_dir + "/boss_bear.gd").new()
	boss.name = "ClausTheBear"
	level.add_child(boss)
	(boss as Node3D).global_position = Vector3(x, 7.0, 0)
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
	_hop_t = 0.0                       # Flutte's victory hops
	await get_tree().create_timer(3.0).timeout
	_boss_bar.visible = false


func on_player_ko() -> void:
	_show_banner("KNOCKED OUT!", "Back to the last checkpoint", 1.8)


## a bamboo post with a paper lamp that lights up when Flutte passes it
func _make_checkpoint(x: float) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.09
	pm.height = 2.6
	post.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.72, 0.3)
	post.material_override = m
	level.add_child(post)
	post.global_position = Vector3(x, 1.3, -0.9)
	var flag := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.7, 0.5, 0.03)
	fm.left_to_right = 0.0
	flag.mesh = fm
	var f := StandardMaterial3D.new()
	f.albedo_color = Color(0.9, 0.15, 0.2)
	f.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = f
	flag.rotation.z = -PI * 0.5
	flag.position = Vector3(0.32, 0.9, 0)
	post.add_child(flag)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.2
	lm.height = 0.46
	lamp.mesh = lm
	var l := StandardMaterial3D.new()
	l.albedo_color = Color(0.75, 0.72, 0.68)
	l.emission_enabled = true
	l.emission = Color(1.0, 0.7, 0.3)
	l.emission_energy_multiplier = 0.0
	lamp.material_override = l
	lamp.position = Vector3(0, 1.5, 0)
	post.add_child(lamp)
	return lamp


## two tall stone pillars mark each end of the boss arena
func _make_arena_gate(x: float) -> void:
	for z in [-1.9, 1.9]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.32
		cm.bottom_radius = 0.42
		cm.height = 4.2
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.56, 0.52, 0.6)
		m.roughness = 0.9
		mi.material_override = m
		level.add_child(mi)
		mi.global_position = Vector3(x, 2.1, z)
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.36
		sm.height = 0.72
		cap.mesh = sm
		var c := StandardMaterial3D.new()
		c.albedo_color = Color(0.85, 0.2, 0.25)
		c.emission_enabled = true
		c.emission = Color(1.0, 0.35, 0.3)
		c.emission_energy_multiplier = 0.8
		cap.material_override = c
		cap.position = Vector3(0, 2.3, 0)
		mi.add_child(cap)


func _level_tick(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p == null or level == null:
		return
	for i in _checks.size():
		if not _check_on[i] and p.global_position.x > CHECK_X[i]:
			_check_on[i] = true
			p.set("spawn_point", Vector3(CHECK_X[i], 0.2, 0))
			var mat := (_checks[i] as MeshInstance3D).material_override as StandardMaterial3D
			mat.albedo_color = Color(1.0, 0.8, 0.5)
			mat.emission_energy_multiplier = 3.0
			_show_banner("CHECKPOINT!", "", 1.2)
	if not _boss_started and p.global_position.x > ARENA_X0 and p.is_on_floor():
		_boss_started = true
		_start_boss.call_deferred()
	if _hop_t >= 0.0:
		_hop_t += delta
		if _hop_t < 4.0 and p.is_on_floor() and fmod(_hop_t, 0.7) < 0.1:
			p.velocity.y = 7.5


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
	at.region = Rect2(0, 0, 255, 146)
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
	_level_tick(delta)
	if _boss_bar.visible:
		var target := float(boss_hp) / float(maxi(boss_max, 1))
		_boss_shown = lerpf(_boss_shown, target, minf(1.0, delta * 8.0))
		_boss_lag = move_toward(_boss_lag, target, delta * (0.3 if _boss_lag > target else 3.0))
		_boss_bar.queue_redraw()


func _draw_boss_bar() -> void:
	var c := _boss_bar
	var font := ThemeDB.fallback_font
	var title := "CLAUS THE BEAR"
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
