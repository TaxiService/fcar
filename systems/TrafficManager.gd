class_name TrafficManager
extends Node

@export_category("Pool")
@export var pool_size: int = 60
@export var max_active_cars: int = 60

@export_category("Rendering")
@export var car_spacing: float = 80.0
@export var close_car_distance: float = 150.0
@export var max_render_distance: float = 1000.0

@export_category("LOD")
@export var rotation_update_radius: float = 200.0

var _pool: Array[TrafficCar] = []
var _active_cars: Array[TrafficCar] = []
var _car_scene: PackedScene = null
var _routes: Array = []  # HighwayGenerator.HighwayRoute refs
var _pool_ready: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Per-route slot tracking: route_index -> Array of slot car refs (null = empty)
var _route_slots: Dictionary = {}

# Squared radii for fast distance checks
var _close_dist_sq: float
var _close_despawn_dist_sq: float  # Slightly larger than close for hysteresis
var _max_render_dist_sq: float
var _rotation_radius_sq: float

# --- Data-oriented car arrays (one entry per car slot across all routes) ---
var _car_count: int = 0
var _car_route_idx: PackedInt32Array
var _car_curve_offset: PackedFloat32Array
var _car_speed: PackedFloat32Array
var _car_target_speed: PackedFloat32Array
var _car_tube_offset_x: PackedFloat32Array
var _car_tube_offset_y: PackedFloat32Array
var _car_state: PackedInt32Array            # 0=cruising, 1=disturbed
var _car_disturbed_timer: PackedFloat32Array
var _car_disturbed_vx: PackedFloat32Array
var _car_disturbed_vy: PackedFloat32Array
var _car_disturbed_vz: PackedFloat32Array
var _car_collision_cooldown: PackedFloat32Array
var _car_world_pos: PackedVector3Array
var _car_color: PackedColorArray
var _car_visible: PackedByteArray           # 0=hidden, 1=mid-range (multimesh), 2=close (node pool)
var _car_tangent: PackedVector3Array        # Cached tangent for extrapolation and rotation

# Mapping from data_index -> assigned TrafficCar node (null if no node assigned)
var _car_node_map: Array = []

const CAR_STATE_CRUISING: int = 0
const CAR_STATE_DISTURBED: int = 1
const DISTURBED_DURATION: float = 2.0

# --- MultiMesh ---
var _multimesh: MultiMesh
var _multimesh_instance: MultiMeshInstance3D

# Frame counter for staggered curve sampling
var _frame_counter: int = 0

func _ready():
	CityGrid.traffic_manager = self
	_close_dist_sq = close_car_distance * close_car_distance
	var despawn_dist = close_car_distance * 1.4
	_close_despawn_dist_sq = despawn_dist * despawn_dist
	_max_render_dist_sq = max_render_distance * max_render_distance
	_rotation_radius_sq = rotation_update_radius * rotation_update_radius
	_car_scene = load("res://city/cars/redsand.tscn")
	_rng.seed = hash("traffic") + int(Time.get_unix_time_from_system()) % 10000
	_setup_multimesh()
	call_deferred("_warm_pool")

func _setup_multimesh():
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = 0

	var mesh = BoxMesh.new()
	mesh.size = Vector3(2.0, 0.8, 4.0)
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_multimesh.mesh = mesh

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)

func _warm_pool():
	for i in range(pool_size):
		var car = _create_pooled_car()
		_pool.append(car)
		if i % 20 == 19:
			await get_tree().process_frame
	_pool_ready = true
	print("TrafficManager: Pool ready (%d cars)" % _pool.size())

	# Wait for city generation to complete before loading routes
	var cg = CityGrid.city_generator
	if cg:
		if not cg.is_node_ready():
			await cg.ready
		# If highways already generated, load now; otherwise wait for signal
		var hg = CityGrid.highway_generator
		if hg and not hg.routes.is_empty():
			_load_routes()
		else:
			cg.city_generation_complete.connect(_load_routes, CONNECT_ONE_SHOT)
	else:
		push_warning("TrafficManager: No CityGenerator found")

func _create_pooled_car() -> TrafficCar:
	var car = TrafficCar.new()
	car.name = "TrafficCar_%d" % get_child_count()
	var visual = _car_scene.instantiate()
	car.set_visual(visual)
	car.visible = false
	add_child(car)
	return car

func _load_routes():
	var hg = CityGrid.highway_generator
	if not hg or hg.routes.is_empty():
		print("TrafficManager: No highway routes available")
		return

	_routes = hg.routes
	# Initialize slot arrays per route (kept for spawn tracking)
	var total_slots = 0
	for i in range(_routes.size()):
		var route = _routes[i]
		var slot_count = maxi(1, int(route.total_length / car_spacing))
		var slots: Array = []
		slots.resize(slot_count)
		slots.fill(null)
		_route_slots[i] = slots
		total_slots += slot_count

	print("TrafficManager: Loaded %d routes, %d total slots (%.0fm spacing)" % [_routes.size(), total_slots, car_spacing])

	_initialize_car_data()

func _initialize_car_data():
	# Count total slots across all routes
	_car_count = 0
	for route in _routes:
		_car_count += maxi(1, int(route.total_length / car_spacing))

	# Resize all parallel arrays
	_car_route_idx.resize(_car_count)
	_car_curve_offset.resize(_car_count)
	_car_speed.resize(_car_count)
	_car_target_speed.resize(_car_count)
	_car_tube_offset_x.resize(_car_count)
	_car_tube_offset_y.resize(_car_count)
	_car_state.resize(_car_count)
	_car_disturbed_timer.resize(_car_count)
	_car_disturbed_vx.resize(_car_count)
	_car_disturbed_vy.resize(_car_count)
	_car_disturbed_vz.resize(_car_count)
	_car_collision_cooldown.resize(_car_count)
	_car_world_pos.resize(_car_count)
	_car_color.resize(_car_count)
	_car_visible.resize(_car_count)
	_car_visible.fill(0)
	_car_tangent.resize(_car_count)

	_car_node_map.resize(_car_count)
	_car_node_map.fill(null)

	# Fill initial data
	var idx = 0
	for route_i in range(_routes.size()):
		var route = _routes[route_i]
		var slots = maxi(1, int(route.total_length / car_spacing))
		for s in range(slots):
			_car_route_idx[idx] = route_i
			var offset = route.total_length * s / float(slots)
			_car_curve_offset[idx] = offset
			var spd = route.speed_limit * _rng.randf_range(0.85, 1.15)
			_car_speed[idx] = spd
			_car_target_speed[idx] = spd
			_car_state[idx] = CAR_STATE_CRUISING
			_car_disturbed_timer[idx] = 0.0
			_car_disturbed_vx[idx] = 0.0
			_car_disturbed_vy[idx] = 0.0
			_car_disturbed_vz[idx] = 0.0
			_car_collision_cooldown[idx] = 0.0

			var angle = _rng.randf() * TAU
			var dist = _rng.randf() * route.tube_radius * 0.7
			_car_tube_offset_x[idx] = cos(angle) * dist
			_car_tube_offset_y[idx] = sin(angle) * dist * 0.3

			_car_color[idx] = Color.from_hsv(_rng.randf(), _rng.randf_range(0.3, 0.7), _rng.randf_range(0.5, 0.9))

			# Compute initial world position and tangent
			var curve_pos = route.curve.sample_baked(offset)
			_car_world_pos[idx] = curve_pos + Vector3(_car_tube_offset_x[idx], _car_tube_offset_y[idx], 0)
			var next_offset = minf(offset + 5.0, route.total_length - 0.1)
			var next_pos = route.curve.sample_baked(next_offset)
			var tangent = (next_pos - curve_pos).normalized()
			if tangent.length_squared() > 0.001:
				_car_tangent[idx] = tangent
			else:
				_car_tangent[idx] = Vector3.FORWARD

			idx += 1

	print("TrafficManager: Initialized %d car slots across %d routes" % [_car_count, _routes.size()])

func get_active_cars() -> Array[TrafficCar]:
	return _active_cars

func get_close_car_data() -> Array:
	return _car_node_map

func get_car_count() -> int:
	return _car_count

func get_car_world_pos(data_index: int) -> Vector3:
	return _car_world_pos[data_index]

func get_car_collision_cooldown(data_index: int) -> float:
	return _car_collision_cooldown[data_index]

func apply_car_disturbance(data_index: int, velocity: Vector3):
	_car_state[data_index] = CAR_STATE_DISTURBED
	_car_disturbed_timer[data_index] = 0.0
	_car_disturbed_vx[data_index] = velocity.x
	_car_disturbed_vy[data_index] = velocity.y
	_car_disturbed_vz[data_index] = velocity.z
	_car_collision_cooldown[data_index] = 1.5

func _acquire_from_pool() -> TrafficCar:
	if _pool.is_empty():
		return null
	return _pool.pop_back()

func _return_to_pool(car: TrafficCar):
	if not is_instance_valid(car):
		return
	# Clear slot in route_slots
	if car.route_index >= 0 and _route_slots.has(car.route_index):
		var slots = _route_slots[car.route_index]
		if car.slot_index >= 0 and car.slot_index < slots.size():
			slots[car.slot_index] = null
	# Clear node map entry
	if car.data_index >= 0 and car.data_index < _car_count:
		_car_node_map[car.data_index] = null
	car.deactivate()
	_active_cars.erase(car)
	_pool.append(car)

func _process(delta: float):
	if not _pool_ready or _car_count == 0:
		return

	var cam = TrafficCar.lod_camera
	if not cam:
		cam = get_viewport().get_camera_3d()
		if cam:
			TrafficCar.lod_camera = cam
	if not cam:
		return

	var cam_pos = cam.global_position

	# Step 1: Advance all car offsets (cheap float math)
	_advance_all_cars(delta)

	# Step 2: Compute positions and visibility tiers
	_compute_visible_positions(cam_pos, delta)

	# Step 3: Spawn/despawn close pool based on tiers
	_update_spawning()

	# Step 4: Sync array state back to active nodes
	_sync_arrays_to_nodes(cam_pos)

	# Step 5: Update MultiMesh for mid-range rendering
	_update_multimesh()

	_frame_counter += 1

func _advance_all_cars(delta: float):
	for i in range(_car_count):
		if _car_collision_cooldown[i] > 0:
			_car_collision_cooldown[i] -= delta

		if _car_state[i] == CAR_STATE_CRUISING:
			_car_curve_offset[i] += _car_speed[i] * delta
			var route = _routes[_car_route_idx[i]]
			if route.is_loop:
				_car_curve_offset[i] = fmod(_car_curve_offset[i], route.total_length)
				if _car_curve_offset[i] < 0:
					_car_curve_offset[i] += route.total_length
			else:
				if _car_curve_offset[i] >= route.total_length:
					_car_curve_offset[i] = fmod(_car_curve_offset[i], route.total_length)
		else:  # DISTURBED
			_car_disturbed_timer[i] += delta
			if _car_disturbed_timer[i] >= DISTURBED_DURATION:
				_car_state[i] = CAR_STATE_CRUISING
				_car_disturbed_timer[i] = 0.0
				_car_speed[i] = _car_target_speed[i]
			else:
				# Advance along curve at half speed while disturbed
				var route = _routes[_car_route_idx[i]]
				_car_curve_offset[i] += _car_target_speed[i] * delta * 0.5
				if route.is_loop:
					_car_curve_offset[i] = fmod(_car_curve_offset[i], route.total_length)
			_car_disturbed_vx[i] *= 0.95
			_car_disturbed_vy[i] *= 0.95
			_car_disturbed_vz[i] *= 0.95

func _compute_visible_positions(cam_pos: Vector3, delta: float):
	for i in range(_car_count):
		# Use previous frame's world_pos for distance (avoids sampling hidden cars)
		var dist_sq = cam_pos.distance_squared_to(_car_world_pos[i])
		var needs_sample = false

		if dist_sq < _close_dist_sq:
			_car_visible[i] = 2  # Close — Node3D pool
			needs_sample = true
		elif dist_sq < _max_render_dist_sq:
			# Keep existing node assignment in hysteresis buffer zone
			if _car_node_map[i] != null and dist_sq < _close_despawn_dist_sq:
				_car_visible[i] = 2  # Still close — keep node
				needs_sample = true
			else:
				_car_visible[i] = 1  # Mid-range — MultiMesh
				# Sample every 3rd frame (staggered by index)
				needs_sample = (_frame_counter % 3 == i % 3)
		else:
			_car_visible[i] = 0  # Hidden
			# Periodic resample to catch drift (staggered across 60 frames)
			needs_sample = (_frame_counter % 60 == i % 60)

		# Always sample disturbed cars for accurate visual
		if _car_state[i] == CAR_STATE_DISTURBED:
			needs_sample = true

		if needs_sample:
			var route = _routes[_car_route_idx[i]]
			var offset = _car_curve_offset[i]
			var curve_pos = route.curve.sample_baked(offset)
			var world_pos = curve_pos + Vector3(_car_tube_offset_x[i], _car_tube_offset_y[i], 0)

			if _car_state[i] == CAR_STATE_DISTURBED:
				var blend = _car_disturbed_timer[i] / DISTURBED_DURATION
				var t = ease(blend, 0.3)
				var disturbed_offset = Vector3(
					_car_disturbed_vx[i], _car_disturbed_vy[i], _car_disturbed_vz[i]
				) * (1.0 - t) * 0.5
				world_pos += disturbed_offset

			_car_world_pos[i] = world_pos

			# Compute and cache tangent for extrapolation and rotation
			var next_offset = minf(offset + 5.0, route.total_length - 0.1)
			var next_pos = route.curve.sample_baked(next_offset)
			var tangent = (next_pos - curve_pos).normalized()
			if tangent.length_squared() > 0.001:
				_car_tangent[i] = tangent
		elif _car_visible[i] >= 1:
			# Extrapolate position along cached tangent
			_car_world_pos[i] += _car_tangent[i] * _car_speed[i] * delta

func _update_spawning():
	# Despawn nodes that are no longer tier 2
	var i = _active_cars.size() - 1
	while i >= 0:
		var car = _active_cars[i]
		if car.data_index < 0 or car.data_index >= _car_count or _car_visible[car.data_index] != 2:
			_return_to_pool(car)
		i -= 1

	# Spawn nodes for tier 2 cars that don't have one
	if _active_cars.size() >= max_active_cars:
		return

	for di in range(_car_count):
		if _active_cars.size() >= max_active_cars:
			return
		if _car_visible[di] != 2:
			continue
		if _car_node_map[di] != null:
			continue
		_spawn_node_for_data(di)

func _spawn_node_for_data(data_idx: int):
	var car = _acquire_from_pool()
	if not car:
		return

	var route_idx = _car_route_idx[data_idx]
	var route = _routes[route_idx]

	# Determine which slot this data_idx maps to within the route
	var route_start = 0
	for ri in range(route_idx):
		route_start += maxi(1, int(_routes[ri].total_length / car_spacing))
	var slot_idx = data_idx - route_start

	var tube_off = Vector3(_car_tube_offset_x[data_idx], _car_tube_offset_y[data_idx], 0)

	car.data_index = data_idx
	car.slot_index = slot_idx
	car.activate(route_idx, _car_curve_offset[data_idx], tube_off, _car_speed[data_idx])

	# Set position from precomputed world pos
	car.global_position = _car_world_pos[data_idx]

	# Set initial facing from cached tangent
	var tangent = _car_tangent[data_idx]
	if tangent.length_squared() > 0.001:
		car.facing_direction = tangent
		car.look_at(car.global_position + tangent, Vector3.UP)

	_active_cars.append(car)
	_car_node_map[data_idx] = car

	# Also update route_slots for backward compat
	if _route_slots.has(route_idx) and slot_idx >= 0 and slot_idx < _route_slots[route_idx].size():
		_route_slots[route_idx][slot_idx] = car

func _sync_arrays_to_nodes(cam_pos: Vector3):
	for car in _active_cars:
		var di = car.data_index
		if di < 0 or di >= _car_count:
			continue

		# Position node from authoritative array data
		car.global_position = _car_world_pos[di]

		# Update rotation for nearby cars using cached tangent
		var dist_sq = car.global_position.distance_squared_to(cam_pos)
		if dist_sq < _rotation_radius_sq:
			var tangent = _car_tangent[di]
			if tangent.length_squared() > 0.001:
				car.facing_direction = tangent
				car.look_at(car.global_position + tangent, Vector3.UP)

		car.visible = true  # Always visible — pool only holds close-range cars

func _update_multimesh():
	# Count cars that need multimesh rendering (visible but no node assigned)
	var mm_count = 0
	for i in range(_car_count):
		if _car_visible[i] >= 1 and _car_node_map[i] == null:
			mm_count += 1

	# Resize multimesh if needed (only grow, with padding)
	if mm_count > _multimesh.instance_count:
		_multimesh.instance_count = mm_count + 100

	# Write transforms and colors
	var write_idx = 0
	for i in range(_car_count):
		if _car_visible[i] < 1 or _car_node_map[i] != null:
			continue

		var pos = _car_world_pos[i]
		var tangent = _car_tangent[i]

		var xform = Transform3D()
		if tangent.length_squared() > 0.001:
			var up = Vector3.UP
			var right = tangent.cross(up).normalized()
			if right.length_squared() < 0.001:
				right = Vector3.RIGHT
			up = right.cross(tangent).normalized()
			xform.basis = Basis(right, up, -tangent)
		xform.origin = pos

		_multimesh.set_instance_transform(write_idx, xform)
		_multimesh.set_instance_color(write_idx, _car_color[i])
		write_idx += 1

	_multimesh.visible_instance_count = write_idx
