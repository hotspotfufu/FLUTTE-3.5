extends "flutte_enemy_base.gd"
## THE SHADOW BEAR - boss of the bamboo forest.
## Attacks:  claw swipe combo (close), ground slam that sends purple shockwaves
## along the ground (jump over them), roar that blasts Flutte back, and a
## charging run when Flutte is far away. Gets faster and angrier at half health.
## Damage taken: staff / tail = 1, firework = 3, energy ball = 8.

enum S { INTRO, IDLE, WALK, CHARGE, SWIPE, SLAM, ROAR, STAGGER, DEFEAT }

@export var max_hp := 45

var _s := S.INTRO
var _t := 0.0
var _think := 0.0
var _did := false
var _hits_since_stagger := 0
var _angry := false
var _attack_count := 0
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _waves: Array = []


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	collision_layer = 4
	collision_mask = 1 | 2      # solid: Flutte can't walk through him
	hp = max_hp
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.75
	cap.height = 2.9
	col.shape = cap
	col.position = Vector3(0, 1.45, 0)
	add_child(col)
	sprite_z = 0.9
	shadow_size = 2.3
	setup_sprite("boss_bear.png", Vector2i(200, 156), 8, 3.6, 129.0)
	add_anim("idle", [0, 1, 2], 4.0)
	add_anim("walk", [3, 4, 5, 6, 7], 7.0)
	add_anim("run", [8, 9, 10, 11], 11.0)
	add_anim("swipe", [12, 13, 14, 15, 16, 17], 9.0, false)
	add_anim("slam", [18, 19, 20, 21], 1.0, false)     # driven by hand below
	add_anim("roar", [22, 23, 24, 23, 24, 23, 24], 7.0, false)
	add_anim("hurt", [25, 26, 27, 28], 10.0, false)
	add_anim("defeat", [29, 30, 31, 32], 3.5, false)
	play("idle")

	# soft purple glow on the ground under him
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.albedo_texture = soft_texture()
	_aura_mat.albedo_color = Color(0.6, 0.15, 0.9, 0.22)
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 1.2)
	_aura = MeshInstance3D.new()
	_aura.mesh = q
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 0.15, -0.3)
	add_child(_aura)
	velocity.y = -2.0
	_report()


func _physics_process(delta: float) -> void:
	apply_gravity(delta)
	_t += delta
	var p := player()
	var dx := 0.0
	var dy := 0.0
	if p:
		dx = p.global_position.x - global_position.x
		dy = p.global_position.y - global_position.y
	var speed_k := 1.3 if _angry else 1.0

	match _s:
		S.INTRO:
			velocity.x = 0.0
			if is_on_floor() and not _did:
				_did = true
				_shake(0.35)
				burst(global_position + Vector3(0, 0.3, 0.3), Color(0.75, 0.35, 1.0), 30, 6.0, 0.2)
				play("roar", true)
			if _did and _anim_done:
				_go(S.IDLE)
			facing = 1 if dx > 0.0 else -1
		S.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			play("idle")
			facing = 1 if dx > 0.0 else -1
			if _t > (0.35 if _angry else 0.7):
				_choose(absf(dx))
		S.WALK:
			play("walk")
			facing = 1 if dx > 0.0 else -1
			velocity.x = facing * 2.2 * speed_k
			if absf(dx) < 2.6 or _t > 2.0:
				_choose(absf(dx))
		S.CHARGE:
			play("run")
			velocity.x = facing * 7.5 * speed_k
			if fmod(_t, 0.12) < delta:
				burst(global_position + Vector3(-facing * 0.8, 0.2, 0.2), Color(0.85, 0.7, 1.0), 4, 1.5, 0.25)
			if (signf(dx) != float(facing) and absf(dx) > 2.5) or _t > 1.8 or is_on_wall():
				_go(S.IDLE)
		S.SWIPE:
			play("swipe")
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			var f := anim_frame()
			if f == 2 and not _did:
				_did = true
				velocity.x = facing * 3.5
				_shake(0.08)
			if f >= 2 and f <= 4 and p and signf(dx) == float(facing) and absf(dx) < 3.0 and dy > -1.0 and dy < 2.6:
				_hurt_player(p, 15)
			if _anim_done:
				_go(S.IDLE)
		S.SLAM:
			velocity.x = 0.0
			var fr := 0
			if _t < 0.25:
				fr = 0
			elif _t < 0.85 / speed_k:
				fr = 1
			elif _t < 1.05 / speed_k:
				fr = 2
			else:
				fr = 3
			_force_frame(18 + fr)
			if fr >= 2 and not _did:
				_did = true
				_shake(0.3)
				_spawn_wave(1)
				_spawn_wave(-1)
			if _t > 1.6 / speed_k:
				_go(S.IDLE)
		S.ROAR:
			velocity.x = 0.0
			play("roar")
			if _t > 0.35 and not _did:
				_did = true
				_shake(0.25)
				if p and absf(dx) < 5.5 and absf(dy) < 3.0:
					_hurt_player(p, 8)
					if "velocity" in p:
						p.set("velocity", Vector3(signf(dx) * 11.0, 5.0, 0))
			if _anim_done:
				_go(S.IDLE)
		S.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 15.0 * delta)
			play("hurt")
			if _anim_done:
				_go(S.IDLE)
		S.DEFEAT:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			play("defeat")
			if _t > 3.0:
				_sprite.modulate.a = maxf(0.0, 1.0 - (_t - 3.0))
				_aura_mat.albedo_color.a = maxf(0.0, 0.22 - (_t - 3.0))
			if _t > 4.0:
				queue_free()

	# walking into the bear hurts
	if _s != S.DEFEAT and _s != S.INTRO and p and absf(dx) < 1.0 and dy > -0.5 and dy < 3.0:
		_hurt_player(p, 10)

	move(delta)
	if _s != S.SLAM:
		tick_anim(delta)
	else:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_sprite.flip_h = (facing < 0) == _art_faces_right
		_sprite.modulate = _base_tint().lerp(Color(1.0, 0.35, 0.35), _flash)
	if _s != S.SLAM:
		_sprite.modulate = _base_tint().lerp(Color(1.0, 0.35, 0.35), _flash)
	_aura.scale = Vector3.ONE * (1.0 + sin(_t * 6.0) * 0.06)
	_update_waves(delta)


func _base_tint() -> Color:
	return Color(1.0, 0.85, 1.0) if _angry else Color.WHITE


func _choose(dist: float) -> void:
	_attack_count += 1
	if _angry and _attack_count % 4 == 0:
		_go(S.ROAR)
	elif dist > 9.0:
		_go(S.CHARGE)
	elif dist < 2.8:
		_go(S.SWIPE if randf() < 0.7 else S.ROAR)
	elif _s != S.WALK and randf() < 0.55:
		_go(S.SLAM)
	elif _s == S.WALK:
		_go(S.SLAM if randf() < 0.5 else S.CHARGE)
	else:
		_go(S.WALK)


func _go(s: S) -> void:
	_s = s
	_t = 0.0
	_did = false
	match s:
		S.SWIPE:
			play("swipe", true)
		S.ROAR:
			play("roar", true)
		S.STAGGER:
			play("hurt", true)
		S.DEFEAT:
			play("defeat", true)
		S.CHARGE:
			var p := player()
			if p:
				facing = 1 if p.global_position.x > global_position.x else -1


func _force_frame(f: int) -> void:
	_sprite.region_rect = Rect2((f % _cols) * _cell.x, (f / _cols) * _cell.y, _cell.x, _cell.y)


func _hurt_player(p: Node, amount: int) -> void:
	if p.has_method("take_damage"):
		p.call("take_damage", amount, self)


func _shake(amount: float) -> void:
	var p := player()
	if p and "_shake" in p:
		p.set("_shake", maxf(float(p.get("_shake")), amount))


## Flutte's attacks call this
func take_hit(amount: int, from: Node = null) -> void:
	if dead or _s == S.INTRO:
		return
	hp = maxi(0, hp - amount)
	flash()
	burst(global_position + Vector3(0, 1.8, 0.4), Color(1.0, 0.9, 1.0), 10, 3.5, 0.12)
	_report()
	if hp <= 0:
		dead = true
		collision_layer = 0
		collision_mask = 1
		_go(S.DEFEAT)
		_shake(0.5)
		for i in 4:
			burst(global_position + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), 0.4), Color(0.75, 0.35, 1.0), 24, 6.0, 0.22)
		spawn_bamboo(10)
		defeated.emit(self)
		get_tree().call_group("flutte_director", "on_boss_defeated", self)
		return
	if not _angry and hp <= max_hp / 2:
		_angry = true
		_go(S.ROAR)          # gets angry at half health
		return
	if _s == S.IDLE or _s == S.WALK or _s == S.STAGGER:
		knockback(from, 2.2, 0.16)     # a big bear only budges a little
	_hits_since_stagger += 1
	if _hits_since_stagger >= 6 and (_s == S.IDLE or _s == S.WALK):
		_hits_since_stagger = 0
		_go(S.STAGGER)


func _report() -> void:
	get_tree().call_group("flutte_director", "on_boss_health", hp, max_hp)


# ------------------------------------------------------------- shockwaves
const WAVE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float life = 1.0;
float hash(float n) { return fract(sin(n * 91.7) * 43758.5); }
void fragment() {
	vec2 p = UV;
	float x = p.x * 9.0;
	float i = floor(x);
	float f = fract(x) - 0.5;
	float h = 0.45 + 0.55 * hash(i + floor(TIME * 12.0));
	float spike = (1.0 - p.y) < h * (1.0 - abs(f) * 2.0) ? 1.0 : 0.0;
	float glow = smoothstep(0.0, 0.9, 1.0 - p.y) * 0.35;
	vec3 col = mix(vec3(0.55, 0.1, 0.95), vec3(1.0, 0.85, 1.0), smoothstep(0.4, 0.95, 1.0 - p.y));
	ALBEDO = col;
	ALPHA = clamp(spike + glow, 0.0, 1.0) * life;
}
"""


func _spawn_wave(dir: int) -> void:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WAVE_SHADER
	m.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.1)
	var w := MeshInstance3D.new()
	w.mesh = q
	w.material_override = m
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(w)
	w.global_position = global_position + Vector3(dir * 1.2, 0.55, 0.3)
	_waves.append({"node": w, "mat": m, "dir": dir, "t": 0.0, "hit": false})


func _update_waves(delta: float) -> void:
	var p := player()
	for wv in _waves.duplicate():
		var w: MeshInstance3D = wv["node"]
		wv["t"] += delta
		var t: float = wv["t"]
		w.global_position.x += float(wv["dir"]) * (9.5 if _angry else 8.0) * delta
		(wv["mat"] as ShaderMaterial).set_shader_parameter("life", clampf(1.6 - t, 0.0, 1.0))
		if p and not wv["hit"] and absf(p.global_position.x - w.global_position.x) < 0.65 and p.global_position.y < global_position.y + 0.8:
			wv["hit"] = true
			_hurt_player(p, 20)
		if t > 1.6:
			w.queue_free()
			_waves.erase(wv)
