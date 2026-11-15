@tool
extends Node2D
## Places a row / arc / wave / circle of BambooStick pickups.
## Add a Node2D, attach this script, drag it where you want it in the level and
## change Shape / Count / Spacing in the Inspector - you'll see it live in the editor.

enum Shape { LINE, ARC, WAVE, CIRCLE }

@export var shape: Shape = Shape.LINE:
	set(v):
		shape = v
		_rebuild()
@export_range(1, 60) var count := 5:
	set(v):
		count = v
		_rebuild()
@export var spacing := 50.0:
	set(v):
		spacing = v
		_rebuild()
@export var arc_height := 70.0:
	set(v):
		arc_height = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("bamboo_generated"):
			remove_child(c)
			c.queue_free()
	for i in count:
		var s: Area2D = load(get_script().resource_path.get_base_dir() + "/bamboo_stick.gd").new()
		s.set_meta("bamboo_generated", true)
		s.position = _point(i)
		add_child(s)


func _point(i: int) -> Vector2:
	var u := 0.0 if count <= 1 else float(i) / float(count - 1)
	var x := (float(i) - float(count - 1) * 0.5) * spacing
	match shape:
		Shape.ARC:
			return Vector2(x, -sin(u * PI) * arc_height)
		Shape.WAVE:
			return Vector2(x, -sin(u * TAU) * arc_height * 0.5)
		Shape.CIRCLE:
			var a := TAU * float(i) / float(count)
			var r: float = maxf(arc_height, spacing * float(count) / TAU)
			return Vector2(cos(a), sin(a)) * r
	return Vector2(x, 0.0)
