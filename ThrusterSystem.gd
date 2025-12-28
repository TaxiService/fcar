class_name ThrusterSystem
extends RefCounted

# Wheel data structure
class WheelData:
	var node: Node3D
	var is_front: bool
	var is_left: bool

	func _init(n: Node3D, front: bool, left: bool):
		node = n
		is_front = front
		is_left = left

# CoM compensation data
var wheel_lever_arms: Array[Vector3] = []
var strafe_compensation: Array[float] = []
var pitch_compensation: Array[float] = []
var yaw_compensation: Array[float] = []
var throttle_compensation: Array[float] = []

# Configuration (set by FCar)
var max_thrust_angle: float = 50.0
var yaw_thrust_angle: float = 30.0
var pitch_differential: float = 0.5
var roll_differential: float = 0.35
var max_thrust: float = 10.0
var com_compensation_enabled: bool = true
var com_compensation_strength: float = 1.0


func calculate_com_compensation(wheel_nodes: Array, center_of_mass: Vector3, debug: bool = false) -> void:
	# Clear and recalculate
	wheel_lever_arms.clear()
	strafe_compensation.clear()
	pitch_compensation.clear()
	yaw_compensation.clear()
	throttle_compensation.clear()

	# First pass: calculate lever arms and find averages
	var total_abs_z = 0.0
	var total_abs_x = 0.0
	var total_horizontal_dist = 0.0
	var valid_count = 0

	for wheel in wheel_nodes:
		if wheel:
			var lever = wheel.position - center_of_mass
			wheel_lever_arms.append(lever)
			total_abs_z += abs(lever.z)
			total_abs_x += abs(lever.x)
			total_horizontal_dist += sqrt(lever.x * lever.x + lever.z * lever.z)
			valid_count += 1
		else:
			wheel_lever_arms.append(Vector3.ZERO)

	if valid_count == 0:
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
	for i in range(wheel_nodes.size()):
		if wheel_nodes[i]:
			var lever = wheel_lever_arms[i]

			# Strafe compensation
			if abs(lever.z) > 0.01:
				strafe_compensation.append(clamp(avg_abs_z / abs(lever.z), 0.3, 3.0))
			else:
				strafe_compensation.append(1.0)

			# Pitch compensation
			if abs(lever.x) > 0.01:
				pitch_compensation.append(clamp(avg_abs_x / abs(lever.x), 0.3, 3.0))
			else:
				pitch_compensation.append(1.0)

			# Yaw and throttle compensation
			var horizontal_dist = sqrt(lever.x * lever.x + lever.z * lever.z)
			if horizontal_dist > 0.01:
				var h_comp = clamp(avg_horizontal_dist / horizontal_dist, 0.3, 3.0)
				yaw_compensation.append(h_comp)
				throttle_compensation.append(h_comp)
			else:
				yaw_compensation.append(1.0)
				throttle_compensation.append(1.0)
		else:
			strafe_compensation.append(1.0)
			pitch_compensation.append(1.0)
			yaw_compensation.append(1.0)
			throttle_compensation.append(1.0)

	if debug:
		print("CoM compensation calculated:")
		print("  Center of Mass: ", center_of_mass)
		print("  Lever arms: ", wheel_lever_arms)
		print("  Strafe compensation: ", strafe_compensation)
		print("  Pitch compensation: ", pitch_compensation)
		print("  Yaw compensation: ", yaw_compensation)
		print("  Throttle compensation: ", throttle_compensation)


class ThrustResult:
	var direction: Vector3
	var magnitude: float
	var force: Vector3


func calculate_wheel_thrust(
	wheel_index: int,
	is_front: bool,
	is_left: bool,
	input_pitch: float,
	input_roll: float,
	input_yaw: float,
	throttle_boost: float,
	base_thrust: float,
	thrust_power: float,
	pitch_axis: Vector3,
	roll_axis: Vector3,
	mass: float
) -> ThrustResult:
	var result = ThrustResult.new()

	# Start with base tilt from movement input
	var tilt_pitch = input_pitch * max_thrust_angle
	var tilt_roll = input_roll * max_thrust_angle

	# Add yaw component with compensation
	var yaw_comp = 1.0
	if com_compensation_enabled and wheel_index < yaw_compensation.size():
		yaw_comp = pow(yaw_compensation[wheel_index], com_compensation_strength)
	var yaw_tilt = input_yaw * yaw_thrust_angle * yaw_comp
	if is_front:
		tilt_roll += yaw_tilt
	else:
		tilt_roll -= yaw_tilt

	# Calculate thrust direction
	var thrust_direction = Vector3.UP
	thrust_direction = thrust_direction.rotated(pitch_axis, deg_to_rad(tilt_pitch))
	thrust_direction = thrust_direction.rotated(roll_axis, deg_to_rad(tilt_roll))

	# Altitude compensation (capped at 1.5x)
	var total_tilt = sqrt(tilt_pitch * tilt_pitch + tilt_roll * tilt_roll)
	total_tilt = clamp(total_tilt, 0.0, 89.0)
	var altitude_compensation = minf(1.0 / cos(deg_to_rad(total_tilt)), 1.5)

	# Thrust differential
	var thrust_multiplier = 1.0
	if is_front:
		thrust_multiplier -= input_pitch * pitch_differential
	else:
		thrust_multiplier += input_pitch * pitch_differential

	if is_left:
		thrust_multiplier -= input_roll * roll_differential
	else:
		thrust_multiplier += input_roll * roll_differential

	# Reduce differential on diagonal movement
	var diagonal_factor = abs(input_pitch) * abs(input_roll)
	if diagonal_factor > 0.0:
		thrust_multiplier = lerp(thrust_multiplier, 1.0, diagonal_factor * 0.7)
	thrust_multiplier = clamp(thrust_multiplier, 0.1, 2.0)

	# CoM compensation
	var com_comp = 1.0
	if com_compensation_enabled and wheel_index < throttle_compensation.size():
		var strafe_weight = abs(input_roll)
		var pitch_weight = abs(input_pitch)
		var throttle_weight = abs(throttle_boost)
		var total_weight = strafe_weight + pitch_weight + throttle_weight

		if total_weight > 0.01:
			var s_comp = pow(strafe_compensation[wheel_index], com_compensation_strength) if wheel_index < strafe_compensation.size() else 1.0
			var p_comp = pow(pitch_compensation[wheel_index], com_compensation_strength) if wheel_index < pitch_compensation.size() else 1.0
			var t_comp = pow(throttle_compensation[wheel_index], com_compensation_strength)
			com_comp = (s_comp * strafe_weight + p_comp * pitch_weight + t_comp * throttle_weight) / total_weight

	# Calculate final thrust magnitude
	var effective_base = maxf(base_thrust + throttle_boost, 0.0)
	var thrust_magnitude = effective_base * altitude_compensation * thrust_multiplier * com_comp * thrust_power
	thrust_magnitude = clamp(thrust_magnitude, 0.0, max_thrust)

	result.direction = thrust_direction
	result.magnitude = thrust_magnitude
	result.force = thrust_direction * thrust_magnitude * mass

	return result
