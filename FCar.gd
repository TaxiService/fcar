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

# Booster assist state
var _alt_was_pressed: bool = false  # For detecting Alt key press
var _booster_roll_differential: float = 0.0  # Current shin offset (left - right)
var _smoothed_pitch_input: float = 0.0  # Smoothed pitch input to avoid bobbing

# Control lock state (F key) - locks current inputs, player can look around freely
var controls_locked: bool = false
var locked_pitch: float = 0.0
var locked_roll: float = 0.0
var locked_throttle: float = 0.0
var locked_yaw: float = 0.0

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
@export var max_angular_speed: float = 1.8 # old values were 2 3 0.3 1.8 50
@export var yaw_deceleration: float = 1.5  # How fast yaw input decays when released
@export var yaw_accel_min: float = 0.8  # Yaw acceleration at max speed
@export var yaw_accel_max: float = 1.5  # Yaw acceleration at rest
@export var yaw_accel_max_speed: float = 30.0  # Speed at which yaw_accel_min kicks in

@export_category("height lock")
@export var height_lock_strength: float = 0.8
@export var height_lock_dissipation: float = 0.5
@export var use_city_grid_spacing: bool = true  # Use CityGrid autoload for height spacing
@export var height_lock_refresh_threshold: float = 2.5  # Fallback if CityGrid unavailable
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
@export var unstable_angular_damp: float = 0.2
@export var stable_linear_damp: float = 2.0
@export var unstable_linear_damp: float = 0.85

@export_category("handbrake")
@export var handbrake_disables_stabilizer: bool = true
@export var handbrake_disables_boosters: bool = false

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
@export var booster_default_thigh_angle: float = -60.0  # degrees (negative = pointing back)
@export var booster_default_shin_angle: float = 45.0  # degrees

@export_category("booster assist")
@export var booster_assist_rotation_speed: float = 120.0  # degrees per second
# Preset angles: {thigh, shin} for each direction
@export var booster_preset_up: Vector2 = Vector2(-119.75, 45.0)
@export var booster_preset_down: Vector2 = Vector2(0.0, 45.0)
@export var booster_preset_forward: Vector2 = Vector2(-60.0, 45.0)
@export var booster_preset_backward: Vector2 = Vector2(-180.0, 33.0)
# Arrow key controls (when assist is enabled)
@export var booster_roll_offset: float = 15.0  # Max differential shin offset in degrees
@export var booster_roll_offset_limited: bool = true  # If false, offset can go beyond limit (testing)
@export var booster_roll_speed: float = 60.0  # How fast the differential builds (deg/sec)
@export var booster_pitch_up_torque: float = 50000.0  # Torque strength for pitching nose up
@export var booster_pitch_down_torque: float = 75000.0  # Torque strength for pitching nose down
@export var booster_pitch_smoothing: float = 2.0  # How fast pitch force ramps up/down (higher = snappier)

@export_category("passengers")
@export var cargo_capacity: int = 2
@export var pickup_range: float = 10.0  # Distance to trigger hailing persons to approach
@export var board_range: float = 3.0  # Distance for person to teleport-board
@export var delivery_range: float = 5.0  # Distance to destination for delivery
@export var delivered_wander_radius: float = 8.0  # How far delivered people can wander from drop-off
@export var explicit_boarding_consent: bool = true  # If true, player must target and confirm groups

@export_category("debug")
@export var debug_thrusters: bool = false
@export var debug_boosters: bool = false
@export var com_compensation_enabled: bool = true
@export_range(0.0, 3.0, 0.1) var com_compensation_strength: float = 1.0
@export var heading_hold_enabled: bool = true
@export var heading_hold_strength: float = 15.0
@export var booster_assist_enabled: bool = true  # WASD/Space/C controls booster presets

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
var destination_marker: DestinationMarker = null  # HUD for passenger destination
var hailing_markers: HailingMarkers = null  # Markers for nearby hailing groups
var shift_manager: ShiftManager = null  # Scoring and shift tracking
var is_ready_for_fares: bool = false  # Must be true for passengers to approach
var confirmed_boarding_group: Array = []  # Members of the group confirmed to board (explicit consent mode)

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

	# Initialize LOD camera for people culling (deferred to ensure camera exists)
	call_deferred("_setup_lod_camera")

	# Initialize booster system
	_init_booster_system()

	# Initialize status lights
	if statuslights_node:
		status_lights = StatusLights.new()
		# Use city grid spacing if available (check deferred since autoload may not be ready)
		status_lights.height_grid_spacing = _get_height_grid_spacing()
		call_deferred("_update_status_lights_spacing")
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

	# Create hailing markers (shows nearby potential fares)
	_create_hailing_markers()

	# Create shift manager (scoring system)
	_create_shift_manager()


func _create_shift_manager():
	shift_manager = ShiftManager.new()
	shift_manager.name = "ShiftManager"
	shift_manager.fcar = self
	get_tree().root.add_child.call_deferred(shift_manager)


func _create_destination_marker():
	destination_marker = DestinationMarker.new()
	destination_marker.name = "DestinationMarkerHUD"
	destination_marker.fcar = self
	get_tree().root.add_child.call_deferred(destination_marker)


func _create_hailing_markers():
	# Create hailing markers system (shows nearby potential fares when ready)
	hailing_markers = HailingMarkers.new()
	hailing_markers.name = "HailingMarkersHUD"
	hailing_markers.fcar = self
	hailing_markers.people_manager = people_manager
	get_tree().root.add_child.call_deferred(hailing_markers)


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


func _toggle_control_lock(pitch: float, roll: float, throttle: float, yaw: float):
	controls_locked = !controls_locked
	if controls_locked:
		# Lock current inputs
		locked_pitch = pitch
		locked_roll = roll
		locked_throttle = throttle
		locked_yaw = yaw
		print("Controls: LOCKED")
	else:
		# Clear locked values
		locked_pitch = 0.0
		locked_roll = 0.0
		locked_throttle = 0.0
		locked_yaw = 0.0
		print("Controls: unlocked")


func _apply_lock_logic(locked_value: float, player_input: float) -> float:
	# When controls are locked:
	# - If player presses the same direction as locked, temporarily suppress (return 0)
	# - If player presses opposite direction, override with player input
	# - If player isn't pressing anything, use locked value
	if player_input == 0.0:
		return locked_value
	elif locked_value != 0.0 and sign(player_input) == sign(locked_value):
		# Player pressing same direction as locked - suppress
		return 0.0
	else:
		# Player pressing opposite or different - use player input
		return player_input


func _physics_process(delta):
	# Update LOD player position for people culling
	_update_lod_player_position()

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
		status_lights.update(auto_hover_enabled, lock_height, global_position.y, target_height, delta, linear_velocity.y)
		status_lights.set_handbrake(handbrake_active)

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


func _get_height_grid_spacing() -> float:
	# Returns the height grid spacing from CityGrid if available, otherwise fallback
	if use_city_grid_spacing and has_node("/root/CityGrid"):
		var city_grid = get_node("/root/CityGrid")
		return city_grid.height_grid_spacing
	return height_lock_refresh_threshold


func _update_status_lights_spacing():
	# Deferred call to update status lights with city grid spacing
	if status_lights:
		status_lights.height_grid_spacing = _get_height_grid_spacing()


func _update_height_lock_refresh(delta: float):
	if lock_height:
		height_lock_refresh_timer += delta
		if height_lock_refresh_timer >= 1.0:
			var height_drift = abs(global_transform.origin.y - target_height)
			if height_drift > _get_height_grid_spacing():
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
	# Read raw player input
	var player_pitch: float = 0.0
	var player_roll: float = 0.0
	var player_throttle: float = 0.0
	var player_yaw: float = 0.0

	if Input.is_action_pressed("backward"):
		player_pitch = 1.0
	if Input.is_action_pressed("forward"):
		player_pitch = -1.0
	if Input.is_action_pressed("strafe_left"):
		player_roll = -1.0
	if Input.is_action_pressed("strafe_right"):
		player_roll = 1.0

	if Input.is_action_pressed("jump"):
		if lock_height: target_height = global_transform.origin.y
		player_throttle = 1.0
	if Input.is_action_just_released("jump"):
		if lock_height: target_height = global_transform.origin.y

	if Input.is_action_pressed("crouch"):
		if lock_height: target_height = global_transform.origin.y
		player_throttle = -1.0
	if Input.is_action_just_released("crouch"):
		if lock_height: target_height = global_transform.origin.y

	if Input.is_action_pressed("turn_right"):
		player_yaw = 1.0
	if Input.is_action_pressed("turn_left"):
		player_yaw = -1.0

	# Handle control lock toggle (F key)
	if Input.is_action_just_pressed("toggle_control_lock"):
		_toggle_control_lock(player_pitch, player_roll, player_throttle, player_yaw)

	# Apply control lock: locked inputs are maintained unless player presses same direction
	var target_pitch: float
	var target_roll: float
	var target_throttle: float
	var target_yaw: float

	if controls_locked:
		target_pitch = _apply_lock_logic(locked_pitch, player_pitch)
		target_roll = _apply_lock_logic(locked_roll, player_roll)
		target_throttle = _apply_lock_logic(locked_throttle, player_throttle)
		target_yaw = _apply_lock_logic(locked_yaw, player_yaw)
	else:
		target_pitch = player_pitch
		target_roll = player_roll
		target_throttle = player_throttle
		target_yaw = player_yaw

	# Handle other toggles
	if Input.is_action_just_pressed("height_brake"):
		engage_heightlock()
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

	# Release handbrake lock when Space or C pressed (vertical movement intent)
	if handbrake_locked and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch")):
		handbrake_locked = false
		print("Handbrake: released by vertical input")

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
	# Toggle booster assist with Alt (detect key press edge)
	var alt_pressed = Input.is_key_pressed(KEY_ALT)
	if alt_pressed and not _alt_was_pressed:
		# Alt was just pressed this frame
		booster_assist_enabled = not booster_assist_enabled
		print("Booster assist: ", "ON" if booster_assist_enabled else "OFF")
	_alt_was_pressed = alt_pressed

	if booster_assist_enabled:
		_update_booster_assist(delta)
	else:
		_update_booster_manual(delta)


func _update_booster_manual(delta: float):
	# Arrow keys rotate booster joints manually
	var thigh_input = 0.0
	var shin_input = 0.0

	if Input.is_key_pressed(KEY_LEFT):
		thigh_input = -1.0
	elif Input.is_key_pressed(KEY_RIGHT):
		thigh_input = 1.0

	if Input.is_key_pressed(KEY_UP):
		shin_input = 1.0
	elif Input.is_key_pressed(KEY_DOWN):
		shin_input = -1.0

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


func _update_booster_assist(delta: float):
	# === WASD/Space/C: Preset direction control ===
	var target_thigh: float = booster_system.thigh_angle_left  # Default: keep current
	var target_shin: float = booster_system.shin_angle_left
	var input_count: int = 0
	var accumulated_thigh: float = 0.0
	var accumulated_shin: float = 0.0

	# Check each direction and accumulate
	if Input.is_action_pressed("forward"):  # W
		accumulated_thigh += booster_preset_forward.x
		accumulated_shin += booster_preset_forward.y
		input_count += 1

	if Input.is_action_pressed("backward"):  # S
		accumulated_thigh += booster_preset_backward.x
		accumulated_shin += booster_preset_backward.y
		input_count += 1

	if Input.is_action_pressed("jump"):  # Space
		accumulated_thigh += booster_preset_up.x
		accumulated_shin += booster_preset_up.y
		input_count += 1

	if Input.is_action_pressed("crouch"):  # C
		accumulated_thigh += booster_preset_down.x
		accumulated_shin += booster_preset_down.y
		input_count += 1

	# If any preset input, calculate blended target
	var has_preset_input = input_count > 0
	if has_preset_input:
		target_thigh = accumulated_thigh / input_count
		target_shin = accumulated_shin / input_count

	# === Left/Right arrows: Roll via differential shin angles ===
	var roll_input = 0.0
	if Input.is_key_pressed(KEY_LEFT):
		roll_input = -1.0
	elif Input.is_key_pressed(KEY_RIGHT):
		roll_input = 1.0

	# Update roll differential (builds up while held, decays when released)
	if roll_input != 0.0:
		var target_differential = roll_input * booster_roll_offset
		if not booster_roll_offset_limited:
			# Unlimited mode: keep increasing
			_booster_roll_differential += roll_input * booster_roll_speed * delta
		else:
			# Limited mode: move toward fixed offset
			_booster_roll_differential = move_toward(_booster_roll_differential, target_differential, booster_roll_speed * delta)
	else:
		# No roll input: decay back to zero
		_booster_roll_differential = move_toward(_booster_roll_differential, 0.0, booster_roll_speed * delta)

	# === Up/Down arrows: Pitch via direct torque ===
	var target_pitch_input = 0.0
	if Input.is_key_pressed(KEY_UP):
		target_pitch_input = -1.0  # Pitch nose down
	elif Input.is_key_pressed(KEY_DOWN):
		target_pitch_input = 1.0  # Pitch nose up

	# Smooth the pitch input to avoid bobbing
	_smoothed_pitch_input = move_toward(_smoothed_pitch_input, target_pitch_input, booster_pitch_smoothing * delta)

	if abs(_smoothed_pitch_input) > 0.01:
		# Apply torque around the car's local X axis (pitch axis)
		var pitch_axis = global_transform.basis.x
		var torque_strength = booster_pitch_up_torque if _smoothed_pitch_input > 0 else booster_pitch_down_torque
		apply_torque(pitch_axis * _smoothed_pitch_input * torque_strength)

	# === Apply angles ===
	var needs_update = has_preset_input or _booster_roll_differential != 0.0

	if needs_update:
		var rotation_step = booster_assist_rotation_speed * delta

		# Move thighs toward target (both same)
		if has_preset_input:
			booster_system.thigh_angle_left = move_toward(booster_system.thigh_angle_left, target_thigh, rotation_step)
			booster_system.thigh_angle_right = move_toward(booster_system.thigh_angle_right, target_thigh, rotation_step)

		# Move shins toward target + differential (left gets +half, right gets -half)
		var base_shin_left = target_shin if has_preset_input else booster_system.shin_angle_left
		var base_shin_right = target_shin if has_preset_input else booster_system.shin_angle_right

		# Apply differential: positive = left shin increases, right decreases
		var target_shin_left = base_shin_left + _booster_roll_differential / 2.0
		var target_shin_right = base_shin_right - _booster_roll_differential / 2.0

		if has_preset_input:
			booster_system.shin_angle_left = move_toward(booster_system.shin_angle_left, target_shin_left, rotation_step)
			booster_system.shin_angle_right = move_toward(booster_system.shin_angle_right, target_shin_right, rotation_step)
		else:
			# Only roll input - apply differential directly
			booster_system.shin_angle_left = move_toward(booster_system.shin_angle_left, booster_system.shin_angle_left + _booster_roll_differential / 2.0, booster_roll_speed * delta)
			booster_system.shin_angle_right = move_toward(booster_system.shin_angle_right, booster_system.shin_angle_right - _booster_roll_differential / 2.0, booster_roll_speed * delta)

		# Clamp all angles
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

	# Check if we've flown too far from boarding passengers - cancel if so
	_check_boarding_too_far()

	# Only accept new passengers if ready and available
	if is_available_for_pickup():
		_detect_and_board_hailing_persons()


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


func _check_boarding_too_far():
	# If we have a confirmed boarding group and fly too far, cancel the whole thing
	if not is_ready_for_fares or confirmed_boarding_group.is_empty():
		return

	# Check if any boarding person is too far away
	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if person.current_state != Person.State.BOARDING:
			continue
		if person.target_car != self:
			continue

		var dist = global_position.distance_to(person.global_position)
		if dist > pickup_range:
			# Too far - cancel boarding and return to selection mode
			print("Boarding cancelled: flew too far from passenger (", "%.1f" % dist, "m)")
			_cancel_ready_state()
			# Re-enable ready state so player can select again
			is_ready_for_fares = true
			ready_state_changed.emit(true)
			return


func _count_boarding_persons() -> int:
	var count = 0
	for person in people_manager.all_people:
		if is_instance_valid(person) and person.current_state == Person.State.BOARDING:
			if person.target_car == self:
				count += 1
	return count


func _detect_and_board_hailing_persons():
	# In explicit consent mode, boarding is triggered by _toggle_ready_for_fares()
	# This function only handles implicit (auto-board) mode
	if explicit_boarding_consent:
		return

	# === IMPLICIT CONSENT MODE (auto-board nearest) ===
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
	# Find all persons with the same group_id who currently want a ride
	var members: Array[Person] = []
	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if person.group_id == group_id and person.wants_ride():
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

	# Disable ready state - must press T again for next fare
	if is_ready_for_fares:
		is_ready_for_fares = false
		confirmed_boarding_group.clear()
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

	if not is_ready_for_fares:
		# Not ready → become ready
		is_ready_for_fares = true
		confirmed_boarding_group.clear()
		print("Ready for fares: YES")
		ready_state_changed.emit(true)
	elif explicit_boarding_consent:
		# Ready + explicit mode: check for targeted group
		var targeted = hailing_markers.get_targeted_group() if hailing_markers else null
		if targeted and targeted.members.size() > 0:
			# Get a representative member to find the full group
			var representative = targeted.members[0]
			if not is_instance_valid(representative):
				_cancel_ready_state()
				return

			# Find ALL group members by group_id (more robust than pre-filtered list)
			var group_members: Array[Person] = []
			if representative.group_id == -1:
				# Solo person - just them
				group_members.append(representative)
			else:
				# Group - find all members with this group_id
				group_members = _find_group_members(representative.group_id)

			# Check capacity - can we fit the whole group?
			var available_slots = cargo_capacity - passengers.size() - _count_boarding_persons()
			if group_members.size() > available_slots:
				print("No room! Group of ", group_members.size(), " won't fit in ", available_slots, " available slots")
				# Stay in ready state so player can pick a different group
				return

			# Confirm the group for boarding
			confirmed_boarding_group = []
			for p in group_members:
				confirmed_boarding_group.append(p)
			print("Confirmed group of ", confirmed_boarding_group.size(), " for boarding")

			# Start boarding all group members
			# IMPORTANT: iterate over a duplicate because _complete_boarding may clear the array
			for person in confirmed_boarding_group.duplicate():
				if is_instance_valid(person):
					_start_boarding_person(person)
			# Stay in ready state until boarding completes
		else:
			# No target → cancel ready state
			_cancel_ready_state()
	else:
		# Implicit mode: just toggle off
		_cancel_ready_state()


func _cancel_ready_state():
	is_ready_for_fares = false
	confirmed_boarding_group.clear()
	print("Ready for fares: NO")
	ready_state_changed.emit(false)
	# Cancel any persons currently boarding this car
	_cancel_all_boarding()


func _cancel_all_boarding():
	# Cancel all persons currently boarding this car - send them back to hailing
	if not people_manager:
		return
	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if person.current_state == Person.State.BOARDING and person.target_car == self:
			person.target_car = null
			person._enter_state(Person.State.HAILING)
			print("Cancelled boarding for person")


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


# LOD/Culling system for people visibility
func _setup_lod_camera():
	# Find and set the camera for person LOD/culling
	var camera = get_viewport().get_camera_3d()
	if camera:
		Person.lod_camera = camera
		print("FCar: LOD camera set for people culling")
	else:
		push_warning("FCar: Could not find camera for LOD system")


func _update_lod_player_position():
	# Update player Y position for vertical culling
	Person.lod_player_y = global_position.y
