class_name FreeCam
extends Camera3D

# Simple fly camera for testing/exploring the city

@export var move_speed: float = 500.0  # m/s base speed
@export var sprint_multiplier: float = 5.0
@export var mouse_sensitivity: float = 0.002

var velocity: Vector3 = Vector3.ZERO
var captured: bool = true


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent):
	# Toggle mouse capture with Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			captured = true

	# Mouse look
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		# Clamp pitch
		rotation.x = clamp(rotation.x, -PI / 2, PI / 2)


func _process(delta: float):
	if not captured:
		return

	# Movement input
	var input_dir = Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		input_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		input_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		input_dir += transform.basis.x
	if Input.is_key_pressed(KEY_SPACE):
		input_dir += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		input_dir -= Vector3.UP

	input_dir = input_dir.normalized()

	# Speed
	var speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier

	# Scroll wheel to adjust base speed
	# (handled in _unhandled_input for scroll)

	position += input_dir * speed * delta


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed *= 1.2
			print("FreeCam speed: %.0f m/s" % move_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed /= 1.2
			print("FreeCam speed: %.0f m/s" % move_speed)
