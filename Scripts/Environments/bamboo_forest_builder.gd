extends Node3D
## Builds the decorative scenery for Level 01 (Bamboo Forest) when the level loads.
##
## Decorative only: nothing here has collision. Gameplay collision (ground,
## platforms) lives in the level scene so it is visible and editable in the editor.
##
## Performance: every repeated object (bamboo segments, leaves, blossoms, hills)
## is drawn with a MultiMeshInstance3D, so the whole forest costs a handful of
## draw calls. This keeps it light enough for phones.
##
## Depth: the camera is orthographic, which has no natural parallax, so each
## scenery layer is shifted by the camera's x position times (1 - parallax).
## parallax < 1 moves slower (far away), parallax > 1 moves faster (foreground).

const FOLIAGE_SHADER: Shader = preload("res://Assets/Materials/foliage_sway.gdshader")
const BACKDROP_SHADER: Shader = preload("res://Assets/Materials/sky_backdrop.gdshader")

const GROUND_Y: float = 0.0
const SEGMENT_HEIGHT: float = 1.0

@export var camera: Camera3D
@export var level_start_x: float = -25.0
@export var level_end_x: float = 125.0
@export var random_seed: int = 2026

# Atmospheric haze: distant layers are blended toward this colour.
@export var haze_color: Color = Color(0.98, 0.76, 0.84)

# Day and night sky colours, blended by set_night_amount().
@export var day_sky_top: Color = Color(0.93, 0.47, 0.68)
@export var day_sky_horizon: Color = Color(1.0, 0.84, 0.80)
@export var day_sun_color: Color = Color(1.0, 0.97, 0.86)
@export var night_sky_top: Color = Color(0.09, 0.08, 0.25)
@export var night_sky_horizon: Color = Color(0.42, 0.24, 0.48)
@export var night_moon_color: Color = Color(0.92, 0.94, 1.0)

var _rng := RandomNumberGenerator.new()
var _layers: Array[Node3D] = []
var _layer_factors: Array[float] = []
var _backdrop_material: ShaderMaterial
var _lantern_material: StandardMaterial3D
var _lantern_lights: Array[OmniLight3D] = []


func _ready() -> void:
	_rng.seed = random_seed
	_build_backdrop()
	_build_hills("FarHills", -42.0, -8.0, 0.2, Color(0.80, 0.62, 0.86), 0.55, 9.0, 16.0, 8.0, 10.5)
	_build_hills("MidHills", -26.0, -5.0, 0.45, Color(0.47, 0.70, 0.52), 0.35, 6.0, 11.0, 6.5, 8.5)
	_build_blossom_trees("BlossomTrees", -13.0, -10.0, 0.75)
	_build_bamboo("FarBamboo", -9.0, -6.5, 0.85, 1.4, 2.6, 9.0, 14.0, Color(0.55, 0.74, 0.36), 0.35, true)
	_build_bamboo("MidBamboo", -4.5, -2.5, 1.0, 2.2, 4.5, 8.0, 13.0, Color(0.50, 0.72, 0.28), 0.0, true)
	_build_flower_bushes("BackFlowers", -2.2, -1.2, 1.0, 2.5, 5.0)
	_build_lanterns("Lanterns", -1.6, 1.0)
	_build_flower_bushes("FrontFlowers", 9.0, 15.0, 1.1, 2.0, 5.0)
	_build_bamboo("ForegroundBamboo", 6.0, 8.0, 1.2, 10.0, 18.0, 12.0, 16.0, Color(0.30, 0.50, 0.20), 0.0, false)
	set_night_amount(0.0)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var cam_x := camera.global_position.x
	for i in _layers.size():
		_layers[i].position.x = cam_x * (1.0 - _layer_factors[i])


## 0.0 = full day, 1.0 = full night. Called by the DayNight controller.
func set_night_amount(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if _backdrop_material:
		_backdrop_material.set_shader_parameter("top_color", day_sky_top.lerp(night_sky_top, t))
		_backdrop_material.set_shader_parameter("horizon_color", day_sky_horizon.lerp(night_sky_horizon, t))
		_backdrop_material.set_shader_parameter("sun_color", day_sun_color.lerp(night_moon_color, t))
		_backdrop_material.set_shader_parameter("sun_size", lerpf(0.05, 0.035, t))
	if _lantern_material:
		_lantern_material.emission_energy_multiplier = lerpf(0.6, 3.0, t)
	for light in _lantern_lights:
		light.light_energy = lerpf(0.0, 1.6, t)
		light.visible = t > 0.01


# --------------------------------------------------------------------------
# Layer helpers
# --------------------------------------------------------------------------

func _make_layer(layer_name: String, parallax: float) -> Node3D:
	var layer := Node3D.new()
	layer.name = layer_name
	add_child(layer)
	_layers.append(layer)
	_layer_factors.append(parallax)
	return layer


func _to_linear(c: Color) -> Color:
	# Per-instance colours are read as linear by the shaders.
	return c.srgb_to_linear()


func _foliage_material(sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("sway_strength", sway)
	m.set_shader_parameter("ground_y", GROUND_Y)
	return m


func _flat_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	return m


func _make_multimesh(node_name: String, mesh: Mesh, material: Material,
		xforms: Array[Transform3D], colors: Array[Color], cast_shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	if cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# --------------------------------------------------------------------------
# Sky
# --------------------------------------------------------------------------

func _build_backdrop() -> void:
	if camera == null:
		push_warning("BambooForestBuilder: no camera assigned, sky backdrop skipped.")
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(60.0, 14.0)
	_backdrop_material = ShaderMaterial.new()
	_backdrop_material.shader = BACKDROP_SHADER
	_backdrop_material.set_shader_parameter("aspect", quad.size.x / quad.size.y)
	_backdrop_material.set_shader_parameter("sun_position", Vector2(0.62, 0.2))
	var backdrop := MeshInstance3D.new()
	backdrop.name = "SkyBackdrop"
	backdrop.mesh = quad
	backdrop.material_override = _backdrop_material
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.position = Vector3(0.0, 0.0, -95.0)
	# Deferred so we never add a child while the scene tree is still setting up.
	camera.add_child.call_deferred(backdrop)


# --------------------------------------------------------------------------
# Hills
# --------------------------------------------------------------------------

func _build_hills(layer_name: String, z: float, center_y: float, parallax: float, base_color: Color,
		haze: float, width_min: float, width_max: float, height_min: float, height_max: float) -> void:
	var layer := _make_layer(layer_name, parallax)
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x := level_start_x - 20.0
	while x < level_end_x + 20.0:
		var w := _rng.randf_range(width_min, width_max)
		var h := _rng.randf_range(height_min, height_max)
		var hill_basis := Basis.from_scale(Vector3(w, h, 3.0))
		xforms.append(Transform3D(hill_basis, Vector3(x, center_y, z + _rng.randf_range(-1.5, 1.5))))
		var shade := _rng.randf_range(-0.04, 0.04)
		var c: Color = base_color.lightened(shade) if shade > 0.0 else base_color.darkened(-shade)
		colors.append(_to_linear(c.lerp(haze_color, haze)))
		x += w * _rng.randf_range(0.9, 1.4)
	layer.add_child(_make_multimesh("Hills", mesh, _flat_material(), xforms, colors, false))


# --------------------------------------------------------------------------
# Bamboo
# --------------------------------------------------------------------------

func _build_bamboo(layer_name: String, z_min: float, z_max: float, parallax: float,
		spacing_min: float, spacing_max: float, height_min: float, height_max: float,
		base_color: Color, haze: float, cast_shadows: bool) -> void:
	var layer := _make_layer(layer_name, parallax)

	var segment := CylinderMesh.new()
	segment.top_radius = 0.11
	segment.bottom_radius = 0.12
	segment.height = SEGMENT_HEIGHT * 0.94
	segment.radial_segments = 8
	segment.rings = 1

	var node_ring := CylinderMesh.new()
	node_ring.top_radius = 0.14
	node_ring.bottom_radius = 0.14
	node_ring.height = 0.07
	node_ring.radial_segments = 8
	node_ring.rings = 1

	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.95, 0.17)

	var seg_x: Array[Transform3D] = []
	var seg_c: Array[Color] = []
	var ring_x: Array[Transform3D] = []
	var ring_c: Array[Color] = []
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []

	var x := level_start_x
	while x < level_end_x:
		var z := _rng.randf_range(z_min, z_max)
		var height := _rng.randf_range(height_min, height_max)
		var count := int(height / SEGMENT_HEIGHT)
		var stalk_color := base_color.lerp(Color(0.75, 0.78, 0.30), _rng.randf_range(0.0, 0.3))
		stalk_color = stalk_color.lerp(haze_color, haze)
		var ring_color := stalk_color.darkened(0.25)
		for i in count:
			var y := GROUND_Y + SEGMENT_HEIGHT * (float(i) + 0.5)
			seg_x.append(Transform3D(Basis(), Vector3(x, y, z)))
			seg_c.append(_to_linear(stalk_color))
			ring_x.append(Transform3D(Basis(), Vector3(x, GROUND_Y + SEGMENT_HEIGHT * float(i + 1), z)))
			ring_c.append(_to_linear(ring_color))

		# Leaves cluster on the upper part of the stalk.
		var leaf_count := _rng.randi_range(6, 11)
		for _j in leaf_count:
			var ly := GROUND_Y + height * _rng.randf_range(0.55, 0.98)
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var droop := deg_to_rad(_rng.randf_range(-35.0, 15.0)) * side
			var yaw := deg_to_rad(_rng.randf_range(-35.0, 35.0))
			var leaf_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, droop)
			var origin := Vector3(x, ly, z) + leaf_basis * Vector3(0.45 * side, 0.0, 0.0)
			leaf_x.append(Transform3D(leaf_basis, origin))
			var leaf_color := Color(0.36, 0.66, 0.24).lerp(Color(0.58, 0.80, 0.30), _rng.randf())
			leaf_c.append(_to_linear(leaf_color.lerp(haze_color, haze)))

		x += _rng.randf_range(spacing_min, spacing_max)

	var stalk_mat := _foliage_material(0.0025)
	layer.add_child(_make_multimesh("Stalks", segment, stalk_mat, seg_x, seg_c, cast_shadows))
	layer.add_child(_make_multimesh("Nodes", node_ring, stalk_mat, ring_x, ring_c, false))
	layer.add_child(_make_multimesh("Leaves", leaf, _foliage_material(0.0035), leaf_x, leaf_c, cast_shadows))


# --------------------------------------------------------------------------
# Pink blossom trees (background)
# --------------------------------------------------------------------------

func _build_blossom_trees(layer_name: String, z_min: float, z_max: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.32
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1

	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 12
	puff.rings = 6

	var trunk_x: Array[Transform3D] = []
	var trunk_c: Array[Color] = []
	var puff_x: Array[Transform3D] = []
	var puff_c: Array[Color] = []

	var x := level_start_x + _rng.randf_range(0.0, 6.0)
	while x < level_end_x:
		var z := _rng.randf_range(z_min, z_max)
		var h := _rng.randf_range(4.0, 6.5)
		trunk_x.append(Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(x, GROUND_Y + h * 0.5, z)))
		trunk_c.append(_to_linear(Color(0.45, 0.30, 0.25).lerp(haze_color, 0.25)))
		var puffs := _rng.randi_range(5, 8)
		for _i in puffs:
			var r := _rng.randf_range(0.9, 1.6)
			var offset := Vector3(_rng.randf_range(-1.8, 1.8), _rng.randf_range(-0.4, 1.3), _rng.randf_range(-0.6, 0.6))
			puff_x.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.8, r)), Vector3(x, GROUND_Y + h, z) + offset))
			var pink := Color(1.0, 0.62, 0.78).lerp(Color(0.98, 0.80, 0.88), _rng.randf())
			puff_c.append(_to_linear(pink.lerp(haze_color, 0.2)))
		x += _rng.randf_range(9.0, 16.0)

	layer.add_child(_make_multimesh("Trunks", trunk, _flat_material(), trunk_x, trunk_c, true))
	layer.add_child(_make_multimesh("Blossoms", puff, _foliage_material(0.0012), puff_x, puff_c, true))


# --------------------------------------------------------------------------
# Pink flower bushes
# --------------------------------------------------------------------------

func _build_flower_bushes(layer_name: String, z_min: float, z_max: float, parallax: float,
		spacing_min: float, spacing_max: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var bush := SphereMesh.new()
	bush.radius = 1.0
	bush.height = 2.0
	bush.radial_segments = 12
	bush.rings = 6

	var flower := SphereMesh.new()
	flower.radius = 0.11
	flower.height = 0.18
	flower.radial_segments = 8
	flower.rings = 4

	var bush_x: Array[Transform3D] = []
	var bush_c: Array[Color] = []
	var flower_x: Array[Transform3D] = []
	var flower_c: Array[Color] = []

	var x := level_start_x + _rng.randf_range(0.0, 3.0)
	while x < level_end_x:
		var z := _rng.randf_range(z_min, z_max)
		var bush_size := Vector3(_rng.randf_range(0.8, 1.4), _rng.randf_range(0.45, 0.7), _rng.randf_range(0.5, 0.8))
		var center := Vector3(x, GROUND_Y + bush_size.y * 0.5, z)
		bush_x.append(Transform3D(Basis.from_scale(bush_size), center))
		bush_c.append(_to_linear(Color(0.30, 0.58, 0.26).lerp(Color(0.44, 0.70, 0.30), _rng.randf())))
		var flowers := _rng.randi_range(7, 14)
		for _i in flowers:
			# Random point on the upper half of the bush surface.
			var a := _rng.randf_range(0.0, TAU)
			var e := _rng.randf_range(0.15, 1.3)
			var dir := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
			var p := center + Vector3(dir.x * bush_size.x, dir.y * bush_size.y, dir.z * bush_size.z)
			flower_x.append(Transform3D(Basis(), p))
			var pink := Color(1.0, 0.45, 0.68).lerp(Color(1.0, 0.78, 0.88), _rng.randf())
			flower_c.append(_to_linear(pink))
		x += _rng.randf_range(spacing_min, spacing_max)

	layer.add_child(_make_multimesh("Bushes", bush, _foliage_material(0.004), bush_x, bush_c, true))
	layer.add_child(_make_multimesh("Flowers", flower, _foliage_material(0.004), flower_x, flower_c, false))


# --------------------------------------------------------------------------
# Lanterns (glow at night)
# --------------------------------------------------------------------------

func _build_lanterns(layer_name: String, z: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.6, 0.12)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.32, 0.20, 0.14)
	post.material = post_mat

	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.38, 0.48, 0.38)
	_lantern_material = StandardMaterial3D.new()
	_lantern_material.albedo_color = Color(1.0, 0.82, 0.55)
	_lantern_material.emission_enabled = true
	_lantern_material.emission = Color(1.0, 0.62, 0.30)
	lamp.material = _lantern_material

	var x := level_start_x + 14.0
	while x < level_end_x:
		var post_node := MeshInstance3D.new()
		post_node.mesh = post
		post_node.position = Vector3(x, GROUND_Y + 0.8, z)
		layer.add_child(post_node)

		var lamp_node := MeshInstance3D.new()
		lamp_node.mesh = lamp
		lamp_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp_node.position = Vector3(x, GROUND_Y + 1.8, z)
		layer.add_child(lamp_node)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.70, 0.40)
		light.omni_range = 4.5
		light.shadow_enabled = false
		light.position = Vector3(x, GROUND_Y + 1.8, z + 0.6)
		layer.add_child(light)
		_lantern_lights.append(light)

		x += 26.0
