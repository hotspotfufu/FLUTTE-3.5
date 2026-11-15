@tool
extends Area2D
## A floating bamboo stick Flutte can collect (like rings in Sonic).
## Bobs and spins in place; touch it or whack it with the staff to collect.
## Drawn in code, so no image is needed.

signal collected(stick: Area2D)

@export var value := 1
@export var stick_length := 34.0:
	set(v):
		stick_length = v
		queue_redraw()
@export var bob_height := 6.0
@export var bob_speed := 2.6
@export var spin_speed := 3.2

var _t := 0.0
var _collected := false

static var _chime: AudioStreamWAV


func _ready() -> void:
	_t = randf() * TAU   # so a row of sticks doesn't move in perfect lockstep
	add_to_group("bamboo")
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var c := CircleShape2D.new()
		c.radius = stick_length * 0.6
		col.shape = c
		add_child(col)
	if not Engine.is_editor_hint():
		collision_layer = 1
		collision_mask = 0xFF
		monitoring = true
		monitorable = true
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.has_method("add_bamboo"):
		collect(body)


func on_staff_hit(by: Node) -> void:
	collect(by)


func collect(by: Node) -> void:
	if _collected:
		return
	_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if by and by.has_method("add_bamboo"):
		by.call("add_bamboo", value)
	collected.emit(self)
	_play_chime()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 46.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.7, 1.7), 0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(_t * bob_speed) * bob_height
	var spin := 0.25 + 0.75 * absf(cos(_t * spin_speed))
	var h := stick_length
	var w := h * 0.24

	# soft glow
	draw_circle(Vector2(0, bob), h * 0.62, Color(1.0, 0.95, 0.5, 0.16))
	draw_circle(Vector2(0, bob), h * 0.42, Color(1.0, 0.97, 0.7, 0.14))

	draw_set_transform(Vector2(0, bob), deg_to_rad(18.0), Vector2(spin, 1.0))
	var dark := Color(0.24, 0.42, 0.12)
	draw_rect(Rect2(-w * 0.5 - 1.5, -h * 0.5 - 1.5, w + 3.0, h + 3.0), dark)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(0.50, 0.75, 0.27))
	draw_rect(Rect2(-w * 0.32, -h * 0.5, w * 0.22, h), Color(0.80, 0.93, 0.50))
	for y in [-h / 6.0, h / 6.0]:
		draw_rect(Rect2(-w * 0.5 - 2.0, y - 1.5, w + 4.0, 3.0), dark)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.5, -h * 0.16),
		Vector2(w * 0.5 + h * 0.42, -h * 0.40),
		Vector2(w * 0.5 + h * 0.12, -h * 0.08),
	]), Color(0.36, 0.68, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# little sparkle
	var sp := (sin(_t * 5.0) + 1.0) * 0.5
	var c := Vector2(h * 0.3, -h * 0.45 + bob)
	var col := Color(1, 1, 1, 0.8 * sp)
	draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), col, 2.0)
	draw_line(c + Vector2(0, -4), c + Vector2(0, 4), col, 2.0)


func _play_chime() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	var p := AudioStreamPlayer.new()
	p.stream = _get_chime()
	p.volume_db = -8.0
	p.pitch_scale = randf_range(0.98, 1.06)
	root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _get_chime() -> AudioStreamWAV:
	if _chime:
		return _chime
	var rate := 22050
	var n := int(rate * 0.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := 1318.5 if t < 0.065 else 1975.5   # two-note "ding"
		phase += TAU * f / float(rate)
		var env := exp(-t * 8.0) * minf(1.0, t * 400.0)
		var s := sin(phase) * 0.4 + sin(phase * 2.0) * 0.1
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 32767.0))
	_chime = AudioStreamWAV.new()
	_chime.format = AudioStreamWAV.FORMAT_16_BITS
	_chime.mix_rate = rate
	_chime.data = data
	return _chime
