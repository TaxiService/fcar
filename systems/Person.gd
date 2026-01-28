class_name Person
extends Sprite3D

# Movement states
enum State { WALKING, STOPPING, WAITING, HAILING, BOARDING, RIDING, EXITING, ARRIVED, RELOCATING }

# Pre-allocated state sets for fast membership checks (avoids array allocation each frame)
const IDLE_STATES = [State.WALKING, State.STOPPING, State.WAITING]
const NEAR_PLAYER_STATES = [State.BOARDING, State.EXITING]

# LOD/Culling settings (static, shared by all people)
static var lod_camera: Camera3D = null  # Set by main scene/FCar
static var lod_player_y: float = 0.0  # Player's Y position (for vertical culling)
static var lod_max_distance: float = 500.0  # Hide beyond this distance
static var lod_max_distance_squared: float = 250000.0  # 500^2, for fast distance checks
static var lod_max_height_above: float = 200.0  # Hide if this much above player
static var lod_update_interval: float = 0.5  # Check every N seconds (stagger checks)
static var lod_enabled: bool = true
static var lod_pixel_distance: float = 150.0  # Switch to pixel sprite beyond this
static var lod_pixel_distance_squared: float = 22500.0  # 150^2

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

# Home zone (set by SpawnZone)
var home_center: Vector3 = Vector3.ZERO
var home_radius: float = 8.0
var home_radius_squared: float = 64.0
var has_home: bool = false

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

# Per-person bobbing parameters (set by PeopleManager on spawn)
var bob_rate: float = 1.5  # Personal bob frequency in Hz
var bob_height: float = 0.2  # Jump height in meters
var bob_hurry_multiplier: float = 2.0  # Speed multiplier when in a hurry

# Relocation state (after delivery, walk to nearest surface)
var relocation_target: Vector3 = Vector3.ZERO
var relocation_surface: Node = null  # SpawnSurface to adopt bounds from
var relocation_speed: float = 2.0  # Faster than normal walk

# Fare cooldown (prevent immediate re-fare after delivery)
var fare_cooldown: float = 0.0  # Time remaining before can become fare again
const FARE_COOLDOWN_TIME: float = 30.0  # Seconds after delivery before eligible

# LOD/Culling instance state
var lod_timer: float = 0.0  # Stagger LOD checks
var lod_check_offset: float = 0.0  # Random offset to distribute checks
var _close_material: ShaderMaterial = null  # Full-detail material
var _pixel_material: ShaderMaterial = null  # Distant pixel material
var _using_pixel_lod: bool = false  # Currently using pixel material
var _close_texture: Texture2D = null  # Full sprite texture
var _close_pixel_size: float = 0.003  # Normal pixel size


func _ready():
	# Disable built-in billboard (shader handles it)
	billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Disable backface culling so sprite is visible from both sides
	double_sided = true

	# Randomize walk speed for this person
	walk_speed = randf_range(walk_speed_min, walk_speed_max)

	# Stagger LOD checks (random offset so not all people check on same frame)
	lod_check_offset = randf() * lod_update_interval

	# Start in waiting state
	_enter_state(State.WAITING)


func set_shared_material(mat: ShaderMaterial):
	# Use shared material from PeopleManager (for color sets)
	_close_material = mat
	material_override = mat
	_using_pixel_lod = false


func set_pixel_material(mat: ShaderMaterial):
	# Set the distant pixel LOD material
	_pixel_material = mat


func _switch_to_pixel_lod():
	if _using_pixel_lod:
		return
	if _pixel_material:
		material_override = _pixel_material
		pixel_size = 0.02  # Larger pixels = smaller on screen but visible
		_using_pixel_lod = true


func _switch_to_close_lod():
	if not _using_pixel_lod:
		return
	if _close_material:
		material_override = _close_material
		pixel_size = _close_pixel_size
		_using_pixel_lod = false


func wants_ride() -> bool:
	# Returns true if this person has a destination and is available for pickup
	return destination != null and current_state == State.HAILING


func get_trip_distance() -> float:
	# Returns distance to destination in meters (0 if no destination)
	if destination == null or not is_instance_valid(destination):
		return 0.0
	return global_position.distance_to(destination.global_position)


func get_trip_tier() -> String:
	# Returns "short", "medium", or "long" based on trip distance
	var dist = get_trip_distance()
	if dist < 800.0:
		return "short"
	elif dist < 2000.0:
		return "medium"
	else:
		return "long"


func can_become_fare() -> bool:
	# Returns true if this person is eligible to become a fare
	# Must be idle, have no destination, and not on cooldown
	if destination != null:
		return false
	if fare_cooldown > 0.0:
		return false
	if current_state not in [State.WALKING, State.WAITING]:
		return false
	return true


func set_destination(dest: Node):
	destination = dest
	if dest != null and current_state in IDLE_STATES:
		base_y = global_position.y
		_enter_state(State.HAILING)


func start_boarding(car: Node):
	target_car = car
	_enter_state(State.BOARDING)


func board_complete():
	_enter_state(State.RIDING)


func start_exiting():
	_enter_state(State.EXITING)


func start_relocating(target_pos: Vector3, surface: Node):
	relocation_target = target_pos
	relocation_surface = surface
	_enter_state(State.RELOCATING)


func _process(delta: float):
	# Decrement fare cooldown
	if fare_cooldown > 0.0:
		fare_cooldown -= delta

	# Fast path: RIDING passengers skip everything except position update
	if current_state == State.RIDING:
		visible = false
		if is_instance_valid(target_car):
			global_position = target_car.global_position
		return

	# LOD/Culling check (staggered for performance)
	if lod_enabled:
		lod_timer += delta
		if lod_timer >= lod_check_offset:
			lod_timer = 0.0
			lod_check_offset = lod_update_interval
			_update_lod_visibility()
			# If we just got hidden, this will be our last frame
			if not visible:
				return

	# Update timers
	state_timer += delta
	hail_time += delta

	# Skip expensive logic if hidden by LOD
	if not visible:
		# Still handle state transitions for waiting people
		if current_state == State.WAITING and state_timer >= state_duration:
			_enter_state(State.WALKING)
		return

	# Process current state
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
		State.EXITING:
			_process_exiting(delta)
		State.ARRIVED:
			_process_arrived(delta)
		State.RELOCATING:
			_process_relocating(delta)


func _process_walking(delta: float):
	# Move in walk direction
	var movement = walk_direction * walk_speed * delta
	global_position += movement

	# Check if outside home zone and redirect toward center
	if has_home:
		var dx = global_position.x - home_center.x
		var dz = global_position.z - home_center.z
		var dist_sq = dx * dx + dz * dz

		if dist_sq > home_radius_squared:
			# Outside radius - turn toward home center
			var to_center = Vector3(home_center.x - global_position.x, 0, home_center.z - global_position.z).normalized()
			walk_direction = to_center
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
	# Square-wave bobbing - instant jump up, then back down
	# Hurried people bob faster
	var effective_rate = bob_rate * (bob_hurry_multiplier if in_a_hurry else 1.0)

	# Position in cycle (0.0 to 1.0)
	var cycle_pos = fmod(hail_time * effective_rate, 1.0)

	# First half of cycle = up, second half = down (square wave)
	var bob_offset = bob_height if cycle_pos < 0.5 else 0.0
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
	# Bounds should already be set by FCar at delivery location
	if state_timer >= 0.5:
		destination = null
		target_car = null
		_enter_state(State.WAITING)


func _process_relocating(delta: float):
	# Walk toward relocation target
	var to_target = relocation_target - global_position
	to_target.y = 0  # Stay on same height plane

	var dist = to_target.length()

	if dist < 1.0:
		# Reached target - adopt new zone/surface and start wandering
		if relocation_surface:
			# SpawnZone (new system)
			if relocation_surface.has_method("get_center"):
				set_home_zone(relocation_surface.get_center(), relocation_surface.get_radius())
			# SpawnSurface (legacy)
			elif relocation_surface.has_method("get_bounds_world"):
				var bounds = relocation_surface.get_bounds_world()
				set_bounds(bounds.min, bounds.max)
			# Register with the zone/surface
			if relocation_surface.has_method("add_person"):
				relocation_surface.add_person(self)

		relocation_surface = null
		relocation_target = Vector3.ZERO
		destination = null
		target_car = null
		_enter_state(State.WAITING)
		return

	# Move toward target
	var dir = to_target.normalized()
	global_position += dir * relocation_speed * delta

	# Face movement direction
	if abs(dir.x) > 0.1:
		facing_right = dir.x > 0
		scale.x = 1.0 if facing_right else -1.0


func _enter_state(new_state: State):
	set_process(true)
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
			fare_cooldown = FARE_COOLDOWN_TIME  # Prevent immediate re-fare

		State.RELOCATING:
			walk_direction = Vector3.ZERO
			visible = true


func _update_facing_direction():
	# Determine facing based on X component of walk direction
	# Positive X = right (default), Negative X = left (flipped)
	# Use scale.x for flipping since materials are shared
	if abs(walk_direction.x) > 0.1:
		facing_right = walk_direction.x > 0
		scale.x = 1.0 if facing_right else -1.0


func set_home_zone(center: Vector3, radius: float):
	home_center = center
	home_radius = radius
	home_radius_squared = radius * radius
	has_home = true


# Legacy compatibility - convert rectangle to circle
func set_bounds(min_pos: Vector3, max_pos: Vector3):
	var center = (min_pos + max_pos) / 2.0
	var size = max_pos - min_pos
	var radius = min(size.x, size.z) / 2.0
	set_home_zone(center, radius)


func set_sprite(tex: AtlasTexture, index: int):
	texture = tex
	sprite_index = index
	_close_texture = tex

	# Scale sprite to be ~1.8m tall max
	# Sprite is 300x600 pixels, so aspect ratio is 0.5
	# pixel_size controls world units per pixel
	# At pixel_size = 0.003, 600 pixels = 1.8m
	_close_pixel_size = 0.003
	pixel_size = _close_pixel_size

	# Offset sprite so origin is at bottom center (feet)
	# Shift up by half the sprite height in pixels
	offset.y = tex.get_height() / 2.0


func refresh_sprite(tex: AtlasTexture):
	# Called when spritesheet is reloaded
	texture = tex
	if material_override and material_override is ShaderMaterial:
		material_override.set_shader_parameter("texture_albedo", tex)


func _update_lod_visibility():
	# Update visibility based on distance from camera and height relative to player
	# Note: RIDING passengers never call this (they skip LOD entirely)
	if not lod_camera:
		# No camera set, always visible and processing
		visible = true
		set_process(true)
		_switch_to_close_lod()
		return

	# Always show people who are boarding or exiting (actively interacting with player)
	if current_state in NEAR_PLAYER_STATES:
		visible = true
		set_process(true)
		_switch_to_close_lod()
		return

	var camera_pos = lod_camera.global_position

	# Calculate horizontal distance squared (avoids sqrt - much faster)
	var dx = global_position.x - camera_pos.x
	var dz = global_position.z - camera_pos.z
	var horiz_dist_sq = dx * dx + dz * dz

	# Hide if too far horizontally
	if horiz_dist_sq > lod_max_distance_squared:
		visible = false
		set_process(false)
		return

	# Calculate height difference relative to player
	var height_diff = global_position.y - lod_player_y

	# Hide if significantly above player (looking down on distant tiny people)
	if height_diff > lod_max_height_above:
		visible = false
		set_process(false)
		return

	# Visible - choose LOD level based on distance
	visible = true
	set_process(true)

	# Switch to pixel LOD if beyond threshold
	if horiz_dist_sq > lod_pixel_distance_squared:
		_switch_to_pixel_lod()
	else:
		_switch_to_close_lod()
	
func _reset_for_reuse():
	# Called when person is acquired from pool and reused
	# Resets all state to initial values
	
	# Movement state
	current_state = State.WAITING
	walk_direction = Vector3.ZERO
	facing_right = true
	scale.x = 1.0
	state_timer = 0.0
	state_duration = randf_range(wait_duration_min, wait_duration_max)
	walk_speed = randf_range(walk_speed_min, walk_speed_max)
	
	# Home zone
	home_center = Vector3.ZERO
	home_radius = 8.0
	home_radius_squared = 64.0
	has_home = false
	
	# Quest/destination
	destination = null
	in_a_hurry = false
	hurry_timer = 0.0
	group_id = -1
	
	# Boarding/riding
	target_car = null
	hail_time = 0.0
	base_y = 0.0
	
	# Relocation
	relocation_target = Vector3.ZERO
	relocation_surface = null
	
	# LOD - randomize offset to distribute checks across frames
	lod_timer = 0.0
	lod_check_offset = randf() * lod_update_interval
	_using_pixel_lod = false
	_close_material = null
	_pixel_material = null

	# Visual
	visible = true
