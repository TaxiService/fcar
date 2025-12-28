class_name StabilizerSystem
extends RefCounted

# Configuration (set by FCar)
var stabilizer_strength: float = 25.0
var auto_flip_strength: float = 25.0
var heading_hold_enabled: bool = true
var heading_hold_strength: float = 15.0
var stable_angular_damp: float = 1.8
var unstable_angular_damp: float = 0.8
var stable_linear_damp: float = 2.0
var unstable_linear_damp: float = 0.85
var max_tilt_for_stabilizer: float = 45.0


func apply_stabilization(
	body: RigidBody3D,
	car_up: Vector3,
	current_yaw_input: float,
	in_grace_period: bool,
	tilt_angle: float
) -> void:
	var delta_quat: Quaternion = Quaternion(car_up, Vector3.UP)
	var angle: float = delta_quat.get_angle()
	var axis: Vector3 = delta_quat.get_axis()

	if in_grace_period and tilt_angle > max_tilt_for_stabilizer:
		# Auto-flip mode: stronger torque to help flip car upright
		body.apply_torque(axis.normalized() * angle * body.mass * auto_flip_strength)
		body.apply_torque(-body.angular_velocity * body.mass * 1.5)
	else:
		# Normal stabilization
		body.apply_torque(-body.angular_velocity * body.mass)
		body.apply_torque(axis.normalized() * angle * body.mass * stabilizer_strength)

		# Heading hold
		if heading_hold_enabled and abs(current_yaw_input) < 0.1:
			var yaw_velocity = body.angular_velocity.dot(body.global_transform.basis.y)
			body.apply_torque(-body.global_transform.basis.y * yaw_velocity * body.mass * heading_hold_strength)


func update_damping(body: RigidBody3D, stabilizer_active: bool) -> void:
	if stabilizer_active:
		body.linear_damp = stable_linear_damp
		body.angular_damp = stable_angular_damp
	else:
		body.linear_damp = unstable_linear_damp
		body.angular_damp = unstable_angular_damp


func get_tilt_angle(car_up: Vector3) -> float:
	return rad_to_deg(acos(clamp(car_up.dot(Vector3.UP), -1.0, 1.0)))
