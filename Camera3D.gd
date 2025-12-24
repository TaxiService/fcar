extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 1, 5)
@export var lerp_speed: float = 20.0
@export var rotation_lerp_speed: float = 8.0  # Slower rotation follow for smoothness

func _physics_process(delta):
	if !target:
		return

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

	# Smoothly interpolate camera position
	global_position = global_position.lerp(target_position, lerp_speed * delta)

	# Smoothly look at the target
	var look_target = target.global_position
	var current_forward = -global_transform.basis.z
	var desired_forward = (look_target - global_position).normalized()
	var smoothed_forward = current_forward.lerp(desired_forward, rotation_lerp_speed * delta).normalized()

	# Update camera orientation
	if smoothed_forward.length() > 0.01:
		var new_basis = Basis.looking_at(smoothed_forward, Vector3.UP)
		global_transform.basis = new_basis
