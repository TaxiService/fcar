class_name TrafficManager
extends Node

@export_category("Pool")
@export var pool_size: int = 150
@export var max_active_cars: int = 80

@export_category("Spawning")
@export var spawn_radius: float = 600.0
@export var despawn_radius: float = 800.0
@export var cars_per_route: int = 20

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
var _spawn_radius_sq: float
var _despawn_radius_sq: float
var _rotation_radius_sq: float

# Round-robin chunk index for batched LOD updates
var _lod_chunk_index: int = 0
const LOD_CHUNK_SIZE: int = 20

func _ready():
	CityGrid.traffic_manager = self
	_spawn_radius_sq = spawn_radius * spawn_radius
	_despawn_radius_sq = despawn_radius * despawn_radius
	_rotation_radius_sq = rotation_update_radius * rotation_update_radius
	_car_scene = load("res://city/cars/redsand.tscn")
	_rng.seed = hash("traffic") + int(Time.get_unix_time_from_system()) % 10000
	call_deferred("_warm_pool")

func _warm_pool():
	for i in range(pool_size):
		var car = _create_pooled_car()
		_pool.append(car)
		if i % 20 == 19:
			await get_tree().process_frame
	_pool_ready = true
	print("TrafficManager: Pool ready (%d cars)" % _pool.size())

	# Grab routes from highway generator
	_load_routes()

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
	# Initialize slot arrays per route
	for i in range(_routes.size()):
		var route = _routes[i]
		var slot_count = cars_per_route
		var slots: Array = []
		slots.resize(slot_count)
		slots.fill(null)
		_route_slots[i] = slots

	print("TrafficManager: Loaded %d routes, %d slots each" % [_routes.size(), cars_per_route])

func _acquire_from_pool() -> TrafficCar:
	if _pool.is_empty():
		return null
	var car = _pool.pop_back()
	return car

func _return_to_pool(car: TrafficCar):
	if not is_instance_valid(car):
		return
	# Clear slot
	if car.route_index >= 0 and _route_slots.has(car.route_index):
		var slots = _route_slots[car.route_index]
		if car.slot_index >= 0 and car.slot_index < slots.size():
			slots[car.slot_index] = null
	car.deactivate()
	_active_cars.erase(car)
	_pool.append(car)

func _process(delta: float):
	if not _pool_ready or _routes.is_empty():
		return

	var cam = TrafficCar.lod_camera
	if not cam:
		cam = get_viewport().get_camera_3d()
		if cam:
			TrafficCar.lod_camera = cam
	if not cam:
		return

	var cam_pos = cam.global_position

	# Spawn/despawn pass
	_update_spawning(cam_pos)

	# Move all active cars
	_update_movement(delta, cam_pos)

	# Batched LOD update
	_update_lod_batch(cam_pos)

func _update_spawning(cam_pos: Vector3):
	# Despawn cars beyond despawn radius
	var i = _active_cars.size() - 1
	while i >= 0:
		var car = _active_cars[i]
		var dist_sq = car.global_position.distance_squared_to(cam_pos)
		if dist_sq > _despawn_radius_sq:
			_return_to_pool(car)
		i -= 1

	# Spawn cars in empty slots near camera
	if _active_cars.size() >= max_active_cars:
		return

	for route_idx in range(_routes.size()):
		var route = _routes[route_idx]
		var slots = _route_slots[route_idx]
		var slot_spacing = route.total_length / slots.size()

		for slot_idx in range(slots.size()):
			if _active_cars.size() >= max_active_cars:
				return
			if slots[slot_idx] != null:
				continue

			# Check if this slot's curve position is near the camera
			var offset = slot_spacing * slot_idx
			var slot_pos = route.curve.sample_baked(offset)
			var dist_sq = slot_pos.distance_squared_to(cam_pos)

			if dist_sq < _spawn_radius_sq:
				_spawn_car_at_slot(route_idx, route, slot_idx, offset)

func _spawn_car_at_slot(route_idx: int, route, slot_idx: int, offset: float):
	var car = _acquire_from_pool()
	if not car:
		return

	# Random tube offset (spread more horizontally than vertically)
	var angle = _rng.randf() * TAU
	var dist = _rng.randf() * route.tube_radius * 0.7
	var tube_off = Vector3(cos(angle) * dist, sin(angle) * dist * 0.3, 0)

	var spd = route.speed_limit * _rng.randf_range(0.8, 1.15)

	car.slot_index = slot_idx
	car.activate(route_idx, offset, tube_off, spd)

	# Set initial position
	var curve_pos = route.curve.sample_baked(offset)
	car.global_position = curve_pos + tube_off

	# Set initial facing
	var next_pos = route.curve.sample_baked(minf(offset + 2.0, route.total_length))
	var tangent = (next_pos - curve_pos).normalized()
	if tangent.length_squared() > 0.001:
		car.facing_direction = tangent
		car.look_at(car.global_position + tangent, Vector3.UP)

	_active_cars.append(car)
	_route_slots[route_idx][slot_idx] = car

func _update_movement(delta: float, cam_pos: Vector3):
	for car in _active_cars:
		if car.route_index < 0 or car.route_index >= _routes.size():
			continue
		var route = _routes[car.route_index]
		_update_car(car, delta, route, cam_pos)

func _update_car(car: TrafficCar, delta: float, route, cam_pos: Vector3):
	match car.state:
		TrafficCar.State.CRUISING:
			car.curve_offset += car.speed * delta

			if route.is_loop:
				car.curve_offset = fmod(car.curve_offset, route.total_length)
				if car.curve_offset < 0:
					car.curve_offset += route.total_length
			else:
				if car.curve_offset >= route.total_length:
					car.curve_offset = 0.0

			var curve_pos = route.curve.sample_baked(car.curve_offset)
			car.global_position = curve_pos + car.tube_offset

			# Only update rotation for nearby cars
			var dist_sq = car.global_position.distance_squared_to(cam_pos)
			if dist_sq < _rotation_radius_sq:
				var look_offset = minf(car.curve_offset + 2.0, route.total_length)
				var next_pos = route.curve.sample_baked(look_offset)
				var tangent = (next_pos - curve_pos).normalized()
				if tangent.length_squared() > 0.001:
					car.facing_direction = tangent
					car.look_at(car.global_position + tangent, Vector3.UP)

		TrafficCar.State.DISTURBED:
			car.disturbed_timer += delta
			var blend = car.disturbed_timer / car.disturbed_duration

			if blend >= 1.0:
				car.state = TrafficCar.State.CRUISING
				_snap_car_to_curve(car, route)
			else:
				var disturbed_pos = car.global_position + car.disturbed_velocity * delta
				car.disturbed_velocity *= 0.95

				car.curve_offset += car.target_speed * delta * 0.5
				if route.is_loop:
					car.curve_offset = fmod(car.curve_offset, route.total_length)
				var curve_pos = route.curve.sample_baked(car.curve_offset) + car.tube_offset

				var t = ease(blend, 0.3)
				car.global_position = disturbed_pos.lerp(curve_pos, t)

func _snap_car_to_curve(car: TrafficCar, route):
	# Find approximate nearest offset by sampling
	var best_offset = car.curve_offset
	var best_dist_sq = INF
	var search_range = 200.0
	var step = 20.0

	var start = car.curve_offset - search_range
	var end = car.curve_offset + search_range

	var check = start
	while check <= end:
		var test_offset = check
		if route.is_loop:
			test_offset = fmod(fmod(test_offset, route.total_length) + route.total_length, route.total_length)
		else:
			test_offset = clampf(test_offset, 0.0, route.total_length)
		var pos = route.curve.sample_baked(test_offset)
		var d = pos.distance_squared_to(car.global_position)
		if d < best_dist_sq:
			best_dist_sq = d
			best_offset = test_offset
		check += step

	car.curve_offset = best_offset
	car.speed = car.target_speed

func _update_lod_batch(cam_pos: Vector3):
	if _active_cars.is_empty():
		return

	var start = _lod_chunk_index
	var end = mini(start + LOD_CHUNK_SIZE, _active_cars.size())

	for i in range(start, end):
		_update_car_lod(_active_cars[i], cam_pos)

	_lod_chunk_index = end
	if _lod_chunk_index >= _active_cars.size():
		_lod_chunk_index = 0

func _update_car_lod(car: TrafficCar, cam_pos: Vector3):
	var dist_sq = car.global_position.distance_squared_to(cam_pos)
	car.visible = dist_sq < _despawn_radius_sq
