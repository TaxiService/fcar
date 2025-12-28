extends RigidBody3D

var lock_height: bool = false
var target_height: float
var height_lock_refresh_timer: float = 0.0  # Time since last height lock refresh
var is_stable: bool = true  # Tracks if car is stable enough for stabilizers/wheels
var disabled_time_remaining: float = 0.0  # Time until stabilizers can re-enable
var grace_period_remaining: float = 0.0  # Immunity period after recovery
var thrust_power: float = 1.0  # Current thrust multiplier (dissipates when disabled)
var handbrake_active: bool = false  # When true, all thrusters are disabled

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
@export_category("handbrake")
@export var handbrake_disables_stabilizer: bool = true  # Also disable stabilizer when handbrake is held

@export_category("auto-hover safety")
@export var auto_hover_enabled: bool = true  # Automatically lock height when close to ground
@export var auto_hover_distance: float = 2.0  # Distance to ground that triggers auto-hover (meters)
@export var auto_hover_margin: float = 0.5  # Extra height added when auto-hover kicks in

@export_category("debug")
@export var debug_thrusters: bool = false  # Show thruster direction cylinders and force arrows
@export var com_compensation_enabled: bool = true  # Compensate for center of mass offset
@export_range(0.0, 3.0, 0.1) var com_compensation_strength: float = 1.0  # How aggressively to compensate (1=calculated, 2=double, 0=none)
@export var heading_hold_enabled: bool = true  # Actively cancel unwanted yaw when not turning
@export var heading_hold_strength: float = 15.0  # How strongly to hold heading (higher = more stable)

# Wheel/corner nodes for future force application
# These should be Marker3D children positioned at the car's corners
@onready var wheel_front_left: Node3D = $WheelFrontLeft if has_node("WheelFrontLeft") else null
@onready var wheel_front_right: Node3D = $WheelFrontRight if has_node("WheelFrontRight") else null
@onready var wheel_back_left: Node3D = $WheelBackLeft if has_node("WheelBackLeft") else null
@onready var wheel_back_right: Node3D = $WheelBackRight if has_node("WheelBackRight") else null

# Debug visualization
var debug_cylinders: Array[MeshInstance3D] = []
var debug_arrows: Array[MeshInstance3D] = []

# CoM compensation - precomputed lever arms and compensation factors
var wheel_lever_arms: Array[Vector3] = []  # Position of each wheel relative to CoM
var strafe_compensation: Array[float] = []  # Thrust multiplier for strafing (prevents yaw)
var pitch_compensation: Array[float] = []   # Thrust multiplier for forward/back (prevents roll)
var yaw_compensation: Array[float] = []     # Yaw tilt multiplier (balances yaw torque around CoM)
var throttle_compensation: Array[float] = []  # Thrust multiplier for up/down (prevents pitch/roll)

func _ready():
	if debug_thrusters:
		_create_debug_visuals()
	_calculate_com_compensation()

func _calculate_com_compensation():
	# Get center of mass (local to the rigid body)
	var com = center_of_mass if center_of_mass_mode == 1 else Vector3.ZERO

	var wheel_nodes = [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]

	# Clear and recalculate
	wheel_lever_arms.clear()
	strafe_compensation.clear()
	pitch_compensation.clear()
	yaw_compensation.clear()
	throttle_compensation.clear()

	# First pass: calculate lever arms and find averages
	var total_abs_z = 0.0
	var total_abs_x = 0.0
	var total_horizontal_dist = 0.0  # Distance in X-Z plane for yaw
	var valid_count = 0

	for wheel in wheel_nodes:
		if wheel:
			var lever = wheel.position - com
			wheel_lever_arms.append(lever)
			total_abs_z += abs(lever.z)
			total_abs_x += abs(lever.x)
			total_horizontal_dist += sqrt(lever.x * lever.x + lever.z * lever.z)
			valid_count += 1
		else:
			wheel_lever_arms.append(Vector3.ZERO)

	if valid_count == 0:
		# No wheels, set defaults
		for i in range(4):
			strafe_compensation.append(1.0)
			pitch_compensation.append(1.0)
			yaw_compensation.append(1.0)
			throttle_compensation.append(1.0)
		return

	var avg_abs_z = total_abs_z / valid_count
	var avg_abs_x = total_abs_x / valid_count
	var avg_horizontal_dist = total_horizontal_dist / valid_count

	# Second pass: calculate compensation factors
	# Wheels with larger lever arms get less thrust to prevent unwanted torque
	for i in range(wheel_nodes.size()):
		if wheel_nodes[i]:
			var lever = wheel_lever_arms[i]

			# Strafe compensation: based on Z lever (forward/back distance from CoM)
			# Larger |Z| means more yaw torque when strafing, so reduce thrust
			if abs(lever.z) > 0.01:
				var strafe_comp = avg_abs_z / abs(lever.z)
				strafe_compensation.append(clamp(strafe_comp, 0.3, 3.0))
			else:
				strafe_compensation.append(1.0)

			# Pitch compensation: based on X lever (left/right distance from CoM)
			# Larger |X| means more roll torque when pitching, so reduce thrust
			if abs(lever.x) > 0.01:
				var pitch_comp = avg_abs_x / abs(lever.x)
				pitch_compensation.append(clamp(pitch_comp, 0.3, 3.0))
			else:
				pitch_compensation.append(1.0)

			# Yaw compensation: based on horizontal distance from CoM
			# Wheels further from CoM in X-Z plane create more yaw torque
			# So reduce their yaw tilt to balance yaw response
			var horizontal_dist = sqrt(lever.x * lever.x + lever.z * lever.z)
			if horizontal_dist > 0.01:
				var yaw_comp = avg_horizontal_dist / horizontal_dist
				yaw_compensation.append(clamp(yaw_comp, 0.3, 3.0))
			else:
				yaw_compensation.append(1.0)

			# Throttle compensation: based on horizontal distance from CoM
			# When going up/down, wheels further from CoM create more pitch/roll torque
			# So reduce their thrust to prevent unwanted rotation during vertical movement
			if horizontal_dist > 0.01:
				var throttle_comp = avg_horizontal_dist / horizontal_dist
				throttle_compensation.append(clamp(throttle_comp, 0.3, 3.0))
			else:
				throttle_compensation.append(1.0)
		else:
			strafe_compensation.append(1.0)
			pitch_compensation.append(1.0)
			yaw_compensation.append(1.0)
			throttle_compensation.append(1.0)

	if debug_thrusters:
		print("CoM compensation calculated:")
		print("  Center of Mass: ", com)
		print("  Lever arms: ", wheel_lever_arms)
		print("  Strafe compensation: ", strafe_compensation)
		print("  Pitch compensation: ", pitch_compensation)
		print("  Yaw compensation: ", yaw_compensation)
		print("  Throttle compensation: ", throttle_compensation)

func _create_debug_visuals():
	var wheel_nodes = [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]

	for wheel in wheel_nodes:
		if not wheel:
			continue

		# Create cylinder for thruster direction
		var cylinder_mesh = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.05
		cylinder.bottom_radius = 0.08
		cylinder.height = 0.3
		cylinder_mesh.mesh = cylinder

		# Create material for cylinder (blue-ish)
		var cyl_mat = StandardMaterial3D.new()
		cyl_mat.albedo_color = Color(0.3, 0.5, 1.0, 0.8)
		cyl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cylinder_mesh.material_override = cyl_mat

		add_child(cylinder_mesh)
		debug_cylinders.append(cylinder_mesh)

		# Create arrow for force vector
		var arrow_mesh = MeshInstance3D.new()
		var arrow = CylinderMesh.new()
		arrow.top_radius = 0.0
		arrow.bottom_radius = 0.04
		arrow.height = 0.5
		arrow_mesh.mesh = arrow

		# Create material for arrow (green for force)
		var arrow_mat = StandardMaterial3D.new()
		arrow_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.9)
		arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		arrow_mesh.material_override = arrow_mat

		add_child(arrow_mesh)
		debug_arrows.append(arrow_mesh)

func _update_debug_visual(index: int, wheel_pos: Vector3, thrust_direction: Vector3, thrust_magnitude: float):
	if index >= debug_cylinders.size() or index >= debug_arrows.size():
		return

	var cylinder = debug_cylinders[index]
	var arrow = debug_arrows[index]

	# Position cylinder at wheel, pointing in thrust direction
	cylinder.global_position = wheel_pos

	# Rotate cylinder to point along thrust direction
	# Cylinder's default orientation is along Y axis, so we need to align Y to thrust_direction
	if thrust_direction.length() > 0.01:
		var up = thrust_direction.normalized()
		var right = up.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.01:
			right = up.cross(Vector3.RIGHT).normalized()
		var forward = right.cross(up).normalized()
		cylinder.global_transform.basis = Basis(right, up, forward)

	# Position arrow BELOW the cylinder (like thruster exhaust fire!)
	# Points opposite to thrust direction, length scales with thrust magnitude
	var arrow_length = clamp(thrust_magnitude / max_thrust, 0.1, 2.0) * 0.5
	var exhaust_direction = -thrust_direction.normalized()  # Opposite of thrust = exhaust direction
	arrow.global_position = wheel_pos + exhaust_direction * (0.15 + arrow_length * 0.5)
	# Flip the basis to point downward (negate the up vector)
	if thrust_direction.length() > 0.01:
		var down = exhaust_direction
		var right = down.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.01:
			right = down.cross(Vector3.RIGHT).normalized()
		var forward = right.cross(down).normalized()
		arrow.global_transform.basis = Basis(right, down, forward)
	arrow.scale = Vector3(1, arrow_length, 1)

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

		# Height lock toggle (Caps Lock)
		if Input.is_action_just_pressed("height_brake"):
			engage_heightlock()

		# CoM compensation toggle (Control)
		if Input.is_action_just_pressed("toggle_com_compensation"):
			com_compensation_enabled = !com_compensation_enabled
			print("CoM compensation: ", "ON" if com_compensation_enabled else "OFF")

		# Auto-hover toggle (V)
		if Input.is_action_just_pressed("toggle_auto_hover"):
			auto_hover_enabled = !auto_hover_enabled
			print("Auto-hover safety: ", "ON" if auto_hover_enabled else "OFF")

		# Handbrake (X) - held to disable thrusters
		handbrake_active = Input.is_action_pressed("handbrake")

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

		# Normalize diagonal input to prevent faster/stronger diagonal movement
		# Without this, W+A would give magnitude √2 ≈ 1.414 instead of 1.0
		var input_magnitude = sqrt(input_pitch * input_pitch + input_roll * input_roll)
		if input_magnitude > 1.0:
			input_pitch /= input_magnitude
			input_roll /= input_magnitude

		# Throttle: simple linear boost/reduction to base thrust
		# Space adds thrust, C reduces thrust - straightforward!
		var throttle_boost: float = current_throttle * throttle_power

		# Yaw: apply ease-in curve for smoother feel
		var input_yaw: float = sign(current_yaw) * pow(abs(current_yaw), 1.5)

		# ===== AUTO-HOVER SAFETY SYSTEM =====
		# Raycast downward to detect ground proximity
		if auto_hover_enabled and not lock_height and not handbrake_active:
			var space_state = get_world_3d().direct_space_state
			var ray_origin = global_position
			var ray_end = global_position + Vector3.DOWN * (auto_hover_distance + 1.0)

			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.exclude = [self]  # Don't hit ourselves

			var result = space_state.intersect_ray(query)
			if result:
				var ground_distance = global_position.y - result.position.y
				if ground_distance < auto_hover_distance:
					# Too close to ground! Auto-engage height lock
					lock_height = true
					target_height = result.position.y + auto_hover_distance + auto_hover_margin
					print("Auto-hover engaged! Ground at ", ground_distance, "m, locking at ", target_height)

		# ===== HEIGHT LOCK SYSTEM =====
		var current_base_thrust = heightlock_thrust if lock_height else hover_thrust

		# Height lock assistance (adds to throttle boost)
		if lock_height:
			var height_error = target_height - global_transform.origin.y
			throttle_boost += clamp(height_error * height_lock_strength, -0.5, 0.5)

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

		# Skip thrust application if handbrake is active
		if handbrake_active:
			# Update debug visuals to show disabled state
			if debug_thrusters:
				var wheel_nodes = [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]
				for i in range(wheel_nodes.size()):
					if wheel_nodes[i]:
						_update_debug_visual(i, wheel_nodes[i].global_position, Vector3.UP, 0.0)
		else:
			# Normal thrust application
			var wheel_index = 0
			for wheel in wheels:
				if not wheel.node:
					wheel_index += 1
					continue

				# Start with base tilt from movement input
				var tilt_pitch = input_pitch * max_thrust_angle
				var tilt_roll = input_roll * max_thrust_angle

				# Add yaw component: front wheels tilt sideways opposite to back wheels
				# This creates natural rotation through thrust differential
				# Apply yaw compensation to balance torque around CoM (if enabled)
				var yaw_comp = 1.0
				if com_compensation_enabled and wheel_index < yaw_compensation.size():
					# Apply strength: pow(comp, strength) - higher strength = more aggressive compensation
					yaw_comp = pow(yaw_compensation[wheel_index], com_compensation_strength)
				var yaw_tilt = input_yaw * yaw_thrust_angle * yaw_comp
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
				# Cap at 1.5x to prevent extreme thrust when heavily tilted + throttling
				var altitude_compensation = 1.0 / cos(deg_to_rad(total_tilt))
				altitude_compensation = minf(altitude_compensation, 1.5)

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

				# Apply Center of Mass compensation to prevent unwanted rotation during translation
				# This adjusts thrust per wheel based on lever arm distance from CoM
				var com_comp = 1.0
				if com_compensation_enabled and wheel_index < throttle_compensation.size():
					# Blend compensation based on input magnitude
					# Each axis contributes its compensation weighted by input strength
					var strafe_weight = abs(input_roll)
					var pitch_weight = abs(input_pitch)
					var throttle_weight = abs(throttle_boost)  # Include vertical thrust!
					var total_weight = strafe_weight + pitch_weight + throttle_weight

					if total_weight > 0.01:
						# Get base compensation values
						var strafe_comp = strafe_compensation[wheel_index] if wheel_index < strafe_compensation.size() else 1.0
						var pitch_comp = pitch_compensation[wheel_index] if wheel_index < pitch_compensation.size() else 1.0
						var throt_comp = throttle_compensation[wheel_index]

						# Apply strength: pow(comp, strength) - higher strength = more aggressive
						strafe_comp = pow(strafe_comp, com_compensation_strength)
						pitch_comp = pow(pitch_comp, com_compensation_strength)
						throt_comp = pow(throt_comp, com_compensation_strength)

						# Blend based on input weights
						com_comp = (strafe_comp * strafe_weight + pitch_comp * pitch_weight + throt_comp * throttle_weight) / total_weight
					# When not moving (hovering), no compensation needed

				# Calculate thrust magnitude (with dissipation via thrust_power)
				# Throttle is now ADDITIVE: base thrust + throttle boost
				# This means Space = more thrust, C = less thrust, simple and intuitive
				var effective_base = current_base_thrust + throttle_boost
				effective_base = maxf(effective_base, 0.0)  # Never go negative
				var thrust_magnitude = effective_base * altitude_compensation * thrust_multiplier * com_comp * thrust_power
				thrust_magnitude = clamp(thrust_magnitude, 0.0, max_thrust)  # Cap at max thrust
				var thrust_force = thrust_direction * thrust_magnitude * mass

				# Apply thrust at wheel position
				apply_force(thrust_force, wheel.node.global_position - global_position)

				# Update debug visualization
				if debug_thrusters:
					_update_debug_visual(wheel_index, wheel.node.global_position, thrust_direction, thrust_magnitude)

				wheel_index += 1

	else:
		# Car is disabled - decay all inputs towards zero
		# This prevents "sticky" inputs when recovering
		current_pitch = move_toward(current_pitch, 0.0, pitch_acceleration * delta * 2.0)
		current_roll = move_toward(current_roll, 0.0, roll_acceleration * delta * 2.0)
		current_throttle = move_toward(current_throttle, 0.0, throttle_acceleration * delta * 2.0)
		current_yaw = move_toward(current_yaw, 0.0, yaw_acceleration * delta * 2.0)

		# Update debug visuals to show disabled state (thrusters pointing up, no force)
		if debug_thrusters:
			var wheel_nodes = [wheel_front_left, wheel_front_right, wheel_back_left, wheel_back_right]
			for i in range(wheel_nodes.size()):
				if wheel_nodes[i]:
					_update_debug_visual(i, wheel_nodes[i].global_position, Vector3.UP, 0.0)

	# Apply damping and stabilization based on stability state
	# Handbrake can optionally disable stabilizer for free-fall/tricks
	var stabilizer_active = is_stable and not (handbrake_active and handbrake_disables_stabilizer)

	if stabilizer_active:
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

			# Heading hold: when not intentionally yawing, actively cancel yaw velocity
			# This prevents unwanted rotation from CoM-induced torque imbalance
			if heading_hold_enabled and abs(current_yaw) < 0.1:
				# Get yaw angular velocity (rotation around car's up axis)
				var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
				# Apply counter-torque to cancel unwanted yaw
				apply_torque(-global_transform.basis.y * yaw_velocity * mass * heading_hold_strength)
	else:
		# Disabled or handbrake - use lower damping, let it tumble/fall naturally
		linear_damp = unstable_linear_damp
		angular_damp = unstable_angular_damp
