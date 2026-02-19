class_name HighwayGenerator
extends Node3D

class HighwayRoute extends RefCounted:
	var curve: Curve3D
	var height_level: int       # Sequential height index
	var route_type: String      # "ring" or "cross"
	var tube_radius: float
	var speed_limit: float
	var is_loop: bool
	var total_length: float

@export_category("Highway Generation")
@export var generate_highways: bool = true
@export var ring_radii_count: int = 3     # 1=outer, 2=outer+mid, 3=outer+mid+inner
@export var height_levels_per_border: int = 2  # Subdivisions per biome (1=borders only, 2=+midpoints)
@export var cross_angles_count: int = 3   # 1-3 unique hex-safe angles
@export var paired_lanes: bool = true
@export var lane_separation: float = 60.0
@export var tube_radius: float = 40.0
@export var ring_radius_offset: float = 50.0
@export var spire_avoidance_radius: float = 90.0
@export var waypoint_spacing: float = 200.0
@export var y_undulation_amplitude: float = 30.0
@export var default_speed_limit: float = 25.0

@export_category("Debug")
@export var debug_draw_highways: bool = false
@export var debug_draw_height_filter: float = -1.0  # -1 = all, otherwise only near this Y
@export var debug_draw_type_filter: String = ""       # "" = all, "ring" or "cross"

var routes: Array = []  # Array of HighwayRoute
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _debug_container: Node3D = null

# Hex face-center safe angles (perpendicular to vertex directions for pointy-top hex)
const SAFE_CROSS_ANGLES = [0.0, PI / 3.0, 2.0 * PI / 3.0]

func set_seed(seed_value: int):
	_rng.seed = seed_value

func generate(city_gen: CityGenerator):
	if not generate_highways:
		return

	_clear()

	var max_spire_dist = _get_max_spire_radius(city_gen)

	# Calculate all height levels and ring radii
	var heights = _calc_height_levels(city_gen)
	var ring_radii = _calc_ring_radii(max_spire_dist)

	# Generate ring highways
	for h_idx in range(heights.size()):
		var y = heights[h_idx]
		for r_idx in range(ring_radii.size()):
			if not _should_generate_ring(r_idx, h_idx):
				continue
			_generate_ring_pair(city_gen, y, h_idx, ring_radii[r_idx], r_idx, max_spire_dist)

	# Generate cross highways
	var num_angles = mini(cross_angles_count, SAFE_CROSS_ANGLES.size())
	for h_idx in range(heights.size()):
		var y = heights[h_idx]
		for a_idx in range(num_angles):
			_generate_cross_pair(city_gen, y, h_idx, SAFE_CROSS_ANGLES[a_idx], max_spire_dist)

	var ring_count = 0
	var cross_count = 0
	for r in routes:
		if r.route_type == "ring":
			ring_count += 1
		else:
			cross_count += 1
	print("HighwayGenerator: Generated %d routes (%d ring, %d cross) across %d heights, %d ring radii" % [
		routes.size(), ring_count, cross_count, heights.size(), ring_radii.size()])

	if debug_draw_highways:
		_draw_debug()

func _clear():
	routes.clear()
	if _debug_container:
		_debug_container.queue_free()
		_debug_container = null

# --- Height and radius calculation ---

func _calc_height_levels(city_gen: CityGenerator) -> Array[float]:
	var heights: Array[float] = []
	var total_sub = city_gen.biome_count * height_levels_per_border
	var spacing = city_gen.spire_height / total_sub
	var max_y = city_gen.spire_height * float(city_gen.biome_count - 1) / city_gen.biome_count
	for i in range(1, total_sub):
		var y = spacing * i
		if y <= max_y:
			heights.append(y)
	return heights

func _calc_ring_radii(max_spire_dist: float) -> Array[float]:
	var radii: Array[float] = []
	radii.append(max_spire_dist + ring_radius_offset)  # Outer — clear of all spires
	if ring_radii_count >= 2:
		radii.append(max_spire_dist * 0.6)  # Mid — between hex ring 1 and 2
	if ring_radii_count >= 3:
		radii.append(max_spire_dist * 0.3)  # Inner — between center and hex ring 1
	return radii

func _should_generate_ring(radius_idx: int, height_idx: int) -> bool:
	# Density falloff: inner rings get fewer height levels
	match radius_idx:
		0: return true                   # Outer: all heights
		1: return height_idx % 2 == 0    # Mid: every other
		2: return height_idx % 3 == 0    # Inner: every 3rd
	return true

func _get_max_spire_radius(city_gen: CityGenerator) -> float:
	var max_dist = 0.0
	for pos in city_gen.spire_positions:
		var dist = Vector2(pos.x, pos.z).length()
		if dist > max_dist:
			max_dist = dist
	return max_dist

# --- Avoidance parameters per ring tier ---

func _avoidance_strength(radius_idx: int, max_spire_dist: float, radius: float) -> float:
	var fraction = clampf(radius / (max_spire_dist + ring_radius_offset), 0.0, 1.0)
	return 1.0 + (1.0 - fraction) * 2.0  # Inner=3x, outer=1x

func _avoidance_passes(radius_idx: int) -> int:
	if radius_idx == 0:
		return 1
	if radius_idx == 1:
		return 2
	return 3

func _spacing_for_radius(radius_idx: int) -> float:
	# Tighter spacing for interior rings (more obstacles to weave through)
	if radius_idx == 0:
		return waypoint_spacing
	return waypoint_spacing * 0.7

# --- Ring highway generation ---

func _generate_ring_pair(city_gen: CityGenerator, y: float, h_idx: int, radius: float, r_idx: int, max_spire_dist: float):
	var strength = _avoidance_strength(r_idx, max_spire_dist, radius)
	var passes = _avoidance_passes(r_idx)
	var spacing = _spacing_for_radius(r_idx)

	if paired_lanes:
		var r_inner = radius - lane_separation * 0.5
		var r_outer = radius + lane_separation * 0.5

		var pts_a = _generate_ring_points(city_gen, y, r_inner, spacing, strength, passes)
		_add_route(_build_loop_curve(pts_a), h_idx, "ring")

		var pts_b = _generate_ring_points(city_gen, y, r_outer, spacing, strength, passes)
		pts_b.reverse()
		_add_route(_build_loop_curve(pts_b), h_idx, "ring")
	else:
		var pts = _generate_ring_points(city_gen, y, radius, spacing, strength, passes)
		_add_route(_build_loop_curve(pts), h_idx, "ring")

func _generate_ring_points(city_gen: CityGenerator, base_y: float, radius: float,
		spacing: float, strength: float, passes: int) -> Array[Vector3]:
	var circumference = TAU * radius
	var num_points = maxi(12, int(circumference / spacing))
	var phase = _rng.randf() * TAU
	var points: Array[Vector3] = []

	for i in range(num_points):
		var angle = TAU * i / num_points
		var x = cos(angle) * radius
		var z = sin(angle) * radius

		var y_offset = sin(angle * 3.0 + phase) * y_undulation_amplitude * 0.7 \
			+ sin(angle * 7.0 + phase * 2.3) * y_undulation_amplitude * 0.3
		var y = base_y + y_offset

		var point = Vector3(x, y, z)
		for p in range(passes):
			point = _avoid_spires(point, city_gen.spire_positions, strength)
		points.append(point)

	return points

# --- Cross highway generation ---

func _generate_cross_pair(city_gen: CityGenerator, y: float, h_idx: int, angle: float, max_spire_dist: float):
	var extent = max_spire_dist + ring_radius_offset + 100.0
	var strength = _avoidance_strength(0, max_spire_dist, extent)
	var passes = 1

	var center_pts = _generate_cross_points(city_gen, y, angle, extent, strength, passes)

	if paired_lanes:
		var perp = Vector3(-sin(angle), 0, cos(angle))
		var offset = perp * lane_separation * 0.5

		var pts_a: Array[Vector3] = []
		for pt in center_pts:
			pts_a.append(pt + offset)
		_add_route(_build_open_curve(pts_a), h_idx, "cross")

		var pts_b: Array[Vector3] = []
		for pt in center_pts:
			pts_b.append(pt - offset)
		pts_b.reverse()
		_add_route(_build_open_curve(pts_b), h_idx, "cross")
	else:
		_add_route(_build_open_curve(center_pts), h_idx, "cross")

func _generate_cross_points(city_gen: CityGenerator, base_y: float, direction_angle: float,
		extent: float, strength: float, passes: int) -> Array[Vector3]:
	var dir = Vector2(cos(direction_angle), sin(direction_angle))
	var start_2d = -dir * extent
	var end_2d = dir * extent

	var total_dist = start_2d.distance_to(end_2d)
	var num_segments = maxi(4, int(total_dist / waypoint_spacing))

	var phase = _rng.randf() * TAU
	var points: Array[Vector3] = []

	for i in range(num_segments + 1):
		var t = float(i) / num_segments
		var pos_2d = start_2d.lerp(end_2d, t)

		var center_weight = sin(t * PI)
		var y_offset = sin(t * PI * 4.0 + phase) * y_undulation_amplitude * center_weight
		var y = base_y + y_offset

		var point = Vector3(pos_2d.x, y, pos_2d.y)
		for p in range(passes):
			point = _avoid_spires(point, city_gen.spire_positions, strength)
		points.append(point)

	return points

# --- Route creation helpers ---

func _add_route(curve: Curve3D, h_idx: int, type: String):
	if not curve:
		return
	var route = HighwayRoute.new()
	route.curve = curve
	route.height_level = h_idx
	route.route_type = type
	route.tube_radius = tube_radius
	route.speed_limit = default_speed_limit
	route.is_loop = (type == "ring")
	route.total_length = curve.get_baked_length()
	routes.append(route)

func _build_loop_curve(points: Array[Vector3]) -> Curve3D:
	if points.size() < 3:
		return null

	var curve = Curve3D.new()
	for i in range(points.size()):
		var prev_idx = (i - 1 + points.size()) % points.size()
		var next_idx = (i + 1) % points.size()
		var tangent = (points[next_idx] - points[prev_idx]).normalized()
		var handle_len = points[i].distance_to(points[next_idx]) * 0.33
		curve.add_point(points[i], -tangent * handle_len, tangent * handle_len)

	# Close the loop by duplicating first point
	var p0 = points[0]
	var close_tangent = (points[1] - points[points.size() - 1]).normalized()
	var close_len = p0.distance_to(points[1]) * 0.33
	curve.add_point(p0, -close_tangent * close_len, close_tangent * close_len)

	return curve

func _build_open_curve(points: Array[Vector3]) -> Curve3D:
	if points.size() < 2:
		return null

	var curve = Curve3D.new()
	for i in range(points.size()):
		var in_handle = Vector3.ZERO
		var out_handle = Vector3.ZERO

		if i > 0 and i < points.size() - 1:
			var tangent = (points[i + 1] - points[i - 1]).normalized()
			var handle_len = points[i].distance_to(points[i + 1]) * 0.33
			in_handle = -tangent * handle_len
			out_handle = tangent * handle_len
		elif i == 0:
			var tangent = (points[1] - points[0]).normalized()
			out_handle = tangent * points[0].distance_to(points[1]) * 0.33
		else:  # last point
			var tangent = (points[i] - points[i - 1]).normalized()
			in_handle = -tangent * points[i - 1].distance_to(points[i]) * 0.33

		curve.add_point(points[i], in_handle, out_handle)

	return curve

# --- Spire avoidance ---

func _avoid_spires(point: Vector3, spires: Array[Vector3], strength: float = 1.0) -> Vector3:
	var result = point
	var effective_radius = spire_avoidance_radius * strength
	for spire_pos in spires:
		var spire_xz = Vector2(spire_pos.x, spire_pos.z)
		var point_xz = Vector2(result.x, result.z)
		var dist = point_xz.distance_to(spire_xz)

		if dist < effective_radius:
			var away = point_xz - spire_xz
			if away.length() < 0.01:
				away = Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5)
			away = away.normalized()
			var push = effective_radius - dist + 10.0
			result.x += away.x * push
			result.z += away.y * push

	return result

# --- Debug visualization ---

func _draw_debug():
	if _debug_container:
		_debug_container.queue_free()

	_debug_container = Node3D.new()
	_debug_container.name = "HighwayDebug"
	add_child(_debug_container)

	var height_tolerance = 50.0
	var drawn = 0

	for route in routes:
		# Type filter
		if debug_draw_type_filter != "" and route.route_type != debug_draw_type_filter:
			continue

		# Height filter — check first curve point's Y
		if debug_draw_height_filter >= 0.0:
			if route.curve.point_count == 0:
				continue
			var route_y = route.curve.get_point_position(0).y
			if absf(route_y - debug_draw_height_filter) > height_tolerance:
				continue

		var color = Color.DODGER_BLUE if route.route_type == "ring" else Color.ORANGE
		_draw_curve_line(route.curve, color)
		for p_idx in range(route.curve.point_count):
			_draw_waypoint_sphere(route.curve.get_point_position(p_idx), color)
		drawn += 1

	print("HighwayGenerator: Debug drew %d / %d routes" % [drawn, routes.size()])

func _draw_curve_line(curve: Curve3D, color: Color):
	var baked_length = curve.get_baked_length()
	if baked_length < 1.0:
		return

	var step = 10.0
	var num_samples = int(baked_length / step)
	if num_samples < 2:
		return

	var im = ImmediateMesh.new()
	var mi = MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in range(num_samples + 1):
		var offset = minf(step * i, baked_length)
		im.surface_add_vertex(curve.sample_baked(offset))
	im.surface_end()

	_debug_container.add_child(mi)

func _draw_waypoint_sphere(pos: Vector3, color: Color):
	var mi = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
	sphere.radial_segments = 6
	sphere.rings = 2
	mi.mesh = sphere
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat

	_debug_container.add_child(mi)
