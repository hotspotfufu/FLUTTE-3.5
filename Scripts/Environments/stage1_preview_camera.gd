extends Camera3D
## STAGE 1 ONLY: lets you pan along the level to review the environment.
## Left/Right arrows or A/D (or a gamepad d-pad) move the camera.
## On touch screens (and with the mouse, via touch emulation) drag to pan.
## In Stage 2 this is replaced by a camera that follows the panda.

@export var pan_speed: float = 9.0
@export var min_x: float = 0.0
@export var max_x: float = 100.0


func _process(delta: float) -> void:
	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	dir = clampf(dir, -1.0, 1.0)
	if dir != 0.0:
		position.x = clampf(position.x + dir * pan_speed * delta, min_x, max_x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var view_height := get_viewport().get_visible_rect().size.y
		if view_height > 0.0:
			# Orthographic `size` is the visible height in world units,
			# so this keeps the ground moving exactly under the finger.
			var world_per_pixel := size / view_height
			position.x = clampf(position.x - drag.relative.x * world_per_pixel, min_x, max_x)
