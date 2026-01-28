extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 1, -5)  # Negative Z to position camera behind car

# Position following (keep high for responsive camera)
@export var position_lerp_speed: float = 25.0  # How fast camera position follows car

# Camera yaw lag (creates over/understeer feel)
@export var camera_yaw_lag_speed: float = 2.0  # How fast camera catches up to car's rotation (lower = more lag)

# Rotation speed during crash/tumble
@export var crash_rotation_lerp_speed: float = 3.0

# When to slow down rotation
@export var tilt_threshold_for_slow_camera: float = 45.0  # Start slowing camera rotation at this tilt

# Mouselook settings
@export var mouse_sensitivity: float = 0.3  # Mouse look sensitivity
@export var max_mouse_pitch: float = 60.0  # Max degrees to look up/down

# Auto-return settings
@export_category("Auto Return")
@export var auto_return_speed: float = 3.0  # How fast camera returns to default

# Change-based auto-return: camera resets when driving changes significantly
@export_subgroup("Change Detection")
@export var direction_change_threshold: float = 0.7  # Dot product threshold (~45 deg change triggers reset)
@export var speed_change_threshold: float = 0.5  # Percentage speed change to trigger reset (0.5 = 50%)
@export var min_speed_for_tracking: float = 5.0  # Below this speed, don't track changes

# Click vs hold detection
@export var click_threshold: float = 0.2  # Max seconds to count as a "click" vs "hold"
@export var default_position_threshold: float = 0.05  # Radians - how close to 0 to count as "default"
@export var manual_reset_speed: float = 5.0  # How fast camera returns when right-clicking to reset

# Velocity look-ahead
@export var velocity_look_ahead: float = 0.5  # How much to look towards velocity (0 = at car, 1 = full velocity direction)
@export var velocity_look_ahead_distance: float = 20.0  # Max distance to offset look target
@export var velocity_look_min_speed: float = 10.0  # Min speed before look-ahead kicks in
@export var velocity_look_smoothing: float = 3.0  # How smoothly the look-ahead transitions

# Camera pitch following car
@export_category("Pitch Following")
@export var follow_car_pitch: bool = true  # Camera tilts with car's pitch
@export var pitch_follow_amount: float = 0.5  # How much to follow car pitch (0 = none, 1 = full)
@export var pitch_follow_smoothing: float = 5.0  # How smoothly pitch follows

# Internal state
var camera_yaw: float = 0.0  # Current camera yaw angle (radians)
var mouse_yaw_offset: float = 0.0  # Mouse look yaw offset (radians)
var mouse_pitch_offset: float = 0.0  # Mouse look pitch offset (radians)
var current_car_pitch: float = 0.0  # Smoothed car pitch for camera follow
var is_mouselooking: bool = false  # Whether mouselook is active
var right_click_start_time: float = 0.0  # When right-click was pressed
var right_click_mouse_moved: bool = false  # Whether mouse moved during right-click
var manual_reset_active: bool = false  # Whether we're smoothly resetting from a right-click
var current_look_offset: Vector3 = Vector3.ZERO  # Smoothed velocity look-ahead offset

# Change-based auto-return: baseline captured when user sets camera position
var baseline_direction: Vector3 = Vector3.ZERO  # Direction when camera was positioned
var baseline_speed: float = 0.0  # Speed when camera was positioned
var has_baseline: bool = false  # Whether we have a valid baseline to compare against
var auto_returning: bool = false  # Whether we're currently auto-returning to default

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
					# Quick click = reset camera to default (works in both modes)
					_reset_camera_to_default()

	# Handle mouse movement for mouselook
	if event is InputEventMouseMotion:
		# Right mouse button or middle mouse button for mouselook
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			right_click_mouse_moved = true  # Mark that mouse moved during click
			is_mouselooking = true
			has_baseline = false  # Invalidate baseline while actively mouselooking
			auto_returning = false  # Cancel any auto-return in progress

			# Apply mouse movement to offsets
			mouse_yaw_offset -= event.relative.x * deg_to_rad(mouse_sensitivity)
			mouse_pitch_offset -= event.relative.y * deg_to_rad(mouse_sensitivity)

			# Clamp pitch to prevent flipping
			mouse_pitch_offset = clamp(mouse_pitch_offset, deg_to_rad(-max_mouse_pitch), deg_to_rad(max_mouse_pitch))

func _reset_camera_to_default():
	# Start smooth reset of mouselook offsets
	manual_reset_active = true
	is_mouselooking = false
	has_baseline = false  # Clear baseline on manual reset
	auto_returning = false  # Cancel any auto-return in progress

	# FIX: To avoid the "jump" bug, we need to keep effective_yaw constant
	# while transferring the offset to camera_yaw
	if target:
		var target_forward = -target.global_transform.basis.z
		var target_yaw_forward = Vector3(target_forward.x, 0, target_forward.z).normalized()
		if target_yaw_forward.length() > 0.01:
			var target_yaw = atan2(target_yaw_forward.x, target_yaw_forward.z)

			# Current effective yaw (what the camera is actually showing)
			var current_effective_yaw = camera_yaw + mouse_yaw_offset

			# Snap camera_yaw to car's heading
			camera_yaw = target_yaw

			# Adjust mouse_yaw_offset so effective_yaw stays the same
			# effective_yaw = camera_yaw + mouse_yaw_offset
			# current_effective_yaw = new_camera_yaw + new_mouse_yaw_offset
			# new_mouse_yaw_offset = current_effective_yaw - new_camera_yaw
			mouse_yaw_offset = current_effective_yaw - camera_yaw

	# Normalize yaw offset to take shortest path to 0
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

	# Get current velocity info
	var velocity = target.linear_velocity if "linear_velocity" in target else Vector3.ZERO
	var speed = velocity.length()
	var current_direction = velocity.normalized() if speed > 0.1 else Vector3.ZERO

	# Mouselook state management
	if is_mouselooking:
		# Not actively mouselooking if no mouse buttons pressed
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			is_mouselooking = false
			auto_returning = false  # Stop any auto-return when user takes control
			# Capture baseline when mouselook ends (if camera was moved from default)
			if not is_at_default_position() and speed > min_speed_for_tracking:
				baseline_direction = current_direction
				baseline_speed = speed
				has_baseline = true

	# Determine if we should START auto-returning based on CHANGES in driving
	if not is_mouselooking and not is_at_default_position() and not auto_returning:
		if has_baseline and speed > min_speed_for_tracking:
			# Check for significant direction change
			var direction_changed = false
			if baseline_direction.length() > 0.1 and current_direction.length() > 0.1:
				var dot = current_direction.dot(baseline_direction)
				direction_changed = dot < direction_change_threshold

			# Check for significant speed change
			var speed_changed = false
			if baseline_speed > min_speed_for_tracking:
				var speed_ratio = speed / baseline_speed
				# Trigger if speed changed by more than threshold (either faster or slower)
				speed_changed = speed_ratio < (1.0 - speed_change_threshold) or speed_ratio > (1.0 + speed_change_threshold)

			if direction_changed or speed_changed:
				auto_returning = true
				has_baseline = false
		elif not has_baseline and speed > min_speed_for_tracking:
			# No baseline yet but moving - capture one now
			baseline_direction = current_direction
			baseline_speed = speed
			has_baseline = true

	# Apply auto-return animation until we reach default
	if auto_returning:
		# Normalize yaw offset to -PI to PI to take the shortest path (fixes the "laps" bug)
		while mouse_yaw_offset > PI:
			mouse_yaw_offset -= TAU
		while mouse_yaw_offset < -PI:
			mouse_yaw_offset += TAU

		# Lerp mouse offsets back to 0
		mouse_yaw_offset = lerp(mouse_yaw_offset, 0.0, auto_return_speed * delta)
		mouse_pitch_offset = lerp(mouse_pitch_offset, 0.0, auto_return_speed * delta)

		# Stop when we've reached default
		if is_at_default_position():
			auto_returning = false
			mouse_yaw_offset = 0.0
			mouse_pitch_offset = 0.0

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

	if velocity_look_ahead > 0 and speed > velocity_look_min_speed:
		# Scale look-ahead by speed (faster = more look-ahead)
		var speed_factor = clamp((speed - velocity_look_min_speed) / 50.0, 0.0, 1.0)

		# Reduce look-ahead when looking backwards (prevents instability)
		var camera_forward = -global_transform.basis.z
		var velocity_dir = velocity.normalized()
		var look_alignment = camera_forward.dot(velocity_dir)  # 1 = looking forward, -1 = looking back

		# Fade out look-ahead as we look backwards
		var look_ahead_factor = clamp((look_alignment + 1.0) / 2.0, 0.0, 1.0)  # Map -1..1 to 0..1

		target_look_offset = velocity_dir * velocity_look_ahead_distance * speed_factor * velocity_look_ahead * look_ahead_factor

	# Smoothly interpolate the look offset
	current_look_offset = current_look_offset.lerp(target_look_offset, velocity_look_smoothing * delta)
	var look_target = target.global_position + current_look_offset

	# Calculate car pitch for camera following
	var car_pitch_offset: float = 0.0
	if follow_car_pitch:
		var car_forward = -target.global_transform.basis.z
		var car_pitch = asin(clamp(car_forward.y, -1.0, 1.0))  # Positive Y = nose up = camera tilts up
		current_car_pitch = lerp(current_car_pitch, car_pitch * pitch_follow_amount, pitch_follow_smoothing * delta)
		car_pitch_offset = current_car_pitch

	# Calculate final camera orientation
	var direction_to_target = (look_target - global_position).normalized()

	# Build final basis looking at target
	if direction_to_target.length() > 0.01:
		# Use look_at style basis construction
		var right = direction_to_target.cross(Vector3.UP).normalized()
		var up = right.cross(direction_to_target).normalized()
		var final_basis = Basis(right, up, -direction_to_target)

		# Apply car pitch offset
		if abs(car_pitch_offset) > 0.001:
			final_basis = final_basis.rotated(right, car_pitch_offset)

		global_transform.basis = final_basis
