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
@export var auto_return_delay: float = 2.0  # Seconds of no mouse input before auto-return starts
@export var auto_return_speed: float = 3.0  # How fast camera returns to default after mouselook

# Internal state
var camera_yaw: float = 0.0  # Current camera yaw angle (radians)
var mouse_yaw_offset: float = 0.0  # Mouse look yaw offset (radians)
var mouse_pitch_offset: float = 0.0  # Mouse look pitch offset (radians)
var time_since_mouse_input: float = 0.0  # Timer for auto-return
var is_mouselooking: bool = false  # Whether mouselook is active

func _ready():
	# Capture mouse for mouselook
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	# Handle mouse movement for mouselook
	if event is InputEventMouseMotion:
		# Right mouse button or middle mouse button for mouselook
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			is_mouselooking = true
			time_since_mouse_input = 0.0  # Reset timer

			# Apply mouse movement to offsets
			mouse_yaw_offset -= event.relative.x * deg_to_rad(mouse_sensitivity)
			mouse_pitch_offset -= event.relative.y * deg_to_rad(mouse_sensitivity)

			# Clamp pitch to prevent flipping
			mouse_pitch_offset = clamp(mouse_pitch_offset, deg_to_rad(-max_mouse_pitch), deg_to_rad(max_mouse_pitch))

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

	# Handle auto-return timer
	if not is_mouselooking:
		time_since_mouse_input += delta

		# After delay, start returning to default
		if time_since_mouse_input >= auto_return_delay:
			# Lerp mouse offsets back to 0
			mouse_yaw_offset = lerp(mouse_yaw_offset, 0.0, auto_return_speed * delta)
			mouse_pitch_offset = lerp(mouse_pitch_offset, 0.0, auto_return_speed * delta)

	# Determine yaw lerp speed based on car stability
	var current_yaw_speed = camera_yaw_lag_speed
	if not car_is_stable or tilt_angle > tilt_threshold_for_slow_camera:
		# Slow down camera during crashes
		current_yaw_speed = crash_rotation_lerp_speed

	# Smoothly lerp camera yaw towards car's yaw (creates lag effect)
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

	# Calculate final camera orientation - always look at the car
	var direction_to_car = (target.global_position - global_position).normalized()

	# Build final basis looking at car
	if direction_to_car.length() > 0.01:
		# Use look_at style basis construction
		var right = direction_to_car.cross(Vector3.UP).normalized()
		var up = right.cross(direction_to_car).normalized()
		var final_basis = Basis(right, up, -direction_to_car)
		global_transform.basis = final_basis
