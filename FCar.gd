extends RigidBody3D

var lock_height: bool = false
var target_height: float

@export var vertical_force: float = 75.0
@export var forward_force: float = 75.0
@export var backward_force: float = 65.0
@export var sideways_force: float = 50.0
@export var yaw_torque: float = 3.0
@export var stabilizer_strength: float = 50.0

func engage_heightlock():
	lock_height = !lock_height
	target_height = global_transform.origin.y

func _physics_process(delta):
	if Input.is_action_just_pressed("height_brake"):
		engage_heightlock()

	if lock_height:
		#linear_damp = 3
		apply_central_force(\
		Vector3.UP * mass * 2*(vertical_force/3) *\
		(target_height - global_transform.origin.y)\
		)
	#if not lock_height:
		#linear_damp = 1
	
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

	if Input.is_action_pressed("turn_left"):
		apply_torque(global_transform.basis.z * yaw_torque*2 * mass)
		apply_torque(global_transform.basis.y * yaw_torque * mass)
		apply_torque(-global_transform.basis.x * yaw_torque*3 * mass)
	if Input.is_action_pressed("turn_right"):
		apply_torque(-global_transform.basis.z * yaw_torque*2 * mass)
		apply_torque(-global_transform.basis.y * yaw_torque * mass)
		apply_torque(-global_transform.basis.x * yaw_torque*3 * mass)

	#print(rad_to_deg(global_transform.basis.y.angle_to(Vector3.UP)) )
	#print(global_transform.basis.get_rotation_quaternion().get_angle())
	#print(global_transform.basis.get_rotation_quaternion().get_axis())
	
	var delta_quat: Quaternion = Quaternion(global_transform.basis.y, Vector3.UP)
	var angle: float = delta_quat.get_angle()
	var axis: Vector3 = delta_quat.get_axis()

	apply_torque(-angular_velocity * mass)
	apply_torque(axis.normalized() * angle * mass * stabilizer_strength)
