extends RigidBody3D

var lock_height: bool = false
var target_height: float
var height_lock_refresh_timer: float = 0.0  # Time since last height lock refresh
var is_stable: bool = true  # Tracks if car is stable enough for stabilizers/wheels
var disabled_time_remaining: float = 0.0  # Time until stabilizers can re-enable
var grace_period_remaining: float = 0.0  # Immunity period after recovery
var thrust_power: float = 1.0  # Current thrust multiplier (dissipates when disabled)

# Smoothed input state (all axes ramp up/down like analog sticks)
# Left stick (WASD) - controls tilt/movement direction
var current_pitch: float = 0.0  # Forward/backward tilt (-1 to 1)
var current_roll: float = 0.0   # Left/right tilt (-1 to 1)
# Right stick (Space/Q/C/E) - controls altitude and rotation
var current_throttle: float = 0.0  # Up/down thrust (-1 to 1)
var current_yaw: float = 0.0       # Rotation (-1 to 1)

# Vectored thrust parameters
@export_category("thrust")
@export var hover_thrust: float = 3.0  # Thrust when NOT height-locked (slowly descends)
@export var heightlock_thrust: float = 5.0  # Thrust when height-locked (maintains altitude)
@export var max_thrust: float = 10.0  # Maximum possible thrust per wheel
@export var max_thrust_angle: float = 50.0  # Max thruster tilt from vertical (degrees)
@export_category("tilt differential")
@export var pitch_differential: float = 0.5  # 0=no tilt, 1=max tilt (front/back thrust difference)
@export var roll_differential: float = 0.35   # 0=no tilt, 1=max tilt (left/right thrust difference)
@export_category("input smoothing")
# Left stick (WASD) - how fast each axis responds
@export var pitch_acceleration: float = 3.0  # How fast forward/back input ramps (higher = snappier)
@export var roll_acceleration: float = 3.0   # How fast left/right input ramps (higher = snappier)
# Right stick (Space/Q/C/E) - how fast each axis responds
@export var throttle_acceleration: float = 2.5  # How fast up/down input ramps (higher = snappier)
@export var yaw_acceleration: float = 0.8  # How fast yaw builds up (higher = slower, more gradual)
@export_category("yaw")
@export var yaw_thrust_angle: float = 30.0  # How much front/back thrusters tilt for yaw
@export var max_angular_speed: float = 2.0  # Max rotation speed (rad/s) - prevents crazy spinning
@export_category("height lock")
@export var height_lock_strength: float = 0.8  # How aggressively height lock corrects
@export var height_lock_dissipation: float = 0.5  # How fast thrust fades when disabled (seconds)
@export var height_lock_refresh_threshold: float = 0.8  # Only refresh target if drifted this far (in meters)
@export var throttle_power: float = 2.0  # How much Space/C multiply thrust (higher = faster climb/descent)
@export_category("stabilizer")
@export var stabilizer_strength: float = 25.0  # Reduced to allow natural tilting
@export var max_tilt_for_stabilizer: float = 45.0  # Disable stabilizer beyond this tilt angle (degrees)
@export_category("unstable/disabled")
@export var recovery_time: float = 1.5  # How long stabilizers stay disabled after exceeding tilt
@export var grace_period: float = 3.0  # Immunity time after recovery - can't be disabled again
@export var auto_flip_strength: float = 25.0  # Torque to help flip car upright during grace period
@export_category("damping")
@export var stable_angular_damp: float = 1.8  # Angular damping when stabilizers active
@export var unstable_angular_damp: float = 0.8  # Angular damping when disabled/tumbling
@export var stable_linear_damp: float = 2.0  # Linear damping when stabilizers active
@export var unstable_linear_damp: float = 0.85  # Linear damping when disabled/tumbling

# Wheel/corner nodes for future force application
# These should be Marker3D children positioned at the car's corners
@onready var wheel_front_left: Node3D = $WheelFrontLeft if has_node("WheelFrontLeft") else null
@onready var wheel_front_right: Node3D = $WheelFrontRight if has_node("WheelFrontRight") else null
@onready var wheel_back_left: Node3D = $WheelBackLeft if has_node("WheelBackLeft") else null
@onready var wheel_back_right: Node3D = $WheelBackRight if has_node("WheelBackRight") else null

func engage_heightlock():
	lock_height = !lock_height
	target_height = global_transform.origin.y

func _physics_process(delta):
	# Check stability first (before processing inputs)
	var car_up = global_transform.basis.y
	var tilt_angle = rad_to_deg(acos(clamp(car_up.dot(Vector3.UP), -1.0, 1.0)))

	# Count down disabled timer and detect expiry
	if disabled_time_remaining > 0.0:
		disabled_time_remaining -= delta
		# Check if just expired this frame
		if disabled_time_remaining <= 0.0:
			# Recovery complete - start grace period
			grace_period_remaining = grace_period
			# Update height lock target to current position (don't jump back up)
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
		# Currently disabled - no control, dissipate thrust
		is_stable = false
		thrust_power = move_toward(thrust_power, 0.0, delta / height_lock_dissipation)
	elif grace_period_remaining > 0.0:
		# In grace period - always stable, can't be disabled again
		is_stable = true
		thrust_power = move_toward(thrust_power, 1.0, delta / height_lock_dissipation)
	else:
		# Normal operation - check tilt threshold
		if tilt_angle >= max_tilt_for_stabilizer:
			# Car tilted too much - trigger recovery period
			print("CRASH! Tilt angle: ", tilt_angle, "° - DISABLED for ", recovery_time, "s")
			is_stable = false
			disabled_time_remaining = recovery_time
		else:
			# Car is upright - enable
			is_stable = true
			thrust_power = move_toward(thrust_power, 1.0, delta / height_lock_dissipation)

	# Height lock auto-refresh system
	if lock_height:
		# Count up the timer
		height_lock_refresh_timer += delta
		# Every 1 second, check if we've drifted significantly
		if height_lock_refresh_timer >= 1.0:
			var height_drift = abs(global_transform.origin.y - target_height)
			# Only refresh target if we've drifted more than threshold (e.g., landed on platform)
			if height_drift > height_lock_refresh_threshold:
				target_height = global_transform.origin.y
			height_lock_refresh_timer = 0.0  # Reset timer regardless
	else:
		# Height lock is off - reset timer
		height_lock_refresh_timer = 0.0

	# Only accept inputs if car is stable/operational
	if is_stable:
		# ===== READ RAW INPUT TARGETS =====
		# These are the "target" values each axis is ramping towards

		# --- LEFT STICK (WASD) - Movement direction ---
		var target_pitch: float = 0.0  # Forward/backward
		var target_roll: float = 0.0   # Left/right

		if Input.is_action_pressed("backward"):
			target_pitch = 1.0
		if Input.is_action_pressed("forward"):
			target_pitch = -1.0
		if Input.is_action_pressed("strafe_left"):
			target_roll = -1.0
		if Input.is_action_pressed("strafe_right"):
			target_roll = 1.0

		# --- RIGHT STICK (Space/Q/C/E) - Altitude and rotation ---
		var target_throttle: float = 0.0  # Up/down
		var target_yaw: float = 0.0       # Rotation

		# Throttle input (vertical)
		if Input.is_action_pressed("jump"):
			if lock_height: target_height = global_transform.origin.y
			target_throttle = 1.0  # Full up
		if Input.is_action_just_released("jump"):
			if lock_height: target_height = global_transform.origin.y

		if Input.is_action_pressed("crouch"):
			if lock_height: target_height = global_transform.origin.y
			target_throttle = -1.0  # Full down
		if Input.is_action_just_released("crouch"):
			if lock_height: target_height = global_transform.origin.y

		# Yaw input (rotation)
		if Input.is_action_pressed("turn_right"):  # Q key
			target_yaw = 1.0
		if Input.is_action_pressed("turn_left"):  # E key
			target_yaw = -1.0

		# Height lock toggle
		if Input.is_action_just_pressed("height_brake"):
			engage_heightlock()

		# ===== APPLY INPUT SMOOTHING =====
		# All axes ramp towards their targets (like analog sticks)

		# Left stick smoothing
		current_pitch = move_toward(current_pitch, target_pitch, pitch_acceleration * delta)
		current_roll = move_toward(current_roll, target_roll, roll_acceleration * delta)

		# Right stick smoothing
		current_throttle = move_toward(current_throttle, target_throttle, throttle_acceleration * delta)

		# Yaw has special handling for angular velocity limits
		var current_angular_speed = angular_velocity.dot(global_transform.basis.y)
		if abs(current_angular_speed) > max_angular_speed:
			# Already spinning too fast - block yaw input in that direction
			if sign(target_yaw) == sign(current_angular_speed):
				target_yaw = 0.0
			# Also apply counter-yaw to slow down
			target_yaw = -sign(current_angular_speed) * 0.3

		# When strafing (A/D), reduce yaw effect to prevent Q+D/A+E combos
		if abs(current_roll) > 0.1:
			target_yaw *= 0.3

		current_yaw = move_toward(current_yaw, target_yaw, yaw_acceleration * delta)

		# ===== CALCULATE FINAL INPUT VALUES =====
		# Apply curves/scaling to smoothed values

		# Pitch and roll: direct mapping (could add curves later)
		var input_pitch: float = current_pitch
		var input_roll: float = current_roll

		# Throttle: scale to thrust multipliers
		var throttle: float = current_throttle * throttle_power

		# Yaw: apply ease-in curve for smoother feel
		var input_yaw: float = sign(current_yaw) * pow(abs(current_yaw), 1.5)

		# ===== HEIGHT LOCK SYSTEM =====
		var current_base_thrust = heightlock_thrust if lock_height else hover_thrust

		# Height lock assistance (adds to throttle)
		if lock_height:
			var height_error = target_height - global_transform.origin.y
			throttle += clamp(height_error * height_lock_strength, -0.5, 0.5)

		# Car's local axes for thrust direction
		var pitch_axis = global_transform.basis.x  # Car's right axis
		var roll_axis = -global_transform.basis.z  # Car's forward axis

		# Calculate thrust for each wheel (they can tilt independently for yaw)
		var wheels = [
			{"node": wheel_front_left, "is_front": true, "is_left": true},
			{"node": wheel_front_right, "is_front": true, "is_left": false},
			{"node": wheel_back_left, "is_front": false, "is_left": true},
			{"node": wheel_back_right, "is_front": false, "is_left": false}
		]

		for wheel in wheels:
			if not wheel.node:
				continue

			# Start with base tilt from movement input
			var tilt_pitch = input_pitch * max_thrust_angle
			var tilt_roll = input_roll * max_thrust_angle

			# Add yaw component: front wheels tilt sideways opposite to back wheels
			# This creates natural rotation through thrust differential
			var yaw_tilt = input_yaw * yaw_thrust_angle
			if wheel.is_front:
				tilt_roll += yaw_tilt  # Front wheels tilt one way
			else:
				tilt_roll -= yaw_tilt  # Back wheels tilt the other way

			# Calculate thrust direction (start with UP, then rotate)
			var thrust_direction = Vector3.UP
			thrust_direction = thrust_direction.rotated(pitch_axis, deg_to_rad(tilt_pitch))
			thrust_direction = thrust_direction.rotated(roll_axis, deg_to_rad(tilt_roll))

			# Calculate total tilt angle for thrust compensation
			var total_tilt = sqrt(tilt_pitch * tilt_pitch + tilt_roll * tilt_roll)
			total_tilt = clamp(total_tilt, 0.0, 89.0)  # Prevent division by zero at 90°

			# Compensate thrust to maintain altitude: multiply by 1/cos(angle)
			var altitude_compensation = 1.0 / cos(deg_to_rad(total_tilt))

			# Calculate thrust differential for natural pitch/roll tilt
			# Front/back difference creates pitch, left/right difference creates roll
			var thrust_multiplier = 1.0

			# Only apply pitch differential (not roll) to avoid diagonal yaw
			# Pitch differential: front wheels less thrust, back wheels more (when pitching forward)
			if wheel.is_front:
				thrust_multiplier -= input_pitch * pitch_differential
			else:
				thrust_multiplier += input_pitch * pitch_differential

			# Only apply roll differential (not pitch) to avoid diagonal yaw
			# Roll differential: left wheels less thrust, right wheels more (when rolling right)
			if wheel.is_left:
				thrust_multiplier -= input_roll * roll_differential
			else:
				thrust_multiplier += input_roll * roll_differential

			# When moving diagonally, reduce differential to prevent yaw
			var diagonal_factor = abs(input_pitch) * abs(input_roll)
			if diagonal_factor > 0.0:
				thrust_multiplier = lerp(thrust_multiplier, 1.0, diagonal_factor * 0.7)

			thrust_multiplier = clamp(thrust_multiplier, 0.1, 2.0)  # Don't go negative or too high

			# Calculate thrust magnitude (with dissipation via thrust_power)
			var thrust_magnitude = current_base_thrust * (1.0 + throttle) * altitude_compensation * thrust_multiplier * thrust_power
			thrust_magnitude = clamp(thrust_magnitude, 0.0, max_thrust)  # Cap at max thrust
			var thrust_force = thrust_direction * thrust_magnitude * mass

			# Apply thrust at wheel position
			apply_force(thrust_force, wheel.node.global_position - global_position)

	else:
		# Car is disabled - decay all inputs towards zero
		# This prevents "sticky" inputs when recovering
		current_pitch = move_toward(current_pitch, 0.0, pitch_acceleration * delta * 2.0)
		current_roll = move_toward(current_roll, 0.0, roll_acceleration * delta * 2.0)
		current_throttle = move_toward(current_throttle, 0.0, throttle_acceleration * delta * 2.0)
		current_yaw = move_toward(current_yaw, 0.0, yaw_acceleration * delta * 2.0)

	# Apply damping and stabilization based on stability state
	if is_stable:
		linear_damp = stable_linear_damp
		angular_damp = stable_angular_damp

		# Check if we're in grace period with heavy tilt - apply auto-flip assist
		if grace_period_remaining > 0.0 and tilt_angle > max_tilt_for_stabilizer:
			# Auto-flip mode: stronger torque to help flip car upright
			var delta_quat: Quaternion = Quaternion(car_up, Vector3.UP)
			var angle: float = delta_quat.get_angle()
			var axis: Vector3 = delta_quat.get_axis()

			# Strong corrective torque to flip back
			apply_torque(axis.normalized() * angle * mass * auto_flip_strength)
			# Extra damping to prevent over-rotation
			apply_torque(-angular_velocity * mass * 1.5)
		else:
			# Normal stabilization forces
			var delta_quat: Quaternion = Quaternion(car_up, Vector3.UP)
			var angle: float = delta_quat.get_angle()
			var axis: Vector3 = delta_quat.get_axis()

			# Angular damping to prevent spinning
			apply_torque(-angular_velocity * mass)
			# Corrective torque to stay upright
			apply_torque(axis.normalized() * angle * mass * stabilizer_strength)
	else:
		# Disabled - use lower damping, let it tumble naturally
		linear_damp = unstable_linear_damp
		angular_damp = unstable_angular_damp
