class_name Person
extends Sprite3D

# Movement states
enum State { WALKING, STOPPING, WAITING, HAILING, BOARDING, RIDING, EXITING, ARRIVED }

# Configuration (set by PeopleManager)
var walk_speed_min: float = 0.8
var walk_speed_max: float = 1.5
var walk_duration_min: float = 2.0
var walk_duration_max: float = 5.0
var wait_duration_min: float = 1.0
var wait_duration_max: float = 4.0

# Instance state
var current_state: State = State.WAITING
var walk_speed: float
var walk_direction: Vector3 = Vector3.ZERO
var facing_right: bool = true
var state_timer: float = 0.0
var state_duration: float = 0.0

# Bounds (set by SpawnSurface)
var bounds_min: Vector3
var bounds_max: Vector3
var has_bounds: bool = false

# Reference to manager for sprite updates
var sprite_index: int = 0

# Quest/destination system
var destination: Node = null  # Another Person or POI
var in_a_hurry: bool = false
var hurry_timer: float = 0.0
var group_id: int = -1  # -1 = solo, else grouped with same id

# Boarding/riding state
var target_car: Node = null  # FCar reference when boarding/riding
var hail_time: float = 0.0  # For bobbing animation
var board_speed: float = 5.0  # Speed when walking to car
var base_y: float = 0.0  # Original Y position for bobbing
var max_boarding_distance: float = 20.0  # Give up boarding if car gets this far


func _ready():
	# Disable built-in billboard (shader handles it)
	billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Disable backface culling so sprite is visible from both sides
	double_sided = true

	# Randomize walk speed for this person
	walk_speed = randf_range(walk_speed_min, walk_speed_max)

	# Start in waiting state
	_enter_state(State.WAITING)


func set_shared_material(mat: ShaderMaterial):
	# Use shared material from PeopleManager (for color sets)
	material_override = mat


func wants_ride() -> bool:
	# Returns true if this person has a destination and is available for pickup
	return destination != null and current_state == State.HAILING


func set_destination(dest: Node):
	destination = dest
	if dest != null and current_state in [State.WALKING, State.STOPPING, State.WAITING]:
		base_y = global_position.y
		_enter_state(State.HAILING)


func start_boarding(car: Node):
	target_car = car
	_enter_state(State.BOARDING)


func board_complete():
	_enter_state(State.RIDING)


func start_exiting():
	_enter_state(State.EXITING)


func _process(delta: float):
	state_timer += delta
	hail_time += delta

	match current_state:
		State.WALKING:
			_process_walking(delta)
		State.STOPPING:
			_process_stopping(delta)
		State.WAITING:
			_process_waiting(delta)
		State.HAILING:
			_process_hailing(delta)
		State.BOARDING:
			_process_boarding(delta)
		State.RIDING:
			_process_riding(delta)
		State.EXITING:
			_process_exiting(delta)
		State.ARRIVED:
			_process_arrived(delta)


func _process_walking(delta: float):
	# Move in walk direction
	var movement = walk_direction * walk_speed * delta
	global_position += movement

	# Check bounds and bounce if needed
	if has_bounds:
		var bounced = false

		if global_position.x < bounds_min.x:
			global_position.x = bounds_min.x
			walk_direction.x = abs(walk_direction.x)
			bounced = true
		elif global_position.x > bounds_max.x:
			global_position.x = bounds_max.x
			walk_direction.x = -abs(walk_direction.x)
			bounced = true

		if global_position.z < bounds_min.z:
			global_position.z = bounds_min.z
			walk_direction.z = abs(walk_direction.z)
			bounced = true
		elif global_position.z > bounds_max.z:
			global_position.z = bounds_max.z
			walk_direction.z = -abs(walk_direction.z)
			bounced = true

		if bounced:
			_update_facing_direction()

	# Check if walk duration is over
	if state_timer >= state_duration:
		_enter_state(State.STOPPING)


func _process_stopping(_delta: float):
	# Brief stopping state before waiting
	if state_timer >= 0.2:
		_enter_state(State.WAITING)


func _process_waiting(_delta: float):
	if state_timer >= state_duration:
		_enter_state(State.WALKING)


func _process_hailing(_delta: float):
	# Bob up and down to indicate wanting a ride - fast and frantic!
	var bob_offset = sin(hail_time * 12.0) * 0.25  # 12 Hz, 0.25m amplitude
	global_position.y = base_y + bob_offset

	# If car is nearby and triggered approach, handled by start_boarding()


func _process_boarding(delta: float):
	if not is_instance_valid(target_car):
		# Car disappeared, go back to hailing
		_enter_state(State.HAILING)
		return

	var car_pos = target_car.global_position
	var dist = global_position.distance_to(car_pos)

	# Give up if car got too far away
	if dist > max_boarding_distance:
		target_car = null
		_enter_state(State.HAILING)
		return

	# Move toward car (FCar will detect when we're close enough and complete boarding)
	var dir = (car_pos - global_position).normalized()
	dir.y = 0  # Stay on ground while approaching
	global_position += dir * board_speed * delta

	# Face the car
	if abs(dir.x) > 0.1:
		facing_right = dir.x > 0
		scale.x = 1.0 if facing_right else -1.0


func _process_riding(_delta: float):
	# Stay hidden and follow car
	if is_instance_valid(target_car):
		global_position = target_car.global_position
	# Actual delivery is triggered by FCar when near destination


func _process_exiting(_delta: float):
	# Brief exit animation - just walk away a bit
	if state_timer < 0.5:
		global_position += walk_direction * walk_speed * _delta
	else:
		_enter_state(State.ARRIVED)


func _process_arrived(_delta: float):
	# Quest complete, transition back to normal wandering
	if state_timer >= 0.5:
		destination = null
		target_car = null
		_enter_state(State.WAITING)


func _enter_state(new_state: State):
	current_state = new_state
	state_timer = 0.0

	match new_state:
		State.WALKING:
			# Pick random walk direction (horizontal only)
			var angle = randf() * TAU
			walk_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
			state_duration = randf_range(walk_duration_min, walk_duration_max)
			_update_facing_direction()

		State.STOPPING:
			walk_direction = Vector3.ZERO
			state_duration = 0.2

		State.WAITING:
			walk_direction = Vector3.ZERO
			state_duration = randf_range(wait_duration_min, wait_duration_max)

		State.HAILING:
			walk_direction = Vector3.ZERO
			visible = true
			# base_y should already be set by set_destination()

		State.BOARDING:
			walk_direction = Vector3.ZERO
			visible = true
			# Reset Y to base before approaching
			global_position.y = base_y

		State.RIDING:
			visible = false
			walk_direction = Vector3.ZERO

		State.EXITING:
			visible = true
			# Pick random direction to walk away
			var angle = randf() * TAU
			walk_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
			_update_facing_direction()

		State.ARRIVED:
			walk_direction = Vector3.ZERO


func _update_facing_direction():
	# Determine facing based on X component of walk direction
	# Positive X = right (default), Negative X = left (flipped)
	# Use scale.x for flipping since materials are shared
	if abs(walk_direction.x) > 0.1:
		facing_right = walk_direction.x > 0
		scale.x = 1.0 if facing_right else -1.0


func set_bounds(min_pos: Vector3, max_pos: Vector3):
	bounds_min = min_pos
	bounds_max = max_pos
	has_bounds = true


func set_sprite(tex: AtlasTexture, index: int):
	texture = tex
	sprite_index = index

	# Pass texture to shader if material is set
	if material_override and material_override is ShaderMaterial:
		material_override.set_shader_parameter("texture_albedo", tex)

	# Scale sprite to be ~1.8m tall max
	# Sprite is 300x600 pixels, so aspect ratio is 0.5
	# pixel_size controls world units per pixel
	# At pixel_size = 0.003, 600 pixels = 1.8m
	pixel_size = 0.003

	# Offset sprite so origin is at bottom center (feet)
	# Shift up by half the sprite height in pixels
	offset.y = tex.get_height() / 2.0


func refresh_sprite(tex: AtlasTexture):
	# Called when spritesheet is reloaded
	texture = tex
	if material_override and material_override is ShaderMaterial:
		material_override.set_shader_parameter("texture_albedo", tex)
