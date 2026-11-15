extends Node
## Blends the level between daytime and nighttime.
## Press N (or double-tap the screen) to toggle during the Stage 1 preview.
## Other systems can call set_night(true/false) later (e.g. a night level).

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var scenery: Node
@export var transition_time: float = 2.0
@export var start_at_night: bool = false

@export var day_sun_color: Color = Color(1.0, 0.93, 0.84)
@export var night_sun_color: Color = Color(0.55, 0.62, 1.0)
@export var day_sun_energy: float = 1.15
@export var night_sun_energy: float = 0.3
@export var day_ambient_color: Color = Color(1.0, 0.86, 0.90)
@export var night_ambient_color: Color = Color(0.35, 0.33, 0.62)
@export var day_ambient_energy: float = 0.75
@export var night_ambient_energy: float = 0.45

var _night_amount: float = 0.0
var _is_night: bool = false
var _tween: Tween


func _ready() -> void:
	_is_night = start_at_night
	_apply(1.0 if start_at_night else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_N:
			set_night(not _is_night)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and touch.double_tap:
			set_night(not _is_night)


func set_night(night: bool) -> void:
	_is_night = night
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply, _night_amount, 1.0 if night else 0.0, transition_time)


func _apply(t: float) -> void:
	_night_amount = t
	if sun != null:
		sun.light_color = day_sun_color.lerp(night_sun_color, t)
		sun.light_energy = lerpf(day_sun_energy, night_sun_energy, t)
	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		env.ambient_light_color = day_ambient_color.lerp(night_ambient_color, t)
		env.ambient_light_energy = lerpf(day_ambient_energy, night_ambient_energy, t)
	if scenery != null and scenery.has_method("set_night_amount"):
		scenery.call("set_night_amount", t)
