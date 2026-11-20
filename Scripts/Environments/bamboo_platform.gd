extends StaticBody3D
## Floating platform: a raft of bamboo logs tied with rope, with a soft round
## cushion of grass and little flowers on top, and leaves hanging off the edges.
## Set `width` per instance in the level; the look and collision resize on load.
## Each instance gets its own collision shape, so instances never share sizes.

@export var width: float = 3.0
@export var thickness: float = 0.4
@export var depth: float = 1.6

@onready var _plank: MeshInstance3D = $Plank
@onready var _trim: MeshInstance3D = $Trim
@onready var _collision: CollisionShape3D = $CollisionShape3D

static var _mats := {}


func _ready() -> void:
	_apply_size()
	_build_look()


func _apply_size() -> void:
	_plank.scale = Vector3(width, thickness, depth)
	_trim.scale = Vector3(width + 0.08, 0.08, depth + 0.04)
	_trim.position = Vector3(0.0, thickness * 0.5 - 0.02, 0.0)
	var box := BoxShape3D.new()
	box.size = Vector3(width, thickness, depth)
	_collision.shape = box


static func _mat(key: String, c: Color, rough: float = 0.8, rim: float = 0.3) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = rim
	m.rim_tint = 0.6
	_mats[key] = m
	return m


func _add(mesh: Mesh, mat: Material, xf: Transform3D, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_look() -> void:
	_plank.visible = false
	_trim.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 13.0 + global_position.y * 7.0)
	var half_t := thickness * 0.5

	# bamboo logs lying side by side (front, middle, back), each with darker node rings
	var r := thickness * 0.34
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = r
	log_mesh.bottom_radius = r
	log_mesh.height = width + 0.25
	log_mesh.radial_segments = 14
	log_mesh.rings = 1
	var cap := CylinderMesh.new()          # pale cut ends
	cap.top_radius = r * 0.92
	cap.bottom_radius = r * 0.92
	cap.height = 0.02
	cap.radial_segments = 14
	var ring := CylinderMesh.new()
	ring.top_radius = r * 1.07
	ring.bottom_radius = r * 1.07
	ring.height = 0.05
	ring.radial_segments = 14
	var rope := CylinderMesh.new()
	rope.top_radius = r * 1.13
	rope.bottom_radius = r * 1.13
	rope.height = 0.09
	rope.radial_segments = 14
	var along_x := Basis(Vector3.BACK, PI * 0.5)
	var rows := maxi(3, int(depth / (r * 2.0)))
	for i in rows:
		var z := lerpf(-depth * 0.5 + r, depth * 0.5 - r, float(i) / float(rows - 1))
		var y := -half_t + r + (0.02 if i % 2 == 0 else 0.0)
		var shade := rng.randf_range(-0.04, 0.04)
		var col := Color(0.58, 0.76, 0.30).lightened(shade) if i % 2 == 0 else Color(0.70, 0.80, 0.34).lightened(shade)
		_add(log_mesh, _mat("log%d" % (i % 2), col, 0.45, 0.4), Transform3D(along_x, Vector3(0, y, z)))
		for e in [-1.0, 1.0]:
			_add(cap, _mat("cap", Color(0.93, 0.88, 0.62), 0.9), Transform3D(along_x, Vector3(e * (width * 0.5 + 0.125), y, z)), false)
		var n := maxi(1, int(width / 1.1))
		for k in n:
			var x := (float(k) + 0.5) / float(n) * width - width * 0.5 + rng.randf_range(-0.15, 0.15)
			_add(ring, _mat("ring", Color(0.46, 0.60, 0.22), 0.5), Transform3D(along_x, Vector3(x, y, z)), false)
	# rope ties near both ends
	for e in [-1.0, 1.0]:
		for i in rows:
			var z := lerpf(-depth * 0.5 + r, depth * 0.5 - r, float(i) / float(rows - 1))
			_add(rope, _mat("rope", Color(0.80, 0.30, 0.22), 0.9), Transform3D(along_x, Vector3(e * (width * 0.5 - 0.3), -half_t + r, z)), false)

	# soft grass cushion on top (a squashed capsule = rounded ends)
	var cushion := CapsuleMesh.new()
	cushion.radius = depth * 0.5
	cushion.height = width + 0.1
	cushion.radial_segments = 20
	cushion.rings = 6
	var cb := along_x.scaled(Vector3(1.0, 1.0, 1.0))
	cb = Basis.from_scale(Vector3(1.0, 0.16 / (depth * 0.5), 1.0)) * cb
	_add(cushion, _mat("grass", Color(0.45, 0.76, 0.32), 0.9, 0.5), Transform3D(cb, Vector3(0, half_t - 0.1, 0)))

	# a few flowers and grass blades on the cushion, leaves dangling off the front
	var flower := SphereMesh.new()
	flower.radius = 0.06
	flower.height = 0.09
	flower.radial_segments = 8
	flower.rings = 4
	var cols := [Color(1.0, 0.5, 0.7), Color(1.0, 0.95, 0.98), Color(1.0, 0.85, 0.35)]
	for i in int(width * 2.0):
		var x := rng.randf_range(-width * 0.45, width * 0.45)
		var z := rng.randf_range(0.1, depth * 0.45)
		var c: Color = cols[rng.randi() % cols.size()]
		_add(flower, _mat("fl%d" % cols.find(c), c, 0.7, 0.2), Transform3D(Basis(), Vector3(x, half_t + 0.11, z)), false)
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.16, 0.5, 0.02)
	for i in int(width * 1.5):
		var x := rng.randf_range(-width * 0.48, width * 0.48)
		var b := Basis(Vector3.BACK, PI + rng.randf_range(-0.4, 0.4))
		_add(leaf, _mat("leaf", Color(0.36, 0.64, 0.26), 0.8, 0.3), Transform3D(b, Vector3(x, -half_t - 0.12, depth * 0.5 - 0.05)), false)
