class_name BoosterSystem
extends RefCounted

# Node references
var booster_left: Node3D
var booster_right: Node3D
var thigh_left: Node3D
var thigh_right: Node3D
var shin_left: Node3D
var shin_right: Node3D
var exhaust_left: Node3D
var exhaust_right: Node3D

# Configuration
var thigh_rotation_min: float = -180.0  # degrees
var thigh_rotation_max: float = 0.0  # degrees
var shin_rotation_min: float = 0.0  # degrees
var shin_rotation_max: float = 45.0  # degrees
var max_thrust: float = 100000.0  # boosters should be powerful

# Default rotation angles (degrees)
var default_thigh_angle: float = -50.0  # negative = pointing back
var default_shin_angle: float = 35.0

# Current rotation state (degrees)
var thigh_angle_left: float = 0.0
var thigh_angle_right: float = 0.0
var shin_angle_left: float = 0.0
var shin_angle_right: float = 0.0

# Thrust state
var thrust_power: float = 0.0  # 0.0 to 1.0


func initialize(fcar: Node3D) -> bool:
	# Get booster root nodes
	booster_left = fcar.get_node_or_null("booster-L")
	booster_right = fcar.get_node_or_null("booster-R")

	if not booster_left or not booster_right:
		push_warning("BoosterSystem: Could not find booster nodes")
		return false

	# Get thigh nodes
	thigh_left = booster_left.get_node_or_null("thigh")
	thigh_right = booster_right.get_node_or_null("thigh")

	if not thigh_left or not thigh_right:
		push_warning("BoosterSystem: Could not find thigh nodes")
		return false

	# Get shin nodes - shin is a child of thigh
	shin_left = thigh_left.get_node_or_null("shin")
	shin_right = thigh_right.get_node_or_null("shin")

	if not shin_left or not shin_right:
		push_warning("BoosterSystem: Could not find shin nodes")
		return false

	# Get exhaust nodes (thrust direction reference)
	exhaust_left = shin_left.get_node_or_null("exhaust")
	exhaust_right = shin_right.get_node_or_null("exhaust")

	if not exhaust_left or not exhaust_right:
		push_warning("BoosterSystem: Could not find exhaust nodes")
		return false

	# Set default rotations
	thigh_angle_left = default_thigh_angle
	thigh_angle_right = default_thigh_angle
	shin_angle_left = default_shin_angle
	shin_angle_right = default_shin_angle
	_apply_rotations()

	return true


func set_thigh_angles(left: float, right: float) -> void:
	thigh_angle_left = clamp(left, thigh_rotation_min, thigh_rotation_max)
	thigh_angle_right = clamp(right, thigh_rotation_min, thigh_rotation_max)
	_apply_rotations()


func set_shin_angles(left: float, right: float) -> void:
	shin_angle_left = clamp(left, shin_rotation_min, shin_rotation_max)
	shin_angle_right = clamp(right, shin_rotation_min, shin_rotation_max)
	_apply_rotations()


func set_thrust(power: float) -> void:
	thrust_power = clamp(power, 0.0, 1.0)


func _apply_rotations() -> void:
	# Apply thigh rotations (around local Y)
	if thigh_left:
		thigh_left.rotation.y = deg_to_rad(thigh_angle_left)
	if thigh_right:
		thigh_right.rotation.y = -deg_to_rad(thigh_angle_right)

	# Apply shin rotations (around local Y, relative to thigh)
	if shin_left:
		shin_left.rotation.y = deg_to_rad(shin_angle_left)
	if shin_right:
		shin_right.rotation.y = -deg_to_rad(shin_angle_right)


func apply_thrust(body: RigidBody3D, delta: float) -> void:
	if thrust_power <= 0.0:
		return

	var force_magnitude = max_thrust * thrust_power

	# Left booster
	if exhaust_left:
		# Thrust comes out of exhaust - which direction is "out"?
		# Looking at scene: exhaust is rotated 90° so its local -Z points outward
		var thrust_dir = exhaust_left.global_transform.basis.y.normalized()
		var force_pos = exhaust_left.global_position - body.global_position
		body.apply_force(thrust_dir * force_magnitude, force_pos)

	# Right booster
	if exhaust_right:
		var thrust_dir = exhaust_right.global_transform.basis.y.normalized()
		var force_pos = exhaust_right.global_position - body.global_position
		body.apply_force(thrust_dir * force_magnitude, force_pos)


# Debug: get current thrust directions (for visualization)
func get_thrust_directions() -> Dictionary:
	var result = {}
	if exhaust_left:
		result["left"] = {
			"position": exhaust_left.global_position,
			"direction": exhaust_left.global_transform.basis.y.normalized()
		}
	if exhaust_right:
		result["right"] = {
			"position": exhaust_right.global_position,
			"direction": exhaust_right.global_transform.basis.y.normalized()
		}
	return result
