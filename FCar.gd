extends RigidBody3D

# ===== STATE VARIABLES =====
var lock_height: bool = false
var target_height: float
var height_lock_refresh_timer: float = 0.0
var is_stable: bool = true
var disabled_time_remaining: float = 0.0
var grace_period_remaining: float = 0.0
var thrust_power: float = 1.0
var handbrake_active: bool = false
var handbrake_locked: bool = false  # Double-press to lock on
var handbrake_last_press_time: float = 0.0
const HANDBRAKE_DOUBLE_PRESS_WINDOW: float = 0.3  # Seconds

# Smoothed input state
var current_pitch: float = 0.0
var current_roll: float = 0.0
var current_throttle: float = 0.0
var current_yaw: float = 0.0

# ===== EXPORT PARAMETERS =====
@export_category("thrust")
@export var hover_thrust: float = 4.0  # Slightly under gravity - graceful descent when height lock OFF
@export var heightlock_thrust: float = 6.0  # Enough for height lock to maintain + maneuver
@export var max_thrust: float = 15.0
@export var max_thrust_angle: float = 50.0

@export_category("tilt differential")
@export var pitch_differential: float = 0.5
@export var roll_differential: float = 0.35

@export_category("input smoothing")
@export var pitch_acceleration: float = 3.0
@export var roll_acceleration: float = 3.0
@export var throttle_acceleration: float = 2.5
@export var yaw_acceleration: float = 0.8

@export_category("yaw")
@export var yaw_thrust_angle: float = 30.0
@export var max_angular_speed: float = 2.0
@export var yaw_deceleration: float = 3.0  # How fast yaw input decays when released
@export var yaw_accel_min: float = 0.3  # Yaw acceleration at max speed
@export var yaw_accel_max: float = 1.8  # Yaw acceleration at rest
@export var yaw_accel_max_speed: float = 50.0  # Speed at which yaw_accel_min kicks in

@export_category("height lock")
@export var height_lock_strength: float = 0.8
@export var height_lock_dissipation: float = 0.5
@export var height_lock_refresh_threshold: float = 0.8
@export var throttle_power: float = 2.0

@export_category("stabilizer")
@export var stabilizer_strength: float = 25.0
@export var max_tilt_for_stabilizer: float = 45.0

@export_category("unstable/disabled")
@export var recovery_time: float = 1.5
@export var grace_period: float = 3.0
@export var auto_flip_strength: float = 25.0

@export_category("damping")
@export var stable_angular_damp: float = 1.8
@export var unstable_angular_damp: float = 0.8
@export var stable_linear_damp: float = 2.0
@export var unstable_linear_damp: float = 0.85

@export_category("handbrake")
@export var handbrake_disables_stabilizer: bool = true
@export var handbrake_disables_boosters: bool = true

@export_category("auto-hover safety")
@export var auto_hover_enabled: bool = true
@export var auto_hover_distance: float = 2.0
@export var auto_hover_margin: float = 0.5

@export_category("boosters")
@export var boosters_require_stability: bool = false  # If false, can fire boosters while tumbling
@export var booster_max_thrust: float = 100000.0
@export var booster_thigh_min: float = -180.0  # degrees
@export var booster_thigh_max: float = 0.0  # degrees
@export var booster_shin_min: float = 0.0  # degrees
@export var booster_shin_max: float = 45.0  # degrees
@export var booster_default_thigh_angle: float = -50.0  # degrees (negative = pointing back)
@export var booster_default_shin_angle: float = 45.0  # degrees

@export_category("passengers")
@export var cargo_capacity: int = 2
@export var pickup_range: float = 10.0  # Distance to trigger hailing persons to approach
@export var board_range: float = 3.0  # Distance for person to teleport-board
@export var delivery_range: float = 5.0  # Distance to destination for delivery
@export var delivered_wander_radius: float = 8.0  # How far delivered people can wander from drop-off

@export_category("waypoint marker")
@export var marker_scale_max: float = 2.0  # Scale when very close (on-screen)
@export var marker_scale_min: float = 0.2  # Scale when far (on-screen)
@export var marker_scale_edge: float = 1.5  # Scale when projected to screen edge (off-screen)
@export var marker_close_distance: float = 2.0  # Distance where marker is at max scale
@export var marker_far_distance: float = 20.0  # Distance where marker reaches min scale
@export var marker_edge_margin: float = 40.0  # How far from screen edge the marker sits
@export var arrow_edge_offset: float = 30.0  # Additional outward offset for arrow (to separate from marker)

@export_category("debug")
@export var debug_thrusters: bool = false
@export var debug_boosters: bool = false
@export var com_compensation_enabled: bool = true
@export_range(0.0, 3.0, 0.1) var com_compensation_strength: float = 1.0
@export var heading_hold_enabled: bool = true
@export var heading_hold_strength: float = 15.0

# ===== WHEEL REFERENCES =====
@onready var wheel_front_left: Node3D = $WheelFrontLeft if has_node("WheelFrontLeft") else null
@onready var wheel_front_right: Node3D = $WheelFrontRight if has_node("WheelFrontRight") else null
@onready var wheel_back_left: Node3D = $WheelBackLeft if has_node("WheelBackLeft") else null
@onready var wheel_back_right: Node3D = $WheelBackRight if has_node("WheelBackRight") else null
@onready var statuslights_node: Node3D = $statuslights if has_node("statuslights") else null
@onready var directionlights_node: Node3D = $directionlights if has_node("directionlights") else null

# ===== SUBSYSTEMS =====
var thruster_system: ThrusterSystem
var stabilizer_system: StabilizerSystem
var booster_system: BoosterSystem
var debug_visualizer: DebugVisualizer
var status_lights: StatusLights
var direction_lights: DirectionLights

# ===== PASSENGER SYSTEM =====
var passengers: Array[Person] = []
var people_manager: Node = null  # Reference to PeopleManager for finding hailing persons
var destination_marker: CanvasLayer = null  # HUD layer for waypoint
var marker_sprite: Sprite2D = null  # The actual waypoint indicator
var marker_arrow: Sprite2D = null  # Arrow pointing to off-screen destination
var is_ready_for_fares: bool = false  # Must be true for passengers to approach

# Eject safety: triple-click Y within time window
var eject_click_count: int = 0
var eject_window_timer: float = 0.0
const EJECT_CLICKS_REQUIRED: int = 3
const EJECT_WINDOW: float = 1.0  # Must get all clicks within this time

signal passenger_boarded(person: Person)
signal passenger_delivered(person: Person, destination: Node)
signal passenger_ejected(person: Person)
signal ready_state_changed(is_ready: bool)


func _ready():
	_init_subsystems()


func _init_subsystems():
	# Initialize thruster system
	thruster_system = ThrusterSystem.new()
	_sync_thruster_config()

	var wheel_nodes = _get_wheel_nodes()
	var com = center_of_mass if center_of_mass_mode == 1 else Vector3.ZERO
	thruster_system.calculate_com_compensation(wheel_nodes, com, debug_thrusters)

	# Initialize stabilizer system
	stabilizer_system = StabilizerSystem.new()
	_sync_stabilizer_config()

	# Initialize debug visualizer
	if debug_thrusters:
		debug_visualizer = DebugVisualizer.new()
		debug_visualizer.max_thrust = max_thrust
		debug_visualizer.create_visuals(self, wheel_nodes)

	# Initialize booster system
	_init_booster_system()

	# Initialize status lights
	if statuslights_node:
		status_lights = StatusLights.new()
		status_lights.height_lock_refresh_threshold = height_lock_refresh_threshold
		if not status_lights.initialize(statuslights_node):
			status_lights = null
			push_warning("FCar: Status lights initialization failed")

	# Initialize direction lights (reuse materials from status lights)
	if directionlights_node and status_lights:
		direction_lights = DirectionLights.new()
		if not direction_lights.initialize(directionlights_node, status_lights.material_on, status_lights.material_off):
			direction_lights = null
			push_warning("FCar: Direction lights initialization failed")

	# Find PeopleManager for passenger system
	_find_people_manager()

	# Create destination marker
	_create_destination_marker()


func _create_destination_marker():
	# Create a HUD layer for the waypoint (renders on top of everything)
	destination_marker = CanvasLayer.new()
	destination_marker.name = "DestinationMarkerHUD"
	destination_marker.layer = 100  # High layer to be on top

	# Create the main waypoint sprite (diamond shape)
	marker_sprite = Sprite2D.new()
	marker_sprite.name = "WaypointSprite"

	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Start transparent

	# Draw a diamond shape with border
	for y in range(32):
		for x in range(32):
			var cx = abs(x - 16)
			var cy = abs(y - 16)
			var dist = cx + cy
			if dist <= 14:
				if dist >= 11:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))  # White border
				else:
					img.set_pixel(x, y, Color(1.0, 0.2, 0.8, 0.95))  # Magenta fill

	var tex = ImageTexture.create_from_image(img)
	marker_sprite.texture = tex
	marker_sprite.scale = Vector2(2.0, 2.0)  # Make it bigger on screen
	destination_marker.add_child(marker_sprite)

	# Create arrow for off-screen indication
	marker_arrow = Sprite2D.new()
	marker_arrow.name = "DirectionArrow"

	var arrow_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	arrow_img.fill(Color(0, 0, 0, 0))

	# Draw an arrow pointing right (we'll rotate it)
	for y in range(32):
		for x in range(32):
			var cy = abs(y - 16)
			# Arrow shape: triangle pointing right
			if x > 8 and x < 28 and cy < (28 - x) / 1.5:
				arrow_img.set_pixel(x, y, Color(1.0, 0.2, 0.8, 0.95))

	var arrow_tex = ImageTexture.create_from_image(arrow_img)
	marker_arrow.texture = arrow_tex
	marker_arrow.scale = Vector2(1.5, 1.5)
	marker_arrow.visible = false
	destination_marker.add_child(marker_arrow)

	# Start hidden
	marker_sprite.visible = false

	# Add to scene
	get_tree().root.add_child.call_deferred(destination_marker)


func _find_people_manager():
	# Search for PeopleManager in the scene
	var root = get_tree().root
	people_manager = _find_node_by_class(root, "PeopleManager")
	if people_manager:
		print("FCar: Found PeopleManager")
	else:
		push_warning("FCar: PeopleManager not found - passenger system disabled")


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str or (node.get_script() and node.get_script().get_global_name() == class_name_str):
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


func _init_booster_system():
	booster_system = BoosterSystem.new()
	if booster_system:
		booster_system.max_thrust = booster_max_thrust
		booster_system.thigh_rotation_min = booster_thigh_min
		booster_system.thigh_rotation_max = booster_thigh_max
		booster_system.shin_rotation_min = booster_shin_min
		booster_system.shin_rotation_max = booster_shin_max
		booster_system.default_thigh_angle = booster_default_thigh_angle
		booster_system.default_shin_angle = booster_default_shin_angle
		if not booster_system.initialize(self):
			booster_system = null
			push_warning("FCar: Booster system initialization failed")
	else:
		push_warning("FCar: BoosterSystem.new() returned null - check for parse errors")


func _sync_thruster_config():
	thruster_system.max_thrust_angle = max_thrust_angle
	thruster_system.yaw_thrust_angle = yaw_thrust_angle
	thruster_system.pitch_differential = pitch_differential
	thruster_system.roll_differential = roll_differential
	thruster_system.max_thrust = max_thrust
	thruster_system.com_compensation_enabled = com_compensation_enabled
	thruster_system.com_compensation_strength = com_compensation_strength


func _sync_stabilizer_config():
	stabilizer_system.stabilizer_strength = stabilizer_strength
	stabilizer_system.auto_flip_strength = auto_flip_strength
	stabilizer_system.heading_hold_enabled = heading_hold_enabled
	stabilizer_system.heading_hold_strength = heading_hold_strength
	stabilizer_system.stable_angular_damp = stable_angular_damp
	stabilizer_system.unstable_angular_damp = unstable_angular_damp
	stabilizer_system.stable_linear_damp = stable_linear_damp
	stabilizer_system.unstable_linear_damp = unstable_linear_damp
	stabilizer_system.max_tilt_for_stabilizer = max_tilt_for_stabilizer


func _get_wheel_nodes() -> Array:
	return [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]


func _get_wheel_data() -> Array:
	return [
		{"node": wheel_front_left, "is_front": true, "is_left": true},
		{"node": wheel_front_right, "is_front": true, "is_left": false},
		{"node": wheel_back_left, "is_front": false, "is_left": true},
		{"node": wheel_back_right, "is_front": false, "is_left": false}
	]


func engage_heightlock():
	lock_height = !lock_height
	target_height = global_transform.origin.y


func _physics_process(delta):
	var car_up = global_transform.basis.y
	var tilt_angle = stabilizer_system.get_tilt_angle(car_up)

	# Update stability state machine
	_update_stability_state(delta, tilt_angle)

	# Update height lock refresh
	_update_height_lock_refresh(delta)

	if is_stable:
		_process_stable_state(delta, tilt_angle)
	else:
		_process_disabled_state(delta)

	# Apply stabilization and damping
	var stabilizer_active = is_stable and not (handbrake_active and handbrake_disables_stabilizer)
	stabilizer_system.update_damping(self, stabilizer_active)

	if stabilizer_active:
		stabilizer_system.apply_stabilization(
			self, car_up, current_yaw,
			grace_period_remaining > 0.0, tilt_angle
		)

	# Update status lights
	if status_lights:
		status_lights.update(auto_hover_enabled, lock_height, global_position.y, target_height)

	# Update direction lights based on WASD input
	# When ready + empty: INVERT lights (all ON, turn OFF on input) = "available" beacon
	# When has passengers or not ready: normal (all OFF, turn ON on input)
	if direction_lights:
		var fwd = Input.is_action_pressed("forward")
		var back = Input.is_action_pressed("backward")
		var left = Input.is_action_pressed("strafe_left")
		var right = Input.is_action_pressed("strafe_right")

		# Invert when ready for fares and no passengers (taxi available mode)
		if is_ready_for_fares and passengers.size() == 0:
			fwd = not fwd
			back = not back
			left = not left
			right = not right

		direction_lights.update(fwd, back, left, right)

	# Update boosters
	if booster_system:
		# Rotation always allowed (even when disabled/unstable)
		_update_booster_rotation(delta)

		# Thrust allowed based on stability and handbrake flags
		var stability_ok = is_stable or not boosters_require_stability
		var handbrake_ok = not (handbrake_active and handbrake_disables_boosters)
		if stability_ok and handbrake_ok:
			_update_booster_thrust(delta)
		else:
			booster_system.set_thrust(0.0)

	# Update passenger system
	_update_passengers()


func _update_stability_state(delta: float, tilt_angle: float):
	# Count down disabled timer
	if disabled_time_remaining > 0.0:
		disabled_time_remaining -= delta
		if disabled_time_remaining <= 0.0:
			grace_period_remaining = grace_period
			if lock_height:
				target_height = global_transform.origin.y
			print("Recovery complete! Starting grace period: ", grace_period, "s")

	# Count down grace period
	if grace_period_remaining > 0.0:
		grace_period_remaining -= delta
		if grace_period_remaining <= 0.0:
			print("Grace period ended - back to normal")

	# State machine for stability
	if disabled_time_remaining > 0.0:
		is_stable = false
		thrust_power = move_toward(thrust_power, 0.0, delta / height_lock_dissipation)
	elif grace_period_remaining > 0.0:
		is_stable = true
		thrust_power = move_toward(thrust_power, 1.0, delta / height_lock_dissipation)
	else:
		if tilt_angle >= max_tilt_for_stabilizer:
			print("CRASH! Tilt angle: ", tilt_angle, "° - DISABLED for ", recovery_time, "s")
			is_stable = false
			disabled_time_remaining = recovery_time
		else:
			is_stable = true
			thrust_power = move_toward(thrust_power, 1.0, delta / height_lock_dissipation)


func _update_height_lock_refresh(delta: float):
	if lock_height:
		height_lock_refresh_timer += delta
		if height_lock_refresh_timer >= 1.0:
			var height_drift = abs(global_transform.origin.y - target_height)
			if height_drift > height_lock_refresh_threshold:
				target_height = global_transform.origin.y
			height_lock_refresh_timer = 0.0
	else:
		height_lock_refresh_timer = 0.0


func _process_stable_state(delta: float, _tilt_angle: float):
	# Read and process inputs
	var inputs = _read_inputs(delta)

	# Sync config in case it changed in inspector
	thruster_system.com_compensation_enabled = com_compensation_enabled
	thruster_system.com_compensation_strength = com_compensation_strength

	# Auto-hover check
	_check_auto_hover()

	# Calculate thrust parameters
	var current_base_thrust = heightlock_thrust if lock_height else hover_thrust
	var throttle_boost = inputs.throttle_boost

	if lock_height:
		var height_error = target_height - global_transform.origin.y
		throttle_boost += clamp(height_error * height_lock_strength, -0.5, 0.5)

	# Apply thrust to wheels (unless handbrake)
	if handbrake_active:
		if debug_visualizer:
			debug_visualizer.update_all_disabled(_get_wheel_nodes())
	else:
		_apply_thrust_to_wheels(inputs, throttle_boost, current_base_thrust)


func _read_inputs(delta: float) -> Dictionary:
	# Read raw input targets
	var target_pitch: float = 0.0
	var target_roll: float = 0.0
	var target_throttle: float = 0.0
	var target_yaw: float = 0.0

	if Input.is_action_pressed("backward"):
		target_pitch = 1.0
	if Input.is_action_pressed("forward"):
		target_pitch = -1.0
	if Input.is_action_pressed("strafe_left"):
		target_roll = -1.0
	if Input.is_action_pressed("strafe_right"):
		target_roll = 1.0

	if Input.is_action_pressed("jump"):
		if lock_height: target_height = global_transform.origin.y
		target_throttle = 1.0
	if Input.is_action_just_released("jump"):
		if lock_height: target_height = global_transform.origin.y

	if Input.is_action_pressed("crouch"):
		if lock_height: target_height = global_transform.origin.y
		target_throttle = -1.0
	if Input.is_action_just_released("crouch"):
		if lock_height: target_height = global_transform.origin.y

	if Input.is_action_pressed("turn_right"):
		target_yaw = 1.0
	if Input.is_action_pressed("turn_left"):
		target_yaw = -1.0

	# Handle toggles
	if Input.is_action_just_pressed("height_brake"):
		engage_heightlock()
	if Input.is_action_just_pressed("toggle_com_compensation"):
		com_compensation_enabled = !com_compensation_enabled
		print("CoM compensation: ", "ON" if com_compensation_enabled else "OFF")
	if Input.is_action_just_pressed("toggle_auto_hover"):
		auto_hover_enabled = !auto_hover_enabled
		print("Auto-hover safety: ", "ON" if auto_hover_enabled else "OFF")

	# T key - toggle ready for fares (only when no passengers)
	if Input.is_action_just_pressed("toggle_ready_for_fares"):
		_toggle_ready_for_fares()

	# Handbrake: hold to engage, double-press to lock on, single press to unlock
	if Input.is_action_just_pressed("handbrake"):
		var now = Time.get_ticks_msec() / 1000.0
		if handbrake_locked:
			# Single press while locked = unlock
			handbrake_locked = false
			print("Handbrake: unlocked")
		elif now - handbrake_last_press_time < HANDBRAKE_DOUBLE_PRESS_WINDOW:
			# Double press = lock on
			handbrake_locked = true
			print("Handbrake: LOCKED")
		handbrake_last_press_time = now

	handbrake_active = handbrake_locked or Input.is_action_pressed("handbrake")

	# Apply input smoothing
	current_pitch = move_toward(current_pitch, target_pitch, pitch_acceleration * delta)
	current_roll = move_toward(current_roll, target_roll, roll_acceleration * delta)
	current_throttle = move_toward(current_throttle, target_throttle, throttle_acceleration * delta)

	# Yaw with angular velocity limits
	var current_angular_speed = angular_velocity.dot(global_transform.basis.y)
	if abs(current_angular_speed) > max_angular_speed:
		if sign(target_yaw) == sign(current_angular_speed):
			target_yaw = 0.0
		target_yaw = -sign(current_angular_speed) * 0.3

	if abs(current_roll) > 0.1:
		target_yaw *= 0.3

	# Calculate speed-based yaw acceleration (lerp from max at rest to min at max_speed)
	var speed = linear_velocity.length()
	var speed_t = clamp(speed / yaw_accel_max_speed, 0.0, 1.0) if yaw_accel_max_speed > 0 else 0.0
	var yaw_accel = lerp(yaw_accel_max, yaw_accel_min, speed_t)

	# Use different rates: acceleration when pressing, deceleration when releasing
	var yaw_rate = yaw_accel if abs(target_yaw) > 0.1 else yaw_deceleration
	current_yaw = move_toward(current_yaw, target_yaw, yaw_rate * delta)

	# Calculate final input values
	var input_pitch = current_pitch
	var input_roll = current_roll

	# Normalize diagonal input
	var input_magnitude = sqrt(input_pitch * input_pitch + input_roll * input_roll)
	if input_magnitude > 1.0:
		input_pitch /= input_magnitude
		input_roll /= input_magnitude

	var input_yaw = sign(current_yaw) * pow(abs(current_yaw), 1.5)
	var throttle_boost = current_throttle * throttle_power

	return {
		"input_pitch": input_pitch,
		"input_roll": input_roll,
		"input_yaw": input_yaw,
		"throttle_boost": throttle_boost
	}


func _check_auto_hover():
	if not auto_hover_enabled or lock_height or handbrake_active:
		return

	var space_state = get_world_3d().direct_space_state
	var ray_origin = global_position
	var ray_end = global_position + Vector3.DOWN * (auto_hover_distance + 1.0)

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)
	if result:
		var ground_distance = global_position.y - result.position.y
		if ground_distance < auto_hover_distance:
			lock_height = true
			target_height = result.position.y + auto_hover_distance + auto_hover_margin
			print("Auto-hover engaged! Ground at ", ground_distance, "m, locking at ", target_height)


func _apply_thrust_to_wheels(inputs: Dictionary, throttle_boost: float, base_thrust: float):
	var pitch_axis = global_transform.basis.x
	var roll_axis = -global_transform.basis.z
	var wheels = _get_wheel_data()

	var wheel_index = 0
	for wheel in wheels:
		if not wheel.node:
			wheel_index += 1
			continue

		var result = thruster_system.calculate_wheel_thrust(
			wheel_index,
			wheel.is_front,
			wheel.is_left,
			inputs.input_pitch,
			inputs.input_roll,
			inputs.input_yaw,
			throttle_boost,
			base_thrust,
			thrust_power,
			pitch_axis,
			roll_axis,
			mass
		)

		apply_force(result.force, wheel.node.global_position - global_position)

		if debug_visualizer:
			debug_visualizer.update_visual(wheel_index, wheel.node.global_position, result.direction, result.magnitude)

		wheel_index += 1


func _process_disabled_state(delta: float):
	# Decay inputs towards zero
	current_pitch = move_toward(current_pitch, 0.0, pitch_acceleration * delta * 2.0)
	current_roll = move_toward(current_roll, 0.0, roll_acceleration * delta * 2.0)
	current_throttle = move_toward(current_throttle, 0.0, throttle_acceleration * delta * 2.0)
	current_yaw = move_toward(current_yaw, 0.0, yaw_acceleration * delta * 2.0)

	if debug_visualizer:
		debug_visualizer.update_all_disabled(_get_wheel_nodes())


func _update_booster_rotation(delta: float):
	# Arrow keys rotate booster joints (works even when disabled)
	var thigh_input = 0.0
	var shin_input = 0.0

	if Input.is_key_pressed(KEY_LEFT):
		thigh_input = -1.0
	elif Input.is_key_pressed(KEY_RIGHT):
		thigh_input = 1.0

	if Input.is_key_pressed(KEY_UP):
		shin_input = -1.0
	elif Input.is_key_pressed(KEY_DOWN):
		shin_input = 1.0

	# Apply rotation (90 deg/sec for thigh, 50 deg/sec for shin)
	if thigh_input != 0.0 or shin_input != 0.0:
		var thigh_speed = 90.0 * delta
		var shin_speed = 50.0 * delta

		booster_system.thigh_angle_left += thigh_input * thigh_speed
		booster_system.thigh_angle_right += thigh_input * thigh_speed
		booster_system.shin_angle_left += shin_input * shin_speed
		booster_system.shin_angle_right += shin_input * shin_speed

		# Clamp angles
		booster_system.thigh_angle_left = clamp(booster_system.thigh_angle_left, booster_thigh_min, booster_thigh_max)
		booster_system.thigh_angle_right = clamp(booster_system.thigh_angle_right, booster_thigh_min, booster_thigh_max)
		booster_system.shin_angle_left = clamp(booster_system.shin_angle_left, booster_shin_min, booster_shin_max)
		booster_system.shin_angle_right = clamp(booster_system.shin_angle_right, booster_shin_min, booster_shin_max)

		booster_system._apply_rotations()


func _update_booster_thrust(delta: float):
	# Shift controls thrust
	var boost_active = Input.is_key_pressed(KEY_SHIFT)

	if boost_active:
		booster_system.set_thrust(1.0)
	else:
		booster_system.set_thrust(0.0)

	booster_system.apply_thrust(self, delta)

	# Debug output
	if debug_boosters and boost_active:
		var dirs = booster_system.get_thrust_directions()
		print("Boosters: thigh=", booster_system.thigh_angle_left, "° shin=", booster_system.shin_angle_left, "°")
		if dirs.has("left"):
			print("  L dir: ", dirs.left.direction)
		if dirs.has("right"):
			print("  R dir: ", dirs.right.direction)


# ===== PASSENGER SYSTEM =====

func _update_passengers():
	if not people_manager:
		return

	# Clean up invalid passenger references
	passengers = passengers.filter(func(p): return is_instance_valid(p))

	# Process eject ritual
	_update_eject_ritual(get_physics_process_delta_time())

	# Check for destination arrivals first
	_check_destination_arrivals()

	# Check for boarding persons who reached the car
	_check_boarding_arrivals()

	# Only accept new passengers if ready and available
	if is_available_for_pickup():
		_detect_and_board_hailing_persons()

	# Update destination marker
	_update_destination_marker()


func _check_boarding_arrivals():
	# Find persons in BOARDING state who are close enough to board
	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if person.current_state != Person.State.BOARDING:
			continue
		if person.target_car != self:
			continue

		# Check distance
		var dist = global_position.distance_to(person.global_position)
		if dist <= board_range:
			# They made it! Add to passengers
			if passengers.size() < cargo_capacity and person not in passengers:
				_complete_boarding(person)


func _count_boarding_persons() -> int:
	var count = 0
	for person in people_manager.all_people:
		if is_instance_valid(person) and person.current_state == Person.State.BOARDING:
			if person.target_car == self:
				count += 1
	return count


func _detect_and_board_hailing_persons():
	# Find hailing persons within pickup range
	var hailing_in_range: Array[Person] = []

	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if not person.wants_ride():
			continue

		var dist = global_position.distance_to(person.global_position)
		if dist <= pickup_range:
			hailing_in_range.append(person)

	# Sort by distance (nearest first)
	hailing_in_range.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)

	# Count how many slots we have available
	var current_boarding = _count_boarding_persons()
	var available_slots = cargo_capacity - passengers.size() - current_boarding

	if available_slots <= 0:
		return  # No room for more

	# Process nearest hailing person (handles groups too)
	for person in hailing_in_range:
		# Check if already boarding or riding
		if person.current_state == Person.State.BOARDING or person.current_state == Person.State.RIDING:
			continue

		# Check if this is a group or solo
		if person.group_id == -1:
			# Solo person - board just them
			_start_boarding_person(person)
			return  # Only accept one fare at a time
		else:
			# Group member - find all members of this group
			var group_members = _find_group_members(person.group_id)

			# Check if entire group fits
			if group_members.size() > available_slots:
				print("Group of ", group_members.size(), " too large for ", available_slots, " slots - skipping")
				continue  # Try next potential fare

			# Start boarding all group members
			for member in group_members:
				_start_boarding_person(member)

			print("Group ", person.group_id, " (", group_members.size(), " members) starting to board")
			return  # Only accept one fare (group) at a time


func _find_group_members(group_id: int) -> Array[Person]:
	# Find all persons with the same group_id
	var members: Array[Person] = []
	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if person.group_id == group_id:
			members.append(person)
	return members


func _start_boarding_person(person: Person):
	# Start boarding process for a single person
	person.start_boarding(self)

	# Check if close enough to board immediately
	var dist = global_position.distance_to(person.global_position)
	if dist <= board_range:
		_complete_boarding(person)


func _complete_boarding(person: Person):
	if person in passengers:
		return  # Already boarded

	person.board_complete()
	passengers.append(person)

	# Disable ready state - must press F again for next fare
	if is_ready_for_fares:
		is_ready_for_fares = false
		ready_state_changed.emit(false)

	print("Passenger boarded! Now carrying ", passengers.size(), "/", cargo_capacity)
	passenger_boarded.emit(person)


func _check_destination_arrivals():
	var to_deliver: Array[Person] = []

	for person in passengers:
		if not is_instance_valid(person) or not is_instance_valid(person.destination):
			continue

		var dest = person.destination
		var dest_pos = dest.global_position
		var dist = global_position.distance_to(dest_pos)

		# Use POI's arrival_radius if destination is a POI, otherwise use delivery_range
		var arrival_dist = delivery_range
		if dest is PointOfInterest:
			arrival_dist = dest.arrival_radius

		if dist <= arrival_dist:
			to_deliver.append(person)

	# Deliver passengers
	for person in to_deliver:
		_deliver_passenger(person)


func _deliver_passenger(person: Person):
	if person not in passengers:
		return

	var destination = person.destination

	# Remove from passengers
	passengers.erase(person)

	# Position person at delivery location
	var drop_pos = global_position
	drop_pos.y = destination.global_position.y  # Match destination height
	person.global_position = drop_pos

	# Set new bounds centered on drop-off point so they wander nearby
	var half_radius = delivered_wander_radius / 2.0
	person.set_bounds(
		Vector3(drop_pos.x - half_radius, drop_pos.y, drop_pos.z - half_radius),
		Vector3(drop_pos.x + half_radius, drop_pos.y, drop_pos.z + half_radius)
	)

	# Trigger exit sequence
	person.start_exiting()

	print("Passenger delivered! Now carrying ", passengers.size(), "/", cargo_capacity)
	passenger_delivered.emit(person, destination)


func get_passenger_count() -> int:
	passengers = passengers.filter(func(p): return is_instance_valid(p))
	return passengers.size()


func has_capacity() -> bool:
	return get_passenger_count() < cargo_capacity


func _toggle_ready_for_fares():
	# Can only toggle ready when no passengers
	if passengers.size() > 0:
		print("Cannot toggle ready state while carrying passengers")
		return

	is_ready_for_fares = !is_ready_for_fares
	print("Ready for fares: ", "YES" if is_ready_for_fares else "NO")
	ready_state_changed.emit(is_ready_for_fares)


func is_available_for_pickup() -> bool:
	# Must be ready AND have no passengers AND no one boarding
	return is_ready_for_fares and passengers.size() == 0 and _count_boarding_persons() == 0


func _update_eject_ritual(delta: float):
	# No passengers = nothing to eject
	if passengers.size() == 0:
		eject_click_count = 0
		return

	# Count down window timer
	if eject_click_count > 0:
		eject_window_timer += delta
		if eject_window_timer > EJECT_WINDOW:
			# Window expired, reset
			eject_click_count = 0

	# Count clicks
	if Input.is_action_just_pressed("eject_passengers"):
		if eject_click_count == 0:
			# First click starts the window
			eject_window_timer = 0.0

		eject_click_count += 1

		if eject_click_count >= EJECT_CLICKS_REQUIRED:
			_eject_all_passengers()
			eject_click_count = 0


func _eject_all_passengers():
	print("EJECT! Ejecting ", passengers.size(), " passengers!")

	# Eject all passengers at current car position
	var eject_pos = global_position

	for person in passengers:
		if not is_instance_valid(person):
			continue

		# Position at car location
		person.global_position = eject_pos

		# Clear their destination - they're stranded now
		person.destination = null
		person.target_car = null

		# Set small wander bounds around eject point
		var half_radius = delivered_wander_radius / 2.0
		person.set_bounds(
			Vector3(eject_pos.x - half_radius, eject_pos.y, eject_pos.z - half_radius),
			Vector3(eject_pos.x + half_radius, eject_pos.y, eject_pos.z + half_radius)
		)

		# Make visible and start exiting
		person.visible = true
		person.start_exiting()

		passenger_ejected.emit(person)

	passengers.clear()

	# Also cancel any boarding persons
	for person in people_manager.all_people:
		if is_instance_valid(person) and person.current_state == Person.State.BOARDING:
			if person.target_car == self:
				person.target_car = null
				person._enter_state(Person.State.HAILING)


func _update_destination_marker():
	if not marker_sprite or not marker_arrow:
		return

	# Find the first passenger with a valid destination
	var dest: Node = null
	for person in passengers:
		if is_instance_valid(person) and is_instance_valid(person.destination):
			dest = person.destination
			break

	if not dest:
		marker_sprite.visible = false
		marker_arrow.visible = false
		return

	# Get camera for projection
	var camera = get_viewport().get_camera_3d()
	if not camera:
		marker_sprite.visible = false
		marker_arrow.visible = false
		return

	var dest_pos = dest.global_position + Vector3(0, 2, 0)  # Slightly above destination
	var screen_size = get_viewport().get_visible_rect().size

	# Calculate distance from camera to destination for scaling
	var camera_distance = camera.global_position.distance_to(dest_pos)

	# Calculate scale based on distance
	# Close = max scale, Far = min scale, stays at min beyond far_distance
	var scale_t = 0.0
	if marker_far_distance > marker_close_distance:
		scale_t = clamp(
			(camera_distance - marker_close_distance) / (marker_far_distance - marker_close_distance),
			0.0, 1.0
		)
	var current_scale = lerp(marker_scale_max, marker_scale_min, scale_t)
	var scale_vec = Vector2(current_scale, current_scale)

	# Check if destination is in front of camera
	var cam_forward = -camera.global_transform.basis.z
	var to_dest = (dest_pos - camera.global_position).normalized()
	var is_in_front = cam_forward.dot(to_dest) > 0

	# Project to screen
	var screen_pos: Vector2
	if is_in_front:
		screen_pos = camera.unproject_position(dest_pos)
	else:
		# Behind camera - project to opposite side of screen
		screen_pos = camera.unproject_position(dest_pos)
		# Flip around screen center
		screen_pos = screen_size - screen_pos

	# Check if on screen (with margin)
	var is_on_screen = (
		screen_pos.x >= marker_edge_margin and screen_pos.x <= screen_size.x - marker_edge_margin and
		screen_pos.y >= marker_edge_margin and screen_pos.y <= screen_size.y - marker_edge_margin and
		is_in_front
	)

	if is_on_screen:
		# Show marker at projected position (distance-based scaling)
		marker_sprite.visible = true
		marker_sprite.position = screen_pos
		marker_sprite.scale = scale_vec
		marker_arrow.visible = false
	else:
		# Clamp to screen edge
		var screen_center = screen_size / 2.0
		var dir_to_marker = (screen_pos - screen_center).normalized()

		# Find intersection with screen edge (for marker)
		var max_x = screen_size.x / 2.0 - marker_edge_margin
		var max_y = screen_size.y / 2.0 - marker_edge_margin

		var marker_pos = screen_center
		if abs(dir_to_marker.x) > 0.001 or abs(dir_to_marker.y) > 0.001:
			var scale_x = max_x / abs(dir_to_marker.x) if abs(dir_to_marker.x) > 0.001 else 99999.0
			var scale_y = max_y / abs(dir_to_marker.y) if abs(dir_to_marker.y) > 0.001 else 99999.0
			var edge_scale = min(scale_x, scale_y)
			marker_pos = screen_center + dir_to_marker * edge_scale

		# Arrow position - further out toward edge
		var arrow_max_x = screen_size.x / 2.0 - marker_edge_margin + arrow_edge_offset
		var arrow_max_y = screen_size.y / 2.0 - marker_edge_margin + arrow_edge_offset
		var arrow_pos = screen_center
		if abs(dir_to_marker.x) > 0.001 or abs(dir_to_marker.y) > 0.001:
			var scale_x = arrow_max_x / abs(dir_to_marker.x) if abs(dir_to_marker.x) > 0.001 else 99999.0
			var scale_y = arrow_max_y / abs(dir_to_marker.y) if abs(dir_to_marker.y) > 0.001 else 99999.0
			var edge_scale = min(scale_x, scale_y)
			arrow_pos = screen_center + dir_to_marker * edge_scale

		# Use edge scale for off-screen markers
		var edge_scale_vec = Vector2(marker_scale_edge, marker_scale_edge)

		# Show marker at edge
		marker_sprite.visible = true
		marker_sprite.position = marker_pos
		marker_sprite.scale = edge_scale_vec

		# Show arrow pointing toward destination
		marker_arrow.visible = true
		marker_arrow.position = arrow_pos
		marker_arrow.rotation = dir_to_marker.angle()
		marker_arrow.scale = edge_scale_vec
