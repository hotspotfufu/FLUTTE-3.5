extends Node
## Turns on Flutte's controls, the bamboo pickups and the bamboo counter.
##
## Set up WITHOUT opening Godot: add this line under [autoload] in project.godot
##     FlutteGameplay="*res://Scripts/flutte_gameplay_setup.gd"
## Then whenever a level scene loads (any scene whose file name contains "Level"),
## this script:
##   1. spawns a playable Flutte (unless one is already in the level)
##   2. adds the bamboo counter
##   3. floats bamboo sticks above the platforms it finds
##      (skipped if the level already has bamboo placed by hand)
##
## Keep all five Flutte scripts together in the same folder.
## Spawn point: a Marker2D named "PlayerSpawn" in the level, otherwise the left-most platform.

@export var level_name_contains := "level"
@export var spawn_player := true
@export var add_hud := true
@export var auto_place_bamboo := true
@export var bamboo_height_above_platform := 70.0
@export var ground_group_spacing := 520.0

const SHAPE_LINE := 0
const SHAPE_ARC := 1

var _dir := ""
var _last_scene: Node = null
var _is_autoload := false


func _ready() -> void:
	_dir = get_script().resource_path.get_base_dir()
	_is_autoload = get_parent() == get_tree().root
	if not _is_autoload:
		# placed directly inside a level scene
		await get_tree().process_frame
		await get_tree().process_frame
		_setup(get_parent())


func _process(_delta: float) -> void:
	if not _is_autoload:
		return
	var scene := get_tree().current_scene
	if scene == _last_scene or scene == null:
		return
	_last_scene = scene
	if scene.scene_file_path.get_file().to_lower().contains(level_name_contains):
		_run_when_ready(scene)


func _run_when_ready(scene: Node) -> void:
	# give bamboo_forest_builder.gd time to build the platforms
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scene) and scene == get_tree().current_scene:
		_setup(scene)


func _new(file: String) -> Object:
	return load(_dir + "/" + file).new()


func _setup(level: Node) -> void:
	var rects := _platform_rects(level)

	# --- where does Flutte start? ---
	var spawn := Vector2(200, 0)
	var marker := level.find_child("PlayerSpawn", true, false)
	if marker is Node2D:
		spawn = (marker as Node2D).global_position
	elif rects.size() > 0:
		var left: Rect2 = rects[0]
		for r in rects:
			if r.position.x < left.position.x:
				left = r
		spawn = Vector2(left.position.x + minf(90.0, left.size.x * 0.5), left.position.y - 2.0)

	var lowest := spawn.y
	for r in rects:
		lowest = maxf(lowest, r.end.y)

	# --- player ---
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null and spawn_player:
		var p: CharacterBody2D = _new("flutte_player.gd")
		p.name = "Flutte"
		level.add_child(p)
		p.global_position = spawn
		p.set("spawn_point", spawn)
		player = p
	if player:
		player.set("kill_y", lowest + 1200.0)

	# --- HUD ---
	if add_hud and get_tree().get_nodes_in_group("bamboo_hud").is_empty():
		var hud: CanvasLayer = _new("bamboo_hud.gd")
		hud.name = "BambooHUD"
		level.add_child(hud)

	# --- bamboo ---
	if auto_place_bamboo and get_tree().get_nodes_in_group("bamboo").is_empty():
		_scatter_bamboo(level, rects, spawn)


func _make_trail(holder: Node, shape: int, count: int, spacing: float, arc: float, pos: Vector2) -> void:
	var t: Node2D = _new("bamboo_trail.gd")
	t.set("count", count)
	t.set("spacing", spacing)
	t.set("shape", shape)
	t.set("arc_height", arc)
	holder.add_child(t)
	t.global_position = pos


func _scatter_bamboo(level: Node, rects: Array[Rect2], spawn: Vector2) -> void:
	var holder := Node2D.new()
	holder.name = "AutoBamboo"
	level.add_child(holder)
	var idx := 0
	for r in rects:
		if r.size.x < 50.0:
			continue
		var top := r.position.y - bamboo_height_above_platform
		if r.size.x <= 700.0:
			var n := clampi(int(r.size.x / 70.0), 1, 6)
			var shape := SHAPE_ARC if idx % 3 == 2 else SHAPE_LINE
			_make_trail(holder, shape, n, minf(55.0, r.size.x / float(n)), 55.0, Vector2(r.get_center().x, top))
		else:
			# long ground: a little arc of bamboo every ground_group_spacing pixels
			var x := r.position.x + 300.0
			while x < r.end.x - 200.0:
				if absf(x - spawn.x) > 150.0:
					_make_trail(holder, SHAPE_ARC, 5, 48.0, 60.0, Vector2(x, top))
				x += ground_group_spacing
		idx += 1


## World-space rectangles of every solid collision shape in the level.
func _platform_rects(root: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	_collect(root, out)
	return out


func _collect(node: Node, out: Array[Rect2]) -> void:
	for c in node.get_children():
		if c is PhysicsBody2D and not (c is CharacterBody2D):
			for s in c.get_children():
				if s is CollisionShape2D and s.shape and not s.disabled:
					var r: Rect2 = s.global_transform * s.shape.get_rect()
					if r.size.x < 100000.0 and r.size.y < 100000.0:
						out.append(r)
				elif s is CollisionPolygon2D and s.polygon.size() > 0:
					var pr := Rect2(s.polygon[0], Vector2.ZERO)
					for pt in s.polygon:
						pr = pr.expand(pt)
					out.append(s.global_transform * pr)
		_collect(c, out)
