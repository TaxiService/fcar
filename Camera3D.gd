extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 1, -5)  # Negative Z to position camera behind car

# Position following (keep high for responsive camera)
@export var position_lerp_speed: float = 25.0  # How fast camera position follows car

# Camera yaw lag (creates over/understeer feel)
@export var camera_yaw_lag_speed: float = 5.0  # How fast camera catches up to car's rotation (lower = more lag)

# Rotation speed during crash/tumble
@export var crash_rotation_lerp_speed: float = 3.0

# When to slow down rotation
@export var tilt_threshold_for_slow_camera: float = 45.0  # Start slowing camera rotation at this tilt

# Mouselook settings
@export var mouse_sensitivity: float = 0.3  # Mouse look sensitivity
@export var max_mouse_pitch: float = 60.0  # Max degrees to look up/down
@export var auto_return_speed: float = 3.0  # How fast camera returns to default after mouselook

# Auto-return mode
@export_category("Auto-return")
@export var use_velocity_based_reset: bool = true  # If true, reset when moving fast; if false, reset after delay
@export var auto_return_delay: float = 2.0  # (Time-based) Seconds of no mouse input before auto-return
@export var velocity_reset_threshold: float = 15.0  # (Velocity-based) Min speed to trigger reset
@export var velocity_consistency_time: float = 3.0  # (Velocity-based) How long to move consistently before reset
@export var direction_consistency_threshold: float = 0.9  # (Velocity-based) Dot product for "same direction" (~25 deg)

# Click vs hold detection
@export var click_threshold: float = 0.2  # Max seconds to count as a "click" vs "hold"
@export var default_position_threshold: float = 0.05  # Radians - how close to 0 to count as "default"
@export var manual_reset_speed: float = 5.0  # How fast camera returns when right-clicking to reset

# Velocity look-ahead
@export var velocity_look_ahead: float = 0.5  # How much to look towards velocity (0 = at car, 1 = full velocity direction)
@export var velocity_look_ahead_distance: float = 20.0  # Max distance to offset look target
@export var velocity_look_min_speed: float = 10.0  # Min speed before look-ahead kicks in
@export var velocity_look_smoothing: float = 3.0  # How smoothly the look-ahead transitions

# Internal state
var camera_yaw: float = 0.0  # Current camera yaw angle (radians)
var mouse_yaw_offset: float = 0.0  # Mouse look yaw offset (radians)
var mouse_pitch_offset: float = 0.0  # Mouse look pitch offset (radians)
var time_since_mouse_input: float = 0.0  # Timer for auto-return (time-based mode)
var is_mouselooking: bool = false  # Whether mouselook is active
var consistent_velocity_time: float = 0.0  # How long car has moved in same direction (velocity-based mode)
var last_velocity_direction: Vector3 = Vector3.ZERO  # Previous frame's velocity direction
var right_click_start_time: float = 0.0  # When right-click was pressed
var right_click_mouse_moved: bool = false  # Whether mouse moved during right-click
var manual_reset_active: bool = false  # Whether we're smoothly resetting from a right-click
var current_look_offset: Vector3 = Vector3.ZERO  # Smoothed velocity look-ahead offset

func _ready():
	# Start with mouse visible - only capture when right-click is held
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event):
	# Handle mouse button press/release for capture and click detection
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				right_click_start_time = Time.get_ticks_msec() / 1000.0
				right_click_mouse_moved = false
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				# Check if this was a quick click (not a hold)
				var hold_duration = Time.get_ticks_msec() / 1000.0 - right_click_start_time
				if hold_duration < click_threshold and not right_click_mouse_moved:
					# Instant reset camera to default
					_reset_camera_to_default()

	# Handle mouse movement for mouselook
	if event is InputEventMouseMotion:
		# Right mouse button or middle mouse button for mouselook
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			right_click_mouse_moved = true  # Mark that mouse moved during click
			is_mouselooking = true
			time_since_mouse_input = 0.0  # Reset timer

			# Apply mouse movement to offsets
			mouse_yaw_offset -= event.relative.x * deg_to_rad(mouse_sensitivity)
			mouse_pitch_offset -= event.relative.y * deg_to_rad(mouse_sensitivity)

			# Clamp pitch to prevent flipping
			mouse_pitch_offset = clamp(mouse_pitch_offset, deg_to_rad(-max_mouse_pitch), deg_to_rad(max_mouse_pitch))

func _reset_camera_to_default():
	# Start smooth reset of mouselook offsets
	manual_reset_active = true
	is_mouselooking = false
	consistent_velocity_time = 0.0

	# Snap camera_yaw to car's current heading to avoid stale rotation
	if target:
		var target_forward = -target.global_transform.basis.z
		var target_yaw_forward = Vector3(target_forward.x, 0, target_forward.z).normalized()
		if target_yaw_forward.length() > 0.01:
			camera_yaw = atan2(target_yaw_forward.x, target_yaw_forward.z)

	# Normalize yaw offset to take shortest path
	while mouse_yaw_offset > PI:
		mouse_yaw_offset -= TAU
	while mouse_yaw_offset < -PI:
		mouse_yaw_offset += TAU

func is_at_default_position() -> bool:
	# Check if camera is at default position (no significant mouselook offset)
	return abs(mouse_yaw_offset) < default_position_threshold and abs(mouse_pitch_offset) < default_position_threshold

func _physics_process(delta):
	if !target:
		return

	# Check car's tilt to determine rotation speed
	var car_up = target.global_transform.basis.y
	var tilt_angle = rad_to_deg(acos(clamp(car_up.dot(Vector3.UP), -1.0, 1.0)))
	var car_is_stable = target.is_stable if "is_stable" in target else true

	# Extract car's yaw angle
	var target_forward = -target.global_transform.basis.z
	var target_yaw_forward = Vector3(target_forward.x, 0, target_forward.z).normalized()

	# Handle case where car is pointing straight up/down
	if target_yaw_forward.length() < 0.01:
		target_yaw_forward = -target.global_transform.basis.x
		target_yaw_forward.y = 0
		target_yaw_forward = target_yaw_forward.normalized()

	# Calculate target yaw angle from car
	var target_yaw = atan2(target_yaw_forward.x, target_yaw_forward.z)

	# Mouselook auto-return logic
	if is_mouselooking:
		# Not actively mouselooking if no mouse buttons pressed
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			is_mouselooking = false

	# Determine if we should auto-return
	var should_return: bool = false

	if not is_mouselooking:
		if use_velocity_based_reset:
			# Velocity-based: reset when car is moving fast in consistent direction
			var velocity = target.linear_velocity if "linear_velocity" in target else Vector3.ZERO
			var speed = velocity.length()
			var current_direction = velocity.normalized() if speed > 0.1 else Vector3.ZERO

			if speed > velocity_reset_threshold:
				# Check if direction is consistent with previous frame
				if last_velocity_direction.length() > 0.1 and current_direction.dot(last_velocity_direction) > direction_consistency_threshold:
					consistent_velocity_time += delta
				else:
					consistent_velocity_time = 0.0
				last_velocity_direction = current_direction
			else:
				consistent_velocity_time = 0.0
				last_velocity_direction = Vector3.ZERO

			should_return = consistent_velocity_time >= velocity_consistency_time
		else:
			# Time-based: reset after delay (original behavior)
			time_since_mouse_input += delta
			should_return = time_since_mouse_input >= auto_return_delay

	# Apply auto-return if conditions are met
	if should_return:
		# Normalize yaw offset to -PI to PI to take the shortest path (fixes the "laps" bug)
		while mouse_yaw_offset > PI:
			mouse_yaw_offset -= TAU
		while mouse_yaw_offset < -PI:
			mouse_yaw_offset += TAU

		# Lerp mouse offsets back to 0
		mouse_yaw_offset = lerp(mouse_yaw_offset, 0.0, auto_return_speed * delta)
		mouse_pitch_offset = lerp(mouse_pitch_offset, 0.0, auto_return_speed * delta)

	# Apply manual reset (from right-click) with smooth interpolation
	if manual_reset_active:
		mouse_yaw_offset = lerp(mouse_yaw_offset, 0.0, manual_reset_speed * delta)
		mouse_pitch_offset = lerp(mouse_pitch_offset, 0.0, manual_reset_speed * delta)

		# Check if we've reached default position
		if is_at_default_position():
			manual_reset_active = false
			mouse_yaw_offset = 0.0
			mouse_pitch_offset = 0.0

	# Determine yaw lerp speed based on car stability
	var current_yaw_speed = camera_yaw_lag_speed
	if not car_is_stable or tilt_angle > tilt_threshold_for_slow_camera:
		# Slow down camera during crashes
		current_yaw_speed = crash_rotation_lerp_speed

	# Smoothly lerp camera yaw towards car's yaw (creates lag effect)
	# But ONLY if camera is at default position - otherwise freeze camera yaw
	# This makes Q/E not rotate the camera when you've manually positioned it
	if is_at_default_position():
		# Normalize angle difference to handle wraparound
		var yaw_diff = target_yaw - camera_yaw
		while yaw_diff > PI:
			yaw_diff -= TAU
		while yaw_diff < -PI:
			yaw_diff += TAU

		camera_yaw += yaw_diff * current_yaw_speed * delta

	# Calculate effective yaw including mouse offset
	var effective_yaw = camera_yaw + mouse_yaw_offset

	# Create basis from effective yaw (camera's base rotation)
	var yaw_basis = Basis()
	yaw_basis = yaw_basis.rotated(Vector3.UP, effective_yaw)

	# Calculate base camera position (without pitch offset)
	var offset_rotated = yaw_basis * offset
	var base_camera_position = target.global_position + offset_rotated

	# Apply pitch rotation around the car's position
	# This keeps the car centered when looking up/down
	if abs(mouse_pitch_offset) > 0.001:
		# Get the vector from car to camera
		var to_camera = base_camera_position - target.global_position

	 		# Get right vector for pitch axis (perpendicular to car-to-camera direction)
		var right = to_camera.cross(Vector3.UP).normalized()

		# Rotate the camera position around the car
		to_camera = to_camera.rotated(right, mouse_pitch_offset)

		# Set final camera position
		var target_position = target.global_position + to_camera
		global_position = global_position.lerp(target_position, position_lerp_speed * delta)
	else:
		# No pitch offset, use base position
		global_position = global_position.lerp(base_camera_position, position_lerp_speed * delta)

	# Calculate look-at target with velocity look-ahead
	var target_look_offset = Vector3.ZERO

	if velocity_look_ahead > 0:
		var velocity = target.linear_velocity if "linear_velocity" in target else Vector3.ZERO
		var speed = velocity.length()

		if speed > velocity_look_min_speed:
			# Scale look-ahead by speed (faster = more look-ahead)
			var speed_factor = clamp((speed - velocity_look_min_speed) / 50.0, 0.0, 1.0)
			target_look_offset = velocity.normalized() * velocity_look_ahead_distance * speed_factor * velocity_look_ahead

	# Smoothly interpolate the look offset
	current_look_offset = current_look_offset.lerp(target_look_offset, velocity_look_smoothing * delta)
	var look_target = target.global_position + current_look_offset

	# Calculate final camera orientation
	var direction_to_target = (look_target - global_position).normalized()

	# Build final basis looking at target
	if direction_to_target.length() > 0.01:
		# Use look_at style basis construction
		var right = direction_to_target.cross(Vector3.UP).normalized()
		var up = right.cross(direction_to_target).normalized()
		var final_basis = Basis(right, up, -direction_to_target)
		global_transform.basis = final_basis
