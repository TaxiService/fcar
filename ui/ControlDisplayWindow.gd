class_name ControlDisplayWindow
extends Control

# Control visualization window showing keyboard layout
# Displays pressed and locked states for game controls

var window_title: String = "Controls"
var car_ref: Node = null

# Key button references
var key_buttons: Dictionary = {}

# Frame throttling for performance
var _frame_counter: int = 0
const UPDATE_EVERY_N_FRAMES: int = 3

# Layout constants
const KEY_SIZE = Vector2(40, 30)
const KEY_GAP = 4
const CLUSTER_GAP = 60


func _ready():
	_build_ui()


func set_car(car: Node):
	car_ref = car


func _build_ui():
	# Left cluster: WASD + Q E + Shift F
	var left_x = 20
	var left_y = 10
	var left_x_staggered = 0
	
	# Row 0: Q W E R T
	_add_key("Q", "turn_left", Vector2(left_x, left_y))
	_add_key("W", "forward", Vector2(left_x + KEY_SIZE.x + KEY_GAP, left_y))
	_add_key("E", "turn_right", Vector2(left_x + (KEY_SIZE.x + KEY_GAP) * 2, left_y))
	_add_key("R", "confirm", Vector2(left_x + (KEY_SIZE.x + KEY_GAP) * 3.5, left_y), false, 0, false)  # Non-lockable circle
	_add_key("T", "cancel", Vector2(left_x + (KEY_SIZE.x + KEY_GAP) * 4.5, left_y), false, 0, false)  # Non-lockable circle
	
	# Row 1: A S D F
	var row1_y = left_y + KEY_SIZE.y + KEY_GAP
	_add_key("A", "strafe_left", Vector2(left_x, row1_y))
	_add_key("S", "backward", Vector2(left_x + KEY_SIZE.x + KEY_GAP, row1_y))
	_add_key("D", "strafe_right", Vector2(left_x + (KEY_SIZE.x + KEY_GAP) * 2, row1_y))
	_add_key("F", "toggle_control_lock", Vector2(left_x_staggered + (KEY_SIZE.x + KEY_GAP) * 3.5, row1_y), false, 0, false)
	
	# Row 2: Shift Z X C space
	var row2_y = row1_y + KEY_SIZE.y + KEY_GAP
	_add_key("⇧", "boost", Vector2(left_x_staggered, row2_y))
	_add_key("Z", "height_brake", Vector2(left_x_staggered + KEY_SIZE.x + KEY_GAP, row2_y), false, 0, false)  # Non-lockable circle
	_add_key("X", "handbrake", Vector2(left_x_staggered + (KEY_SIZE.x + KEY_GAP) * 2, row2_y), false, 0, false)  # Non-lockable circle
	_add_key("C", "crouch", Vector2(left_x_staggered + (KEY_SIZE.x + KEY_GAP) * 3, row2_y))

	
	# Center cluster: Space and C
	var center_x = left_x_staggered + (KEY_SIZE.x + KEY_GAP) * 4
	var center_y = row2_y
	
	# Space bar (wider)
	var space_key = _add_key("␣", "jump", Vector2(center_x, center_y))
	space_key.custom_minimum_size = Vector2(80, KEY_SIZE.y)
	space_key.size = Vector2(80, KEY_SIZE.y)
	
	# C below space
	#_add_key("C", "crouch", Vector2(center_x + 15, center_y + KEY_SIZE.y + KEY_GAP))
	
	# Right cluster: Arrow keys
	var right_x = center_x + CLUSTER_GAP
	var right_y = left_y
	
	# Row 0: Up arrow (centered)
	_add_key("↑", "pitch_down", Vector2(right_x + KEY_SIZE.x + KEY_GAP, right_y))
	
	# Row 1: Left Down Right
	var arrow_row1_y = right_y + KEY_SIZE.y + KEY_GAP
	_add_key("←", "shin_left", Vector2(right_x, arrow_row1_y))
	_add_key("↓", "pitch_up", Vector2(right_x + KEY_SIZE.x + KEY_GAP, arrow_row1_y))
	_add_key("→", "shin_right", Vector2(right_x + (KEY_SIZE.x + KEY_GAP) * 2, arrow_row1_y))


func _add_key(lbl: String, action: String, pos: Vector2, raw_key: bool = false, key_code: int = 0, lockable: bool = true) -> ControlDisplayKey:
	var key = ControlDisplayKey.new()
	key.position = pos
	key.size = KEY_SIZE
	key.set_key(lbl, action, raw_key, key_code, lockable)
	add_child(key)

	# Store by action name for lookup
	var lookup_key = str(key_code) if raw_key else action
	key_buttons[lookup_key] = key

	return key


func _process(_delta: float):
	if not car_ref:
		return

	# Frame throttling - only update every N frames
	_frame_counter += 1
	if _frame_counter < UPDATE_EVERY_N_FRAMES:
		return
	_frame_counter = 0

	var lock_mode_active = Input.is_action_pressed("toggle_control_lock")

	for lookup_key in key_buttons:
		var key_btn: ControlDisplayKey = key_buttons[lookup_key]
		var physical_pressed: bool
		var is_locked: bool

		if key_btn.is_raw_key:
			var kc = key_btn.raw_key_code
			physical_pressed = Input.is_key_pressed(kc)
			is_locked = car_ref.locked_keys.has(kc) if "locked_keys" in car_ref else false
		else:
			var action = key_btn.action_name
			physical_pressed = Input.is_action_pressed(action)
			is_locked = car_ref.locked_actions.has(action) if "locked_actions" in car_ref else false

		key_btn.update_state(physical_pressed, is_locked, lock_mode_active)
