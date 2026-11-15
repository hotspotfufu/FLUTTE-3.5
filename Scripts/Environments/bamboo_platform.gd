extends StaticBody3D
## Solid wooden platform with a green bamboo trim.
## Set `width` per instance in the level; the mesh and collision resize on load.
## Each instance gets its own collision shape, so instances never share sizes.

@export var width: float = 3.0
@export var thickness: float = 0.4
@export var depth: float = 1.6

@onready var _plank: MeshInstance3D = $Plank
@onready var _trim: MeshInstance3D = $Trim
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply_size()


func _apply_size() -> void:
	_plank.scale = Vector3(width, thickness, depth)
	_trim.scale = Vector3(width + 0.08, 0.08, depth + 0.04)
	_trim.position = Vector3(0.0, thickness * 0.5 - 0.02, 0.0)
	var box := BoxShape3D.new()
	box.size = Vector3(width, thickness, depth)
	_collision.shape = box
