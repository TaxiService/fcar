extends RigidBody3D

var lock_height: bool = false
var target_height: float
var is_stable: bool = true  # Tracks if car is stable enough for stabilizers/wheels
var disabled_time_remaining: float = 0.0  # Time until stabilizers can re-enable
var grace_period_remaining: float = 0.0  # Immunity period after recovery

@export var vertical_force: float = 75.0
@export var forward_force: float = 75.0
@export var backward_force: float = 65.0
@export var sideways_force: float = 50.0
@export var yaw_torque: float = 3.5
@export var stabilizer_strength: float = 20.0
@export var max_tilt_for_stabilizer: float = 60.0  # Disable stabilizer beyond this tilt angle (degrees)
@export var recovery_time: float = 2.0  # How long stabilizers stay disabled after exceeding tilt
@export var grace_period: float = 4.0  # Immunity time after recovery - can't be disabled again
@export var auto_flip_strength: float = 30.0  # Torque to help flip car upright during grace period
@export var stable_angular_damp: float = 3.0  # Angular damping when stabilizers active
@export var unstable_angular_damp: float = 1.0  # Angular damping when disabled/tumbling
@export var stable_linear_damp: float = 2.0  # Linear damping when stabilizers active
@export var unstable_linear_damp: float = 1.0  # Linear damping when disabled/tumbling

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
		# Currently disabled - no control
		is_stable = false
	elif grace_period_remaining > 0.0:
		# In grace period - always stable, can't be disabled again
		is_stable = true
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

	# Only accept inputs if car is stable/operational
	if is_stable:
		if Input.is_action_just_pressed("height_brake"):
			engage_heightlock()

		if lock_height:
			apply_central_force(\
			Vector3.UP * mass * 2*(vertical_force/3) *\
			(target_height - global_transform.origin.y)\
			)

		if Input.is_action_pressed("jump"):
			if lock_height: target_height = global_transform.origin.y
			apply_central_force(Vector3.UP * vertical_force * mass)
		if Input.is_action_just_released("jump"):
			if lock_height: target_height = global_transform.origin.y

		if Input.is_action_pressed("crouch"):
			if lock_height: target_height = global_transform.origin.y
			apply_central_force(Vector3.DOWN * (vertical_force/2) * mass)
		if Input.is_action_just_released("crouch"):
			if lock_height: target_height = global_transform.origin.y

		if Input.is_action_pressed("forward"):
			apply_central_force(-global_transform.basis.z * forward_force * mass)
		if Input.is_action_pressed("backward"):
			apply_central_force(global_transform.basis.z * backward_force * mass)

		if Input.is_action_pressed("strafe_left"):
			apply_central_force(-global_transform.basis.x * sideways_force * mass)
		if Input.is_action_pressed("strafe_right"):
			apply_central_force(global_transform.basis.x * sideways_force * mass)

		# Simple turning with just yaw torque
		# Q turns right, E turns left
		if Input.is_action_pressed("turn_left"):  # Q key
			apply_torque(global_transform.basis.y * yaw_torque * mass * 1.0)
		if Input.is_action_pressed("turn_right"):  # E key
			apply_torque(global_transform.basis.y * yaw_torque * mass * -1.0)

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
