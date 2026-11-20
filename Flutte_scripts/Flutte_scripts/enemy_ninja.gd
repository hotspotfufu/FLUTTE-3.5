extends "flutte_enemy_base.gd"
## Forest Ninja. Patrols, spots Flutte ("!"), walks up to him and slashes.
## He can BLOCK the staff with his sword (tail spin, energy ball and fireworks
## always get through) and sometimes hops back after a slash.
## Three kinds (set `role` before adding to the level):
##   "patrol" - walks back and forth          "guard"  - holds his spot, blocks a lot
##   "ambush" - hides up in the bamboo and drops down when Flutte walks under him
## Ninjas are solid: Flutte can't walk through them, only beat them or jump over.
## Defeated by 2 hits from the staff or tail spin, or 1 hit from the energy ball
## or a firework rocket. No health bar.

enum S { PATROL, ALERT, CHASE, ATTACK, HURT, DEFEAT, BLOCK, HOP }

@export var patrol_range := 2.5
@export var walk_speed := 1.4
@export var chase_speed := 2.3
@export var sight := 7.5
@export var attack_range := 1.35
@export var damage := 10
@export var role := "patrol"
@export var block_chance := 0.3

var home := Vector3.ZERO
var _s := S.PATROL
var _t := 0.0
var _cooldown := 0.0
var _hit_done := false
var _alert: Label3D
var _slash: MeshInstance3D
var _waiting := false
var _blocks_left := 2


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4      # "Enemies"
	collision_mask = 1 | 2   # "World" + "Player" (solid: they block Flutte)
	hp = 2
	home = global_position
	facing = -1 if randf() < 0.5 else 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.3
	col.shape = cap
	col.position = Vector3(0, 0.65, 0)
	add_child(col)
	setup_sprite("enemy_ninja.png", Vector2i(255, 146), 8, 1.6, 129.0)
	add_anim("idle", [0, 1, 2], 5.0)
	add_anim("walk", [3, 4, 5, 6, 7], 10.0)
	add_anim("run", [8, 9, 10, 11], 12.0)
	add_anim("attack", [12, 13, 14, 15, 16, 17], 11.0, false)
	add_anim("hurt", [18, 19, 20, 21], 14.0, false)
	add_anim("defeat", [22, 23, 24, 25], 8.0, false)
	add_anim("block", [26, 27], 9.0, false)
	play("walk")
	if role == "guard":
		block_chance = 0.65
		_blocks_left = 3
		patrol_range = 0.0
	elif role == "ambush":
		_waiting = true
		visible = false
		collision_layer = 0
		block_chance = 0.2

	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 120
	_alert.outline_size = 24
	_alert.modulate = Color(1.0, 0.85, 0.2)
	_alert.outline_modulate = Color(0.3, 0.05, 0.05)
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.position = Vector3(0, 2.0, 0.1)
	_alert.visible = false
	add_child(_alert)


func _physics_process(delta: float) -> void:
	var p := player()
	var dx := 0.0
	var dy := 0.0
	if p:
		dx = p.global_position.x - global_position.x
		dy = p.global_position.y - global_position.y
	if _waiting:
		# hidden up in the bamboo until Flutte walks underneath
		if _shadow:
			_shadow.visible = false
		if p and absf(dx) < 3.2:
			_waiting = false
			visible = true
			collision_layer = 4
			# drop a few steps ahead of Flutte, never on top of him
			var ahead := float(p.get("facing")) if "facing" in p else 1.0
			global_position.x = p.global_position.x + ahead * 3.4
			global_position.y = minf(global_position.y, p.global_position.y + 6.0)
			dx = p.global_position.x - global_position.x
			velocity = Vector3(0, -3.0, 0)
			facing = 1 if dx > 0.0 else -1
			play("attack", true)
			burst(global_position, Color(0.5, 0.85, 0.35), 14, 3.0, 0.12)
			_go(S.ALERT)
		return
	apply_gravity(delta)
	_t += delta
	_cooldown -= delta

	match _s:
		S.PATROL:
			if role == "guard":
				play("idle")
				velocity.x = 0.0
				if p:
					facing = 1 if dx > 0.0 else -1
			else:
				play("walk")
				velocity.x = facing * walk_speed
			if role == "guard":
				pass
			elif absf(global_position.x - home.x) > patrol_range and signf(global_position.x - home.x) == float(facing):
				facing = -facing
			elif is_on_floor() and not ground_ahead(0.5):
				facing = -facing
			if p and absf(dx) < sight and absf(dy) < 2.2:
				_go(S.ALERT)
		S.ALERT:
			velocity.x = 0.0
			if is_on_floor():
				play("idle")
			facing = 1 if dx > 0.0 else -1
			_alert.visible = true
			_alert.position.y = 2.0 + sin(_t * 30.0) * 0.04
			if _t > 0.45:
				_alert.visible = false
				_go(S.CHASE)
		S.CHASE:
			play("walk")
			facing = 1 if dx > 0.0 else -1
			velocity.x = facing * chase_speed
			if is_on_floor() and not ground_ahead(0.5) and absf(dy) < 0.5:
				velocity.x = 0.0          # don't run off a ledge
				play("idle")
			if absf(dx) < attack_range and absf(dy) < 1.2 and _cooldown <= 0.0:
				_go(S.ATTACK)
			elif absf(dx) > sight * 1.6 or absf(dy) > 3.5:
				home = global_position
				_go(S.PATROL)
		S.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			play("attack")
			var f := anim_frame()
			if f == 2 and not _hit_done:
				_hit_done = true
				_spawn_slash()
				velocity.x = facing * 2.5
				if p and signf(dx) == float(facing) and absf(dx) < attack_range + 0.35 and absf(dy) < 1.2:
					if p.has_method("take_damage"):
						p.call("take_damage", damage, self)
			if _anim_done:
				_cooldown = randf_range(0.8, 1.3)
				if randf() < 0.35 and is_on_floor():
					# hop back out of reach after the slash
					velocity = Vector3(-facing * 4.2, 4.6, 0)
					_go(S.HOP)
				else:
					_go(S.CHASE)
		S.BLOCK:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			play("block")
			if _t > 0.42:
				_cooldown = 0.0          # blocks, then strikes straight back
				_go(S.CHASE)
		S.HOP:
			play("idle")
			if _t > 0.15 and is_on_floor():
				_go(S.CHASE)
		S.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			play("hurt")
			if _t > 0.35:
				_go(S.CHASE)
		S.DEFEAT:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			play("defeat")
			if _t > 1.3:
				_sprite.modulate.a = maxf(0.0, 1.0 - (_t - 1.3) * 2.5)
			if _t > 1.7:
				queue_free()
	move(delta)
	tick_anim(delta)


func _go(s: S) -> void:
	_s = s
	_t = 0.0
	_hit_done = false
	if s == S.ATTACK:
		play("attack", true)


## Flutte's staff, tail spin, energy ball and fireworks all call this
func take_hit(amount: int, from: Node = null) -> void:
	if dead or _waiting:
		return
	# sword block: only against the staff, only from the front, and not forever
	var staff: bool = from != null and from.is_in_group("player") and float(from.get("_tail_t")) < 0.0
	if staff and _blocks_left > 0 and (_s == S.CHASE or _s == S.PATROL or _s == S.ALERT or _s == S.BLOCK) and is_on_floor():
		var front: bool = signf((from as Node3D).global_position.x - global_position.x) == float(facing) or _s != S.PATROL
		if front and randf() < block_chance:
			_blocks_left -= 1
			facing = 1 if (from as Node3D).global_position.x > global_position.x else -1
			burst(global_position + Vector3(facing * 0.5, 1.0, 0.25), Color(1.0, 1.0, 0.85), 12, 4.5, 0.08)
			velocity.x = -facing * 1.5
			if "velocity" in from:
				from.set("velocity", Vector3(-facing * -3.5, (from.get("velocity") as Vector3).y, 0))
			_go(S.BLOCK)
			play("block", true)
			return
	hp -= amount
	flash()
	var away := 1.0
	if from is Node3D:
		away = signf(global_position.x - (from as Node3D).global_position.x)
		if away == 0.0:
			away = 1.0
	facing = -int(away)
	burst(global_position + Vector3(0, 0.9, 0.2), Color(1.0, 0.95, 0.6), 10, 3.0, 0.1)
	if hp <= 0:
		dead = true
		collision_layer = 0
		collision_mask = 1
		velocity = Vector3(away * 5.0, 5.0, 0)
		_alert.visible = false
		_go(S.DEFEAT)
		play("defeat", true)
		burst(global_position + Vector3(0, 0.8, 0.2), Color(1.0, 0.3, 0.25), 18, 4.0, 0.14)
		spawn_bamboo(2)
		defeated.emit(self)
		get_tree().call_group("flutte_director", "on_enemy_defeated", self)
	else:
		velocity.y = 2.5
		knockback(from, 4.5, 0.25)
		_go(S.HURT)
		play("hurt", true)


func _spawn_slash() -> void:
	# red crescent like the art sheet's attack combo
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float t = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float s = clamp((a + 1.4) / 2.8, 0.0, 1.0);
	float th = 0.28 * sin(3.14159 * s);
	float band = smoothstep(0.86 - th, 0.86 - th * 0.4, r) * (1.0 - smoothstep(0.86, 0.92, r));
	float vis = step(-1.4, a) * step(a, 1.4) * step(s, t * 1.4);
	vec3 col = mix(vec3(1.0, 0.95, 0.95), vec3(0.95, 0.05, 0.1), smoothstep(0.0, 0.6, (0.86 - r) / max(th, 0.01)));
	ALBEDO = col;
	ALPHA = band * vis * (1.0 - smoothstep(0.6, 1.0, t));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(facing * 0.35, 0.75, 0.15)
	mi.scale = Vector3(facing, 1, 1)
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("t", v), 0.0, 1.0, 0.3)
	tw.tween_callback(mi.queue_free)
