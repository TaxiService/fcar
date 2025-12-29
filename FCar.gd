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

@export_category("auto-hover safety")
@export var auto_hover_enabled: bool = true
@export var auto_hover_distance: float = 2.0
@export var auto_hover_margin: float = 0.5

@export_category("boosters")
@export var booster_max_thrust: float = 100000.0
@export var booster_thigh_min: float = -180.0  # degrees
@export var booster_thigh_max: float = 0.0  # degrees
@export var booster_shin_min: float = 0.0  # degrees
@export var booster_shin_max: float = 45.0  # degrees
@export var booster_default_thigh_angle: float = -50.0  # degrees (negative = pointing back)
@export var booster_default_shin_angle: float = 35.0  # degrees

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

# ===== SUBSYSTEMS =====
var thruster_system: ThrusterSystem
var stabilizer_system: StabilizerSystem
var booster_system: BoosterSystem
var debug_visualizer: DebugVisualizer
var status_lights: StatusLights


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

	# Update boosters (disabled when car is unstable)
	if booster_system:
		if is_stable:
			_update_boosters(delta)
		else:
			booster_system.set_thrust(0.0)


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

	handbrake_active = Input.is_action_pressed("handbrake")

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

	current_yaw = move_toward(current_yaw, target_yaw, yaw_acceleration * delta)

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


func _update_boosters(delta: float):
	# Test controls: Shift fires boosters, arrow keys rotate joints
	var boost_active = Input.is_key_pressed(KEY_SHIFT)

	# Arrow keys rotate booster joints (works anytime)
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

	# Shift controls thrust
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
