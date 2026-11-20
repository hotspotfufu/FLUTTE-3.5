extends Node3D
## Builds the scenery for Level 01 (Bamboo Forest) when the level loads.
##
## Decorative only: nothing here has collision. Gameplay collision (ground,
## platforms) lives in the level scene so it is visible and editable in the editor.
##
## The level is seen through a perspective camera from the side, like
## Kirby: Return to Dream Land. Scenery is laid out in depth, so it gets real
## parallax for free:
##   far:        sky, clouds, misty mountains, rolling hills
##   background: cherry blossom trees, distant bamboo groves
##   middle:     detailed bamboo, flower bushes, lanterns (behind the path)
##   play lane:  the path (z = 0) where Flutte and his opponents move
##   foreground: low grass, flowers, stones and round bushes in front of the path,
##               plus a few tall bamboo stalks that fade out when Flutte is behind them
##
## Performance: every repeated object is drawn with a MultiMeshInstance3D, so the
## whole forest costs a few dozen draw calls. This keeps it light enough for phones.
##
## If the camera is orthographic (older scenes) the layers fall back to the old
## fake-parallax shifting.

const FOLIAGE_SHADER: Shader = preload("res://Assets/Materials/foliage_sway.gdshader")
const BACKDROP_SHADER: Shader = preload("res://Assets/Materials/sky_backdrop.gdshader")

const GROUND_Y: float = 0.0
const SEGMENT_HEIGHT: float = 1.0

@export var camera: Camera3D
@export var level_start_x: float = -25.0
@export var level_end_x: float = 142.0
@export var random_seed: int = 2026

# Atmospheric haze: distant layers are blended toward this colour.
@export var haze_color: Color = Color(0.98, 0.80, 0.88)

# Day and night sky colours, blended by set_night_amount().
@export var day_sky_top: Color = Color(0.45, 0.70, 0.98)
@export var day_sky_horizon: Color = Color(1.0, 0.86, 0.90)
@export var day_sun_color: Color = Color(1.0, 0.98, 0.88)
@export var night_sky_top: Color = Color(0.09, 0.08, 0.25)
@export var night_sky_horizon: Color = Color(0.42, 0.24, 0.48)
@export var night_moon_color: Color = Color(0.92, 0.94, 1.0)

var _rng := RandomNumberGenerator.new()
var _layers: Array[Node3D] = []
var _layer_factors: Array[float] = []
var _backdrop_material: ShaderMaterial
var _lantern_material: StandardMaterial3D
var _lantern_lights: Array[OmniLight3D] = []
var _cloud_layer: Node3D
var _fg_fade_mat: ShaderMaterial
var _perspective := true


func _ready() -> void:
	_rng.seed = random_seed
	_perspective = camera == null or camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	_build_backdrop()
	_build_far_ground()
	_build_clouds("Clouds", -95.0, 0.05)
	_build_hills("Mountains", -78.0, -6.0, 0.1, Color(0.70, 0.62, 0.90), 0.55, 16.0, 26.0, 13.0, 19.0, 0.8)
	_build_hills("FarHills", -48.0, -5.5, 0.2, Color(0.55, 0.78, 0.60), 0.45, 9.0, 16.0, 7.0, 9.5, 1.0)
	_build_hills("MidHills", -30.0, -4.0, 0.45, Color(0.45, 0.76, 0.42), 0.25, 6.0, 11.0, 5.0, 7.0, 1.0)
	_build_blossom_trees("BlossomTrees", -20.0, -11.0, 0.75)
	_build_bamboo("FarBamboo", -10.0, -7.0, 0.85, 1.1, 2.2, 9.0, 13.0, Color(0.56, 0.78, 0.40), 0.30, true, 0.10)
	_build_bamboo("MidBamboo", -5.5, -2.8, 1.0, 1.8, 3.6, 8.0, 12.0, Color(0.46, 0.74, 0.28), 0.0, true, 0.13)
	_build_flower_bushes("BackFlowers", -2.4, -1.1, 1.0, 1.6, 3.4, 1.0)
	_build_grass("BackGrass", -1.0, -0.75, 1.0, 0.35, 1.0)
	_build_lanterns("Lanterns", -1.7, 1.0)
	_build_path_edge("PathEdge")
	_build_grass("FrontGrass", 1.3, 3.5, 1.0, 0.28, 1.0)
	_build_stones("Stones", 1.6, 5.5, 1.0)
	_build_flower_bushes("FrontFlowers", 3.0, 7.0, 1.05, 2.4, 5.0, 0.45)
	_build_foreground_bamboo("ForegroundBamboo", 7.5, 9.0)
	_style_ground()
	set_night_amount(0.0)


func _process(delta: float) -> void:
	if camera == null:
		return
	var cam_x := camera.global_position.x
	if not _perspective:
		for i in _layers.size():
			_layers[i].position.x = cam_x * (1.0 - _layer_factors[i])
	elif _cloud_layer:
		_cloud_layer.position.x += delta * 0.35          # clouds drift slowly
	# tall foreground stalks open up wherever they would hide Flutte or an opponent
	if _fg_fade_mat and camera.is_inside_tree():
		var vp := get_viewport().get_visible_rect().size
		var xs := [-10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0]
		var who: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemies")
		var n := 0
		for c in who:
			if n >= xs.size():
				break
			if not (c is Node3D) or camera.is_position_behind((c as Node3D).global_position):
				continue
			var sx := camera.unproject_position((c as Node3D).global_position + Vector3(0, 0.9, 0)).x / vp.x
			if sx > -0.2 and sx < 1.2:
				xs[n] = sx
				n += 1
		_fg_fade_mat.set_shader_parameter("hide_a", Vector4(xs[0], xs[1], xs[2], xs[3]))
		_fg_fade_mat.set_shader_parameter("hide_b", Vector4(xs[4], xs[5], xs[6], xs[7]))


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


func _foliage_material(sway: float, rim: float = 0.35, backlight: float = 0.0, shade: float = 0.22, shade_h: float = 0.8) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("sway_strength", sway)
	m.set_shader_parameter("ground_y", GROUND_Y)
	m.set_shader_parameter("rim_amount", rim)
	m.set_shader_parameter("backlight_amount", backlight)
	m.set_shader_parameter("ground_shade", shade)
	m.set_shader_parameter("shade_height", shade_h)
	return m


func _flat_material(rim: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.7
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


func _shade(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)


# --------------------------------------------------------------------------
# Hand-built meshes (made once, drawn many times)
# --------------------------------------------------------------------------

## One bamboo leaf: long and pointed, folded along the midrib, drooping at the tip.
func _leaf_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 7
	var pts_l: Array[Vector3] = []
	var pts_c: Array[Vector3] = []
	var pts_r: Array[Vector3] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var w := sin(pow(t, 0.75) * PI) * width * 0.5 * (1.0 - t * 0.25)
		var droop := -t * t * length * 0.28
		var x := t * length
		pts_c.append(Vector3(x, droop + 0.012, 0))       # raised midrib = V fold
		pts_l.append(Vector3(x, droop, w))
		pts_r.append(Vector3(x, droop, -w))
	for i in steps:
		var shade_a := 0.85 + 0.15 * float(i) / float(steps)
		for side in [pts_l, pts_r]:
			var a: Vector3 = pts_c[i]
			var b: Vector3 = pts_c[i + 1]
			var c: Vector3 = side[i + 1]
			var d: Vector3 = side[i]
			var n := (b - a).cross(d - a).normalized()
			if n.y < 0.0:
				n = -n
			st.set_normal(n)
			st.set_color(Color(1.08 * shade_a, 1.08 * shade_a, 1.0 * shade_a))
			st.add_vertex(a)
			st.set_color(Color(shade_a, shade_a, shade_a))
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	return st.commit()


## A tuft of grass: thin curved blades fanned out, darker at the roots.
func _grass_mesh(blades: int, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in blades:
		var ang := (float(b) / float(blades) - 0.5) * 1.6 + rng.randf_range(-0.15, 0.15)
		var yaw := rng.randf_range(-0.9, 0.9)
		var h := height * rng.randf_range(0.6, 1.1)
		var w := 0.05
		var dirv := Vector3(sin(ang), cos(ang), 0).rotated(Vector3.UP, yaw)
		var side := Vector3(cos(ang), -sin(ang), 0).rotated(Vector3.UP, yaw) * w
		var base := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		var mid := base + dirv * h * 0.55 + Vector3(0, 0, 0)
		var tip := base + dirv * h + Vector3(sin(ang) * h * 0.25, -h * 0.08, 0).rotated(Vector3.UP, yaw)
		var n := side.cross(dirv).normalized()
		st.set_normal(n)
		st.set_color(Color(0.55, 0.6, 0.5))
		st.add_vertex(base - side)
		st.add_vertex(base + side)
		st.set_color(Color(0.9, 0.95, 0.85))
		st.add_vertex(mid + side * 0.7)
		st.set_color(Color(0.55, 0.6, 0.5))
		st.add_vertex(base - side)
		st.set_color(Color(0.9, 0.95, 0.85))
		st.add_vertex(mid + side * 0.7)
		st.add_vertex(mid - side * 0.7)
		st.add_vertex(mid - side * 0.7)
		st.add_vertex(mid + side * 0.7)
		st.set_color(Color(1.15, 1.18, 1.0))
		st.add_vertex(tip)
	return st.commit()


## A five-petal blossom facing up (and a bit toward the camera).
func _flower_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in 5:
		var a0 := TAU * float(p) / 5.0
		var segs := 6
		for s in segs:
			var t0 := float(s) / float(segs)
			var t1 := float(s + 1) / float(segs)
			var aa := a0 + (t0 - 0.5) * 1.15
			var ab := a0 + (t1 - 0.5) * 1.15
			var ra := radius * (0.75 + 0.25 * sin(t0 * PI))
			var rb := radius * (0.75 + 0.25 * sin(t1 * PI))
			var c0 := Vector3(0, 0.02, 0)
			var pa := Vector3(cos(aa) * ra, 0.03 + ra * 0.25, sin(aa) * ra)
			var pb := Vector3(cos(ab) * rb, 0.03 + rb * 0.25, sin(ab) * rb)
			st.set_normal(Vector3.UP)
			st.set_color(Color(1.25, 1.2, 1.15))
			st.add_vertex(c0)
			st.set_color(Color(1, 1, 1))
			st.add_vertex(pa)
			st.add_vertex(pb)
	return st.commit()


func _sphere(radius: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


func _cylinder(top: float, bottom: float, height: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = seg
	m.rings = 1
	return m


# --------------------------------------------------------------------------
# Sky
# --------------------------------------------------------------------------

func _build_backdrop() -> void:
	if camera == null:
		push_warning("BambooForestBuilder: no camera assigned, sky backdrop skipped.")
		return
	var dist := 95.0
	var size := Vector2(60.0, 14.0)
	if _perspective:
		dist = 180.0
		camera.far = maxf(camera.far, 240.0)
		var h := 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) * 1.35
		size = Vector2(h * 2.4, h)
	var quad := QuadMesh.new()
	quad.size = size
	_backdrop_material = ShaderMaterial.new()
	_backdrop_material.shader = BACKDROP_SHADER
	_backdrop_material.set_shader_parameter("aspect", quad.size.x / quad.size.y)
	_backdrop_material.set_shader_parameter("sun_position", Vector2(0.64, 0.24))
	var backdrop := MeshInstance3D.new()
	backdrop.name = "SkyBackdrop"
	backdrop.mesh = quad
	backdrop.material_override = _backdrop_material
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.position = Vector3(0.0, 0.0, -dist)
	# Deferred so we never add a child while the scene tree is still setting up.
	camera.add_child.call_deferred(backdrop)


## soft cotton-ball clouds far behind everything
func _build_clouds(layer_name: String, z: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)
	_cloud_layer = layer
	var puff := _sphere(1.0, 14, 7)
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var x := level_start_x - 60.0
	while x < level_end_x + 60.0:
		var y := _rng.randf_range(16.0, 30.0)
		var n := _rng.randi_range(4, 7)
		var w := _rng.randf_range(7.0, 13.0)
		for i in n:
			var t := float(i) / float(n - 1) - 0.5
			var r := _rng.randf_range(2.2, 3.8) * (1.0 - absf(t) * 0.8)
			var p := Vector3(x + t * w, y + _rng.randf_range(-0.4, 1.2) * (1.0 - absf(t)), z + _rng.randf_range(-3.0, 3.0))
			xf.append(Transform3D(Basis.from_scale(Vector3(r * 1.25, r, r)), p))
			col.append(_to_linear(Color(1.0, 0.97, 0.98)))
		# flat bottom
		xf.append(Transform3D(Basis.from_scale(Vector3(w * 0.55, 1.2, 2.5)), Vector3(x, y - 0.6, z)))
		col.append(_to_linear(Color(0.98, 0.92, 0.96)))
		x += _rng.randf_range(22.0, 40.0)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	layer.add_child(_make_multimesh("Clouds", puff, m, xf, col, false))


## the meadow continues far into the distance behind the play area
func _build_far_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 160.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.56, 0.80, 0.46)
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.name = "FarMeadow"
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(50.0, GROUND_Y - 0.03, -92.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --------------------------------------------------------------------------
# Hills and mountains
# --------------------------------------------------------------------------

func _build_hills(layer_name: String, z: float, center_y: float, parallax: float, base_color: Color,
		haze: float, width_min: float, width_max: float, height_min: float, height_max: float, depth_k: float) -> void:
	var layer := _make_layer(layer_name, parallax)
	var mesh := _sphere(1.0, 28, 14)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x := level_start_x - 70.0
	while x < level_end_x + 70.0:
		var w := _rng.randf_range(width_min, width_max)
		var h := _rng.randf_range(height_min, height_max)
		var hill_basis := Basis.from_scale(Vector3(w, h, 6.0 * depth_k))
		xforms.append(Transform3D(hill_basis, Vector3(x, center_y, z + _rng.randf_range(-2.5, 2.5))))
		var c := _shade(base_color, _rng.randf_range(-0.05, 0.06))
		colors.append(_to_linear(c.lerp(haze_color, haze)))
		x += w * _rng.randf_range(0.8, 1.3)
	var mat := _flat_material(0.4)
	layer.add_child(_make_multimesh("Hills", mesh, mat, xforms, colors, false))


# --------------------------------------------------------------------------
# Bamboo
# --------------------------------------------------------------------------

func _build_bamboo(layer_name: String, z_min: float, z_max: float, parallax: float,
		spacing_min: float, spacing_max: float, height_min: float, height_max: float,
		base_color: Color, haze: float, cast_shadows: bool, radius: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var segment := _cylinder(radius * 0.94, radius, SEGMENT_HEIGHT * 0.92, 12)
	var node_ring := _sphere(radius * 1.18, 12, 4)
	var leaf := _leaf_mesh(0.95, 0.2)
	var twig := _cylinder(0.012, 0.02, 1.0, 4)

	var seg_x: Array[Transform3D] = []
	var seg_c: Array[Color] = []
	var ring_x: Array[Transform3D] = []
	var ring_c: Array[Color] = []
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []
	var twig_x: Array[Transform3D] = []
	var twig_c: Array[Color] = []

	var x := level_start_x - 15.0
	while x < level_end_x + 15.0:
		var z := _rng.randf_range(z_min, z_max)
		var height := _rng.randf_range(height_min, height_max)
		var count := int(height / SEGMENT_HEIGHT)
		var lean := _rng.randf_range(-0.04, 0.04)
		var stalk_color := base_color.lerp(Color(0.80, 0.82, 0.35), _rng.randf_range(0.0, 0.35))
		stalk_color = stalk_color.lerp(haze_color, haze)
		var ring_color := stalk_color.darkened(0.18).lerp(Color(0.85, 0.85, 0.6), 0.15)
		for i in count:
			var y := GROUND_Y + SEGMENT_HEIGHT * (float(i) + 0.5)
			var thin := 1.0 - float(i) / float(count) * 0.35       # thinner toward the top
			var off := Vector3(lean * y, 0, 0)
			seg_x.append(Transform3D(Basis.from_scale(Vector3(thin, 1, thin)).rotated(Vector3.BACK, -lean), Vector3(x, y, z) + off))
			# each segment a touch lighter just above its node, like real culms
			seg_c.append(_to_linear(_shade(stalk_color, _rng.randf_range(-0.04, 0.05))))
			var ry := GROUND_Y + SEGMENT_HEIGHT * float(i + 1)
			ring_x.append(Transform3D(Basis.from_scale(Vector3(thin, 0.32, thin)), Vector3(x + lean * ry, ry, z)))
			ring_c.append(_to_linear(ring_color))

		# leafy sprays: a thin twig with a fan of leaves at its end
		var sprays := _rng.randi_range(4, 7)
		for _j in sprays:
			var ly := GROUND_Y + height * _rng.randf_range(0.45, 0.97)
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var yaw := _rng.randf_range(-0.7, 0.7)
			var tw_len := _rng.randf_range(0.5, 1.1)
			var up := _rng.randf_range(0.25, 0.6)
			var dirv := Vector3(side, up, 0).normalized().rotated(Vector3.UP, yaw)
			var base := Vector3(x + lean * ly, ly, z)
			var tip := base + dirv * tw_len
			# cylinders point along Y, so turn Y to the twig direction
			var tbasis := Basis(Quaternion(Vector3.UP, dirv)).scaled(Vector3(1, tw_len, 1))
			twig_x.append(Transform3D(tbasis, base + dirv * tw_len * 0.5))
			twig_c.append(_to_linear(ring_color))
			var nleaves := _rng.randi_range(4, 7)
			for k in nleaves:
				var fan := (float(k) / float(nleaves - 1) - 0.5) * 1.9
				var lb := Basis(Vector3.UP, yaw + (0.0 if side > 0.0 else PI) + _rng.randf_range(-0.3, 0.3))
				lb = lb * Basis(Vector3.BACK, -0.45 + fan * 0.6) * Basis(Vector3.RIGHT, fan * 0.7)
				var sc := _rng.randf_range(0.75, 1.15)
				leaf_x.append(Transform3D(lb.scaled(Vector3(sc, sc, sc)), tip))
				var leaf_color := Color(0.30, 0.62, 0.20).lerp(Color(0.62, 0.86, 0.30), _rng.randf())
				leaf_c.append(_to_linear(leaf_color.lerp(haze_color, haze)))

		x += _rng.randf_range(spacing_min, spacing_max)

	var stalk_mat := _foliage_material(0.0022, 0.45, 0.0, 0.3, 1.2)
	stalk_mat.set_shader_parameter("roughness_value", 0.45)
	layer.add_child(_make_multimesh("Stalks", segment, stalk_mat, seg_x, seg_c, cast_shadows))
	layer.add_child(_make_multimesh("Nodes", node_ring, stalk_mat, ring_x, ring_c, false))
	layer.add_child(_make_multimesh("Twigs", twig, stalk_mat, twig_x, twig_c, false))
	layer.add_child(_make_multimesh("Leaves", leaf, _foliage_material(0.003, 0.3, 0.45, 0.0), leaf_x, leaf_c, cast_shadows))


## A few big stalks right in front of the camera. They frame the view, and fade
## to see-through whenever Flutte (or the action) is behind them.
func _build_foreground_bamboo(layer_name: String, z_min: float, z_max: float) -> void:
	var layer := _make_layer(layer_name, 1.2)
	var sh := Shader.new()
	sh.code = FG_FADE_SHADER
	_fg_fade_mat = ShaderMaterial.new()
	_fg_fade_mat.shader = sh
	var seg := _cylinder(0.2, 0.21, SEGMENT_HEIGHT * 0.93, 14)
	var ring := _sphere(0.25, 14, 4)
	var leaf := _leaf_mesh(1.5, 0.3)
	var sx: Array[Transform3D] = []
	var sc: Array[Color] = []
	var rx: Array[Transform3D] = []
	var rc: Array[Color] = []
	var lx: Array[Transform3D] = []
	var lc: Array[Color] = []
	var x := level_start_x + 8.0
	while x < level_end_x:
		if x > 102.0:
			break                      # keep the boss arena's view clear
		var z := _rng.randf_range(z_min, z_max)
		var col := Color(0.30, 0.55, 0.22).lerp(Color(0.45, 0.66, 0.25), _rng.randf())
		for i in 18:
			var y := GROUND_Y + SEGMENT_HEIGHT * (float(i) + 0.5)
			sx.append(Transform3D(Basis(), Vector3(x, y, z)))
			sc.append(_to_linear(col))
			rx.append(Transform3D(Basis.from_scale(Vector3(1, 0.3, 1)), Vector3(x, y + 0.5, z)))
			rc.append(_to_linear(col.darkened(0.2)))
		for k in 5:
			var ly := _rng.randf_range(5.5, 9.0)
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var lb := Basis(Vector3.UP, 0.0 if side > 0.0 else PI) * Basis(Vector3.BACK, _rng.randf_range(-0.6, 0.1))
			lx.append(Transform3D(lb, Vector3(x, ly, z)))
			lc.append(_to_linear(Color(0.28, 0.55, 0.2).lerp(Color(0.5, 0.75, 0.28), _rng.randf())))
		x += _rng.randf_range(16.0, 26.0)
	layer.add_child(_make_multimesh("Stalks", seg, _fg_fade_mat, sx, sc, false))
	layer.add_child(_make_multimesh("Nodes", ring, _fg_fade_mat, rx, rc, false))
	layer.add_child(_make_multimesh("Leaves", leaf, _fg_fade_mat, lx, lc, false))


const FG_FADE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec4 hide_a = vec4(-10.0);
uniform vec4 hide_b = vec4(-10.0);
float gap(float x, vec4 h) {
	vec4 d = abs(vec4(x) - h);
	float m = min(min(d.x, d.y), min(d.z, d.w));
	return 1.0 - smoothstep(0.06, 0.11, m);
}
void fragment() {
	float near = max(gap(SCREEN_UV.x, hide_a), gap(SCREEN_UV.x, hide_b));
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
	RIM = 0.4;
	RIM_TINT = 0.6;
	ALPHA = 1.0 - near;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""


# --------------------------------------------------------------------------
# Cherry blossom trees (background)
# --------------------------------------------------------------------------

func _build_blossom_trees(layer_name: String, z_min: float, z_max: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var trunk := _cylinder(0.16, 0.34, 1.0, 10)
	var branch := _cylinder(0.05, 0.12, 1.0, 6)
	var puff := _sphere(1.0, 16, 8)
	var petal_spot := _flower_mesh(0.5)

	var trunk_x: Array[Transform3D] = []
	var trunk_c: Array[Color] = []
	var puff_x: Array[Transform3D] = []
	var puff_c: Array[Color] = []
	var spot_x: Array[Transform3D] = []
	var spot_c: Array[Color] = []

	var x := level_start_x + _rng.randf_range(0.0, 6.0)
	while x < level_end_x + 10.0:
		var z := _rng.randf_range(z_min, z_max)
		var h := _rng.randf_range(3.6, 5.5)
		var bark := Color(0.45, 0.30, 0.28).lerp(haze_color, 0.15)
		var bend := _rng.randf_range(-0.12, 0.12)
		trunk_x.append(Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)).rotated(Vector3.BACK, bend), Vector3(x - bend * h * 0.5, GROUND_Y + h * 0.5, z)))
		trunk_c.append(_to_linear(bark))
		var top := Vector3(x - bend * h, GROUND_Y + h, z)
		# 3 branches reaching up and out; each one ends in a cloud of blossom
		var crowns: Array[Vector3] = [top + Vector3(0, 0.6, 0)]
		for b in 3:
			var ang := (float(b) - 1.0) * 0.8 + _rng.randf_range(-0.2, 0.2)
			var blen := _rng.randf_range(1.4, 2.2)
			var dirv := Vector3(sin(ang), cos(ang) * 0.8, _rng.randf_range(-0.3, 0.3)).normalized()
			var start := top - Vector3(0, _rng.randf_range(0.2, 1.0), 0)
			var bb := Basis(Quaternion(Vector3.UP, dirv)).scaled(Vector3(1, blen, 1))
			trunk_x.append(Transform3D(bb, start + dirv * blen * 0.5))
			trunk_c.append(_to_linear(bark.darkened(0.05)))
			crowns.append(start + dirv * blen)
		for c in crowns:
			var puffs := _rng.randi_range(5, 8)
			for _i in puffs:
				var r := _rng.randf_range(0.55, 1.0)
				var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.35, 0.6), _rng.randf_range(-0.6, 0.6))
				puff_x.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.85, r)), c + off))
				var pink := Color(1.0, 0.60, 0.78).lerp(Color(1.0, 0.86, 0.92), _rng.randf())
				puff_c.append(_to_linear(pink.lerp(haze_color, 0.12)))
		# fallen petals on the grass below
		for _p in 7:
			var s := _rng.randf_range(0.6, 1.2)
			spot_x.append(Transform3D(Basis.from_scale(Vector3(s, 0.2, s)).rotated(Vector3.UP, _rng.randf() * TAU),
				Vector3(x + _rng.randf_range(-2.4, 2.4), GROUND_Y + 0.01, z + _rng.randf_range(-1.2, 1.2))))
			spot_c.append(_to_linear(Color(1.0, 0.78, 0.88)))
		x += _rng.randf_range(7.0, 13.0)

	layer.add_child(_make_multimesh("Trunks", trunk, _foliage_material(0.0, 0.3, 0.0, 0.25, 1.0), trunk_x, trunk_c, true))
	layer.add_child(_make_multimesh("Blossoms", puff, _foliage_material(0.0012, 0.55, 0.3, 0.0), puff_x, puff_c, true))
	layer.add_child(_make_multimesh("FallenPetals", petal_spot, _foliage_material(0.0, 0.0, 0.0, 0.0), spot_x, spot_c, false))


# --------------------------------------------------------------------------
# Flower bushes: lumpy round bushes dotted with five-petal flowers
# --------------------------------------------------------------------------

func _build_flower_bushes(layer_name: String, z_min: float, z_max: float, parallax: float,
		spacing_min: float, spacing_max: float, max_h: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var lump := _sphere(1.0, 16, 8)
	var flower := _flower_mesh(0.11)
	var center := _sphere(0.035, 6, 3)

	var bush_x: Array[Transform3D] = []
	var bush_c: Array[Color] = []
	var flower_x: Array[Transform3D] = []
	var flower_c: Array[Color] = []
	var center_x: Array[Transform3D] = []
	var center_c: Array[Color] = []

	var x := level_start_x + _rng.randf_range(0.0, 3.0)
	while x < level_end_x + 10.0:
		var z := _rng.randf_range(z_min, z_max)
		var size := _rng.randf_range(0.7, 1.0) * max_h
		var green := Color(0.28, 0.60, 0.26).lerp(Color(0.46, 0.74, 0.30), _rng.randf())
		var flower_col := Color(1.0, 0.45, 0.68) if _rng.randf() < 0.65 else (Color(1.0, 0.95, 0.98) if _rng.randf() < 0.5 else Color(1.0, 0.82, 0.35))
		var lumps := _rng.randi_range(3, 5)
		for l in lumps:
			var t := float(l) / float(lumps - 1) - 0.5
			var r := size * _rng.randf_range(0.55, 0.8) * (1.0 - absf(t) * 0.6)
			var c := Vector3(x + t * size * 1.6, GROUND_Y + r * 0.6, z + _rng.randf_range(-0.2, 0.2))
			bush_x.append(Transform3D(Basis.from_scale(Vector3(r * 1.1, r * 0.85, r)), c))
			bush_c.append(_to_linear(_shade(green, _rng.randf_range(-0.05, 0.08))))
			var flowers := _rng.randi_range(3, 6)
			for _i in flowers:
				var a := _rng.randf_range(0.0, TAU)
				var e := _rng.randf_range(0.25, 1.35)
				var dirv := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
				if dirv.z < -0.3:
					dirv.z = -dirv.z               # mostly on the side facing the camera
				var p := c + Vector3(dirv.x * r * 1.1, dirv.y * r * 0.85, dirv.z * r)
				var fb := Basis(Quaternion(Vector3.UP, dirv.normalized()))
				var fs := _rng.randf_range(0.8, 1.3) * maxf(0.6, size)
				flower_x.append(Transform3D(fb.scaled(Vector3(fs, fs, fs)), p))
				flower_c.append(_to_linear(flower_col.lerp(Color.WHITE, _rng.randf_range(0.0, 0.3))))
				center_x.append(Transform3D(Basis.from_scale(Vector3(fs, fs, fs)), p + dirv.normalized() * 0.03 * fs))
				center_c.append(_to_linear(Color(1.0, 0.85, 0.3)))
		x += _rng.randf_range(spacing_min, spacing_max)

	layer.add_child(_make_multimesh("Bushes", lump, _foliage_material(0.003, 0.4, 0.15, 0.35, 0.7), bush_x, bush_c, true))
	layer.add_child(_make_multimesh("Flowers", flower, _foliage_material(0.003, 0.2, 0.4, 0.0), flower_x, flower_c, false))
	layer.add_child(_make_multimesh("FlowerCenters", center, _foliage_material(0.003, 0.0, 0.0, 0.0), center_x, center_c, false))


# --------------------------------------------------------------------------
# Grass tufts and stones
# --------------------------------------------------------------------------

func _build_grass(layer_name: String, z_min: float, z_max: float, parallax: float, height: float, density: float) -> void:
	var layer := _make_layer(layer_name, parallax)
	var tuft := _grass_mesh(9, height)
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var x := level_start_x
	while x < level_end_x + 10.0:
		var s := _rng.randf_range(0.7, 1.3)
		xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(x, GROUND_Y, _rng.randf_range(z_min, z_max))))
		col.append(_to_linear(Color(0.40, 0.70, 0.28).lerp(Color(0.62, 0.84, 0.34), _rng.randf())))
		x += _rng.randf_range(0.25, 0.7) / density
	layer.add_child(_make_multimesh("Grass", tuft, _foliage_material(0.02, 0.2, 0.3, 0.0), xf, col, false))


func _build_stones(layer_name: String, z_min: float, z_max: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)
	var stone := _sphere(1.0, 12, 6)
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var x := level_start_x + 3.0
	while x < level_end_x + 10.0:
		for i in _rng.randi_range(1, 3):
			var r := _rng.randf_range(0.12, 0.3)
			xf.append(Transform3D(Basis.from_scale(Vector3(r * 1.4, r * 0.7, r)).rotated(Vector3.UP, _rng.randf() * TAU),
				Vector3(x + float(i) * 0.35, GROUND_Y + r * 0.2, _rng.randf_range(z_min, z_max))))
			col.append(_to_linear(Color(0.72, 0.70, 0.76).lerp(Color(0.86, 0.82, 0.80), _rng.randf())))
		x += _rng.randf_range(4.0, 9.0)
	layer.add_child(_make_multimesh("Stones", stone, _flat_material(0.3), xf, col, true))


## a soft grassy lip along both sides of the dirt path
func _build_path_edge(layer_name: String) -> void:
	var layer := _make_layer(layer_name, 1.0)
	var lump := _sphere(1.0, 12, 6)
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	for side in [-1.35, 1.3]:
		var x := level_start_x
		while x < level_end_x + 10.0:
			var r := _rng.randf_range(0.35, 0.6)
			xf.append(Transform3D(Basis.from_scale(Vector3(r * 1.6, r * 0.32, r * 0.55)), Vector3(x, GROUND_Y, side + _rng.randf_range(-0.08, 0.08))))
			col.append(_to_linear(Color(0.42, 0.72, 0.30).lerp(Color(0.55, 0.80, 0.34), _rng.randf())))
			x += r * 1.8
	layer.add_child(_make_multimesh("PathEdge", lump, _foliage_material(0.0, 0.25, 0.0, 0.2, 0.2), xf, col, false))


## give the ground and the path a painted, slightly patchy look
func _style_ground() -> void:
	var level := get_parent()
	if level == null:
		return
	var ground := level.get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	var path := level.get_node_or_null("Ground/PathMesh") as MeshInstance3D
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	if ground:
		var gm := ShaderMaterial.new()
		gm.shader = sh
		gm.set_shader_parameter("color_a", Color(0.33, 0.62, 0.24))
		gm.set_shader_parameter("color_b", Color(0.50, 0.75, 0.30))
		gm.set_shader_parameter("scale", 0.35)
		ground.material_override = gm
	if path:
		var pm := ShaderMaterial.new()
		pm.shader = sh
		pm.set_shader_parameter("color_a", Color(0.72, 0.55, 0.38))
		pm.set_shader_parameter("color_b", Color(0.84, 0.68, 0.48))
		pm.set_shader_parameter("scale", 1.4)
		pm.set_shader_parameter("edge_soft", 1.0)
		path.material_override = pm


const GROUND_SHADER := """
shader_type spatial;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform float scale = 0.4;
uniform float edge_soft = 0.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz * scale;
	float n = noise(p) * 0.6 + noise(p * 2.7) * 0.3 + noise(p * 7.0) * 0.1;
	vec3 c = mix(color_a.rgb, color_b.rgb, smoothstep(0.3, 0.75, n));
	// little light speckles (pebbles / clover)
	float sp = step(0.93, hash(floor(wpos.xz * 9.0)));
	c = mix(c, c * 1.12, sp * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	if (edge_soft > 0.0) {
		// the path's long edges fade softly into the grass
		float e = 1.0 - smoothstep(0.75, 1.0, abs(UV.y - 0.5) * 2.0);
		ALPHA = e;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ALPHA_HASH_SCALE = 1.0;
	}
}
"""


# --------------------------------------------------------------------------
# Lanterns (glow at night)
# --------------------------------------------------------------------------

func _build_lanterns(layer_name: String, z: float, parallax: float) -> void:
	var layer := _make_layer(layer_name, parallax)

	var post := _cylinder(0.06, 0.08, 1.6, 8)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.40, 0.24, 0.16)
	post.material = post_mat

	var roof := _cylinder(0.02, 0.36, 0.2, 8)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.55, 0.12, 0.10)
	roof.material = roof_mat

	var lamp := _sphere(0.24, 12, 6)
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
		lamp_node.scale = Vector3(1.0, 1.15, 1.0)
		lamp_node.position = Vector3(x, GROUND_Y + 1.78, z)
		layer.add_child(lamp_node)

		var roof_node := MeshInstance3D.new()
		roof_node.mesh = roof
		roof_node.position = Vector3(x, GROUND_Y + 2.1, z)
		layer.add_child(roof_node)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.70, 0.40)
		light.omni_range = 4.5
		light.shadow_enabled = false
		light.position = Vector3(x, GROUND_Y + 1.8, z + 0.6)
		layer.add_child(light)
		_lantern_lights.append(light)

		x += 26.0
