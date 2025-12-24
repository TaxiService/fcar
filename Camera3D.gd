extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 1, 5)

# Position following (keep high for responsive camera)
@export var position_lerp_speed: float = 25.0  # How fast camera position follows car

# Rotation speeds for stable flight
@export var rotation_lerp_speed: float = 8.0

# Rotation speed during crash/tumble
@export var crash_rotation_lerp_speed: float = 3.0

# When to slow down rotation
@export var tilt_threshold_for_slow_camera: float = 45.0  # Start slowing camera rotation at this tilt

func _physics_process(delta):
	if !target:
		return

	# Check car's tilt to determine rotation speed
	var car_up = target.global_transform.basis.y
	var tilt_angle = rad_to_deg(acos(clamp(car_up.dot(Vector3.UP), -1.0, 1.0)))
	var car_is_stable = target.is_stable if "is_stable" in target else true

	# Determine rotation speed based on tilt/stability
	# Position always follows fast - rotation slows during crashes
	var current_rotation_speed = rotation_lerp_speed
	if not car_is_stable or tilt_angle > tilt_threshold_for_slow_camera:
		# Car is crashing or heavily tilted - slow rotation only
		current_rotation_speed = crash_rotation_lerp_speed

	# Extract only the yaw (Y-axis rotation) from the target
	# This prevents camera from rolling/pitching with the car
	# In Godot, -Z is forward, so we use -basis.z
	var target_forward = -target.global_transform.basis.z
	var target_yaw_forward = Vector3(target_forward.x, 0, target_forward.z).normalized()

	# Handle case where car is pointing straight up/down
	if target_yaw_forward.length() < 0.01:
		target_yaw_forward = -target.global_transform.basis.x
		target_yaw_forward.y = 0
		target_yaw_forward = target_yaw_forward.normalized()

	# Create a transform that only follows yaw, not roll/pitch
	var yaw_basis = Basis.looking_at(target_yaw_forward, Vector3.UP)

	# Calculate camera target position using yaw-only rotation
	var offset_rotated = yaw_basis * offset
	var target_position = target.global_position + offset_rotated

	# Position follows car directly (fast, no lag)
	global_position = global_position.lerp(target_position, position_lerp_speed * delta)

	# Rotation follows smoothly (this is where we prevent jarring movements)
	var look_target = target.global_position
	var current_forward = -global_transform.basis.z
	var desired_forward = (look_target - global_position).normalized()
	var smoothed_forward = current_forward.lerp(desired_forward, current_rotation_speed * delta).normalized()

	# Update camera orientation
	if smoothed_forward.length() > 0.01:
		var new_basis = Basis.looking_at(smoothed_forward, Vector3.UP)
		global_transform.basis = new_basis
