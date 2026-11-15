extends Node3D
## Places a row, arc or wave of bamboo sticks (3D).
## Add a Node3D to the level, attach this script, set Shape / Count / Spacing.

enum Shape { LINE, ARC, WAVE }

@export var shape: Shape = Shape.LINE
@export_range(1, 30) var count := 5
@export var spacing := 0.6
@export var arc_height := 1.0


func _ready() -> void:
	var stick_script: Script = load(get_script().resource_path.get_base_dir() + "/bamboo_stick.gd")
	for i in count:
		var s: Node3D = stick_script.new()
		s.position = _point(i)
		add_child(s)


func _point(i: int) -> Vector3:
	var u := 0.0 if count <= 1 else float(i) / float(count - 1)
	var x := (float(i) - float(count - 1) * 0.5) * spacing
	match shape:
		Shape.ARC:
			return Vector3(x, sin(u * PI) * arc_height, 0)
		Shape.WAVE:
			return Vector3(x, sin(u * TAU) * arc_height * 0.5, 0)
	return Vector3(x, 0, 0)
