class_name HighwayGenerator
extends Node3D

class HighwayRoute extends RefCounted:
	var curve: Curve3D
	var height_level: int       # Biome border index (1, 2, 3...)
	var route_type: String      # "ring" or "cross"
	var tube_radius: float
	var speed_limit: float
	var is_loop: bool
	var total_length: float

@export_category("Highway Generation")
@export var generate_highways: bool = true
@export var ring_highways_per_border: int = 1
@export var cross_highway_count: int = 2
@export var tube_radius: float = 40.0
@export var ring_radius_offset: float = 50.0
@export var spire_avoidance_radius: float = 90.0
@export var waypoint_spacing: float = 200.0
@export var y_undulation_amplitude: float = 30.0
@export var default_speed_limit: float = 25.0

@export_category("Debug")
@export var debug_draw_highways: bool = false

var routes: Array = []  # Array of HighwayRoute
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _debug_container: Node3D = null

func set_seed(seed_value: int):
	_rng.seed = seed_value

func generate(city_gen: CityGenerator):
	if not generate_highways:
		return

	_clear()

	var biome_height = city_gen.spire_height / city_gen.biome_count

	# Ring highways at each biome border (skip ground level border 0)
	for border_idx in range(1, city_gen.biome_count):
		var border_y = biome_height * border_idx
		for i in range(ring_highways_per_border):
			var route = _generate_ring_highway(city_gen, border_y, border_idx, i)
			if route:
				routes.append(route)

	# Cross highways along hex face-center directions (safe angles that avoid spires)
	# Pointy-top hex has vertices at 30°+n*60°, so face-centers are at n*60° (0°, 60°, 120°)
	var safe_angles = [0.0, PI / 3.0, 2.0 * PI / 3.0]
	for i in range(cross_highway_count):
		var border_idx = (i % (city_gen.biome_count - 1)) + 1
		var border_y = biome_height * border_idx
		var angle = safe_angles[i % safe_angles.size()]
		var route = _generate_cross_highway(city_gen, border_y, border_idx, angle)
		if route:
			routes.append(route)

	var ring_count = 0
	var cross_count = 0
	for r in routes:
		if r.route_type == "ring":
			ring_count += 1
		else:
			cross_count += 1
	print("HighwayGenerator: Generated %d routes (%d ring, %d cross)" % [routes.size(), ring_count, cross_count])

	if debug_draw_highways:
		_draw_debug()

func _clear():
	routes.clear()
	if _debug_container:
		_debug_container.queue_free()
		_debug_container = null

func _get_max_spire_radius(city_gen: CityGenerator) -> float:
	var max_dist = 0.0
	for pos in city_gen.spire_positions:
		var dist = Vector2(pos.x, pos.z).length()
		if dist > max_dist:
			max_dist = dist
	return max_dist

func _generate_ring_highway(city_gen: CityGenerator, base_y: float, border_idx: int, ring_index: int) -> HighwayRoute:
	var max_spire_dist = _get_max_spire_radius(city_gen)
	var ring_radius = max_spire_dist + ring_radius_offset + ring_index * tube_radius * 2.5

	var circumference = TAU * ring_radius
	var num_points = maxi(12, int(circumference / waypoint_spacing))

	# Phase offset for organic undulation
	var phase = _rng.randf() * TAU

	var points: Array[Vector3] = []

	for i in range(num_points):
		var angle = TAU * i / num_points
		var x = cos(angle) * ring_radius
		var z = sin(angle) * ring_radius

		# Multi-frequency Y undulation for organic feel
		var y_offset = sin(angle * 3.0 + phase) * y_undulation_amplitude * 0.7 \
			+ sin(angle * 7.0 + phase * 2.3) * y_undulation_amplitude * 0.3
		var y = base_y + y_offset

		var point = Vector3(x, y, z)
		point = _avoid_spires(point, city_gen.spire_positions)
		points.append(point)

	# Build Curve3D with smooth handles and loop closure
	var curve = Curve3D.new()

	for i in range(points.size()):
		var prev_idx = (i - 1 + points.size()) % points.size()
		var next_idx = (i + 1) % points.size()

		var to_next = points[next_idx] - points[i]
		var to_prev = points[prev_idx] - points[i]
		var tangent = (to_next - to_prev).normalized()
		var handle_len = points[i].distance_to(points[next_idx]) * 0.33

		curve.add_point(points[i], -tangent * handle_len, tangent * handle_len)

	# Close the loop by duplicating first point at the end
	var p0 = points[0]
	var prev_last = points[points.size() - 1]
	var next_first = points[1]
	var close_tangent = (next_first - prev_last).normalized()
	var close_handle_len = p0.distance_to(next_first) * 0.33
	curve.add_point(p0, -close_tangent * close_handle_len, close_tangent * close_handle_len)

	var route = HighwayRoute.new()
	route.curve = curve
	route.height_level = border_idx
	route.route_type = "ring"
	route.tube_radius = tube_radius
	route.speed_limit = default_speed_limit
	route.is_loop = true
	route.total_length = curve.get_baked_length()

	print("  Ring highway at y=%.0f, radius=%.0f, %d points, length=%.0fm" % [
		base_y, ring_radius, num_points, route.total_length])

	return route

func _generate_cross_highway(city_gen: CityGenerator, base_y: float, border_idx: int, direction_angle: float) -> HighwayRoute:
	var max_spire_dist = _get_max_spire_radius(city_gen)
	var extent = max_spire_dist + ring_radius_offset + 100.0

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

		# Y undulation — gentler near endpoints, stronger in the middle
		var center_weight = sin(t * PI)  # 0 at ends, 1 at middle
		var y_offset = sin(t * PI * 4.0 + phase) * y_undulation_amplitude * center_weight
		var y = base_y + y_offset

		var point = Vector3(pos_2d.x, y, pos_2d.y)
		point = _avoid_spires(point, city_gen.spire_positions)
		points.append(point)

	# Build Curve3D with smooth handles (open-ended)
	var curve = Curve3D.new()

	for i in range(points.size()):
		var in_handle = Vector3.ZERO
		var out_handle = Vector3.ZERO

		if i > 0 and i < points.size() - 1:
			var to_next = points[i + 1] - points[i]
			var to_prev = points[i - 1] - points[i]
			var tangent = (to_next - to_prev).normalized()
			var handle_len = points[i].distance_to(points[i + 1]) * 0.33
			in_handle = -tangent * handle_len
			out_handle = tangent * handle_len
		elif i == 0 and points.size() > 1:
			var tangent = (points[1] - points[0]).normalized()
			var handle_len = points[0].distance_to(points[1]) * 0.33
			out_handle = tangent * handle_len
		elif i == points.size() - 1 and points.size() > 1:
			var tangent = (points[i] - points[i - 1]).normalized()
			var handle_len = points[i - 1].distance_to(points[i]) * 0.33
			in_handle = -tangent * handle_len

		curve.add_point(points[i], in_handle, out_handle)

	var route = HighwayRoute.new()
	route.curve = curve
	route.height_level = border_idx
	route.route_type = "cross"
	route.tube_radius = tube_radius
	route.speed_limit = default_speed_limit
	route.is_loop = false
	route.total_length = curve.get_baked_length()

	print("  Cross highway at y=%.0f, angle=%.0f°, %d points, length=%.0fm" % [
		base_y, rad_to_deg(direction_angle), points.size(), route.total_length])

	return route

func _avoid_spires(point: Vector3, spires: Array[Vector3]) -> Vector3:
	var result = point
	for spire_pos in spires:
		var spire_xz = Vector2(spire_pos.x, spire_pos.z)
		var point_xz = Vector2(result.x, result.z)
		var dist = point_xz.distance_to(spire_xz)

		if dist < spire_avoidance_radius:
			var away = point_xz - spire_xz
			if away.length() < 0.01:
				away = Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5)
			away = away.normalized()
			var push = spire_avoidance_radius - dist + 10.0
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

	for route in routes:
		var color = Color.DODGER_BLUE if route.route_type == "ring" else Color.ORANGE
		_draw_curve_line(route.curve, color)
		for p_idx in range(route.curve.point_count):
			_draw_waypoint_sphere(route.curve.get_point_position(p_idx), color)

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
