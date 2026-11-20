extends Node
## Turns the Stage 1 bamboo forest into a playable level.
## Runs automatically (it is an autoload in project.godot) whenever a scene whose
## file name contains "Level" starts. It:
##   1. swaps the still panda picture (PandaScaleReference) for a playable Flutte
##   2. makes the camera follow Flutte instead of panning with A/D
##   3. floats bamboo sticks along the ground and above every platform
##   4. adds the bamboo counter and updates the on-screen controls hint

const HINT := "A/D or Arrows: walk   Shift: run   Space: jump   J or F: swing staff   N: day / night"

var _dir := ""
var _last_scene: Node = null
var _title_shown := false


func _ready() -> void:
	_dir = get_script().resource_path.get_base_dir()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene == _last_scene:
		return
	_last_scene = scene
	if scene.scene_file_path.get_file().to_lower().contains("level"):
		_setup.call_deferred(scene)


func _setup(level: Node) -> void:
	if not is_instance_valid(level) or not (level is Node3D):
		return
	if get_tree().get_first_node_in_group("player") != null:
		return

	# --- Flutte ---
	var spawn := Vector3(4, 0.2, 0)
	var ref := level.get_node_or_null("PandaScaleReference")
	if ref is Node3D:
		spawn = Vector3((ref as Node3D).global_position.x, 0.2, 0)
		ref.queue_free()
	var player: CharacterBody3D = load(_dir + "/flutte_player.gd").new()
	player.name = "Flutte"
	level.add_child(player)
	player.global_position = spawn
	player.set("spawn_point", spawn)

	player.set("max_x", 126.4)          # the path now runs on to the boss arena

	# --- title screen (once, when the game opens) ---
	if not _title_shown:
		_title_shown = true
		add_child(load(_dir + "/flutte_title.gd").new())

	# --- hint text ---
	var hint := level.get_node_or_null("HUD/Hint")
	if hint is Label:
		(hint as Label).text = "BAMBOO FOREST\n" + HINT

	# --- bamboo counter ---
	var hud: CanvasLayer = load(_dir + "/bamboo_hud.gd").new()
	level.add_child(hud)

	# --- ninjas, lanterns, boss fight ---
	var director: CanvasLayer = load(_dir + "/flutte_level_director.gd").new()
	director.set("level", level)
	level.add_child(director)

	# --- joystick, buttons, show/hide help, day/night button ---
	var touch: CanvasLayer = load(_dir + "/flutte_touch_controls.gd").new()
	touch.set("level", level)
	level.add_child(touch)

	# --- bamboo sticks ---
	if get_tree().get_nodes_in_group("bamboo").is_empty():
		_place_bamboo(level, spawn.x)


func _place_bamboo(level: Node, spawn_x: float) -> void:
	var holder := Node3D.new()
	holder.name = "Bamboo"
	level.add_child(holder)
	var trail_script: Script = load(_dir + "/bamboo_trail.gd")

	# above each platform
	var platform_xs: Array[float] = []
	var platforms := level.get_node_or_null("Platforms")
	if platforms:
		var i := 0
		for p in platforms.get_children():
			if not (p is Node3D):
				continue
			p.add_to_group("one_way_platform")
			var w := 3.0
			if "width" in p:
				w = float(p.get("width"))
			var top := (p as Node3D).global_position.y + 0.2
			var t: Node3D = trail_script.new()
			t.set("count", clampi(int(w * 1.3), 2, 6))
			t.set("spacing", 0.55)
			t.set("shape", 1 if i % 3 == 2 else 0)
			t.set("arc_height", 0.7)
			holder.add_child(t)
			t.global_position = Vector3((p as Node3D).global_position.x, top + 0.75, 0)
			platform_xs.append((p as Node3D).global_position.x)
			i += 1

	# along the ground: arcs to jump through, plain rows under the platforms
	var x := spawn_x + 4.0
	var n := 0
	while x < 100.0:
		var near_platform := false
		for px in platform_xs:
			if absf(px - x) < 2.8:
				near_platform = true
		var g: Node3D = trail_script.new()
		g.set("count", 4 if near_platform else 5)
		g.set("spacing", 0.6)
		g.set("shape", 0 if near_platform else 1)
		g.set("arc_height", 1.3)
		holder.add_child(g)
		g.global_position = Vector3(x, 0.8, 0)
		n += 1
		x += 6.5
