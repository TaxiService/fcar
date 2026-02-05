class_name ControlDisplayKey
extends Control

# Visual key button for control display window
# Shows pressed/locked state for a single input

@export var key_label: String = "?"
@export var action_name: String = ""
@export var is_raw_key: bool = false
@export var raw_key_code: int = 0

# Colors
const COLOR_BG_IDLE = Color(0.08, 0.18, 0.15)
const COLOR_BG_LOCKED = Color(0.4, 0.2, 0.0)
const COLOR_BG_PRESSED = Color(0.3, 0.9, 0.5)
const COLOR_TEXT_IDLE = Color(0.5, 0.5, 0.55)
const COLOR_TEXT_LOCKED = Color(1, 0.6, 0.2)
const COLOR_TEXT_PRESSED = Color(0.2, 0.0, 0.2)
const COLOR_BORDER_LOCKED = Color(1.0, 0.6, 0.2)
const COLOR_BORDER_LOCK_MODE = Color(0.4, 0.5, 0.4)

var panel: Panel
var label: Label
var style_box: StyleBoxFlat

var _current_locked: bool = false


func _init():
	custom_minimum_size = Vector2(40, 20)


func _ready():
	_build_ui()


func _build_ui():
	# Panel background
	panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	
	# Create stylebox
	style_box = StyleBoxFlat.new()
	style_box.bg_color = COLOR_BG_IDLE
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	style_box.border_width_top = 0
	style_box.border_width_bottom = 0
	panel.add_theme_stylebox_override("panel", style_box)
	
	# Label
	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_TEXT_IDLE)
	label.text = " %s " % key_label
	add_child(label)


func set_key(lbl: String, action: String = "", raw_key: bool = false, key_code: int = 0):
	key_label = lbl
	action_name = action
	is_raw_key = raw_key
	raw_key_code = key_code
	if label:
		label.text = " %s " % key_label


func update_state(physical_pressed: bool, is_locked: bool, lock_mode_active: bool):
	if not style_box or not label:
		return
	
	_current_locked = is_locked
	var is_active = physical_pressed or is_locked
	
	# Background color
	style_box.bg_color = COLOR_BG_PRESSED if physical_pressed else COLOR_BG_IDLE
	
	# Text color and label
	label.add_theme_color_override("font_color", COLOR_TEXT_PRESSED if is_active else COLOR_TEXT_IDLE)
	
	# Label text: ">X<" when locked, " X " otherwise
	if is_locked and !physical_pressed:
		label.text = ">%s<" % key_label
	else:
		label.text = " %s " % key_label
	
	# Border
	var border_width = 0
	var border_color = Color.TRANSPARENT
	
	if is_locked:
		border_width = 3
		border_color = COLOR_BORDER_LOCKED
		if !physical_pressed: 
			style_box.bg_color = COLOR_BG_LOCKED
			label.add_theme_color_override("font_color", COLOR_TEXT_LOCKED)
	elif lock_mode_active and action_name != "toggle_control_lock":
		border_width = 2
		border_color = COLOR_BORDER_LOCK_MODE
	
	style_box.border_width_left = border_width
	style_box.border_width_right = border_width
	style_box.border_width_top = border_width
	style_box.border_width_bottom = border_width
	style_box.border_color = border_color
