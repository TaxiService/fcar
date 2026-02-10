class_name ShiftSelector
extends CanvasLayer

# Shift selection popup
# R (confirm) = select current option
# T (cancel) = cycle to next option

enum ShiftType { CANCEL, SINGLE, HALF, FULL, HOSPITAL, RESUME }

const FARE_OPTIONS = [
	{ "type": ShiftType.CANCEL, "label": "Cancel", "fares": 0 },
	{ "type": ShiftType.SINGLE, "label": "Single Fare", "fares": 1 },
	{ "type": ShiftType.HALF, "label": "Half Shift (5)", "fares": 5 },
	{ "type": ShiftType.FULL, "label": "Full Shift (10)", "fares": 10 },
]

var _active_options: Array = []  # Built dynamically in show_selector()
var current_selection: int = 0
var is_open: bool = false

# External references
var people_manager: Node = null  # Set by FCar to check for parts

# UI elements
var panel: Panel
var title_label: Label
var option_container: VBoxContainer
var option_labels: Array[Label] = []
var hint_label: Label
var _bg: ColorRect

# Colors
const COLOR_NORMAL = Color(0.6, 0.6, 0.6)
const COLOR_SELECTED = Color(1.0, 0.9, 0.3)
const COLOR_HOSPITAL = Color(1.0, 0.4, 0.4)
const COLOR_RESUME = Color(0.4, 1.0, 0.6)
const COLOR_TITLE = Color(0.8, 0.8, 0.8)

# Signals
signal shift_selected(fare_count: int)
signal hospital_run_selected
signal shift_resumed
signal cancelled


func _ready():
	layer = 110  # Above other UI
	_build_ui()
	hide_selector()


func _build_ui():
	# Semi-transparent background
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.color = Color(0, 0, 0, 0.5)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Center panel
	panel = Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(240, 180)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# Title
	title_label = Label.new()
	title_label.text = "Start Shift"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", COLOR_TITLE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)

	# Container for dynamic option labels
	option_container = VBoxContainer.new()
	option_container.name = "Options"
	panel.add_child(option_container)

	# Instructions
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.text = "R: confirm   T: cycle"
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint_label)


func _build_option_labels():
	# Clear existing labels
	for label in option_labels:
		if is_instance_valid(label):
			label.queue_free()
	option_labels.clear()

	# Create labels for active options
	for i in range(_active_options.size()):
		var label = Label.new()
		label.text = _active_options[i].label
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", COLOR_NORMAL)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_labels.append(label)
		option_container.add_child(label)


func _update_layout():
	if not is_instance_valid(panel):
		return

	var viewport_size = get_viewport().get_visible_rect().size

	# Calculate panel height based on option count
	var option_count = _active_options.size()
	var panel_height = 55 + (option_count * 26) + 30  # title + options + hint
	panel.size = Vector2(240, panel_height)
	panel.position = (viewport_size - panel.size) / 2

	# Layout elements within panel
	var y_offset = 15
	title_label.position = Vector2(0, y_offset)
	title_label.size = Vector2(panel.size.x, 25)
	y_offset += 35

	option_container.position = Vector2(0, y_offset)
	option_container.size = Vector2(panel.size.x, option_count * 26)

	# Hint at bottom
	hint_label.position = Vector2(0, panel_height - 25)
	hint_label.size = Vector2(panel.size.x, 20)


func show_selector(mid_shift: bool = false):
	# Build active options dynamically
	_active_options = []

	# Add Hospital Run if parts exist
	if people_manager and people_manager.has_undelivered_parts():
		var part_count = people_manager.all_parts.size()
		_active_options.append({
			"type": ShiftType.HOSPITAL,
			"label": "Hospital Run (%d parts)" % part_count,
			"fares": 0
		})

	if mid_shift:
		# Mid-shift context: Resume + Cancel only (no new shift types)
		title_label.text = "Shift Paused"
		_active_options.append({
			"type": ShiftType.RESUME,
			"label": "Resume Shift",
			"fares": 0
		})
		_active_options.append({ "type": ShiftType.CANCEL, "label": "Cancel", "fares": 0 })
	else:
		# Normal context: fare shift types
		title_label.text = "Start Shift"
		for opt in FARE_OPTIONS:
			_active_options.append(opt)

	# Rebuild UI labels
	_build_option_labels()

	current_selection = 0
	is_open = true
	visible = true
	_update_selection_display()
	_update_layout()


func hide_selector():
	is_open = false
	visible = false


func cycle_selection():
	# Move to next option (wraps around)
	current_selection = (current_selection + 1) % _active_options.size()
	_update_selection_display()


func confirm_selection():
	var selected = _active_options[current_selection]

	if selected.type == ShiftType.CANCEL:
		cancelled.emit()
	elif selected.type == ShiftType.HOSPITAL:
		hospital_run_selected.emit()
	elif selected.type == ShiftType.RESUME:
		shift_resumed.emit()
	else:
		shift_selected.emit(selected.fares)

	hide_selector()


func _update_selection_display():
	for i in range(option_labels.size()):
		if i >= _active_options.size():
			break
		var opt_type = _active_options[i].type
		if i == current_selection:
			var color = COLOR_SELECTED
			if opt_type == ShiftType.HOSPITAL:
				color = COLOR_HOSPITAL
			elif opt_type == ShiftType.RESUME:
				color = COLOR_RESUME
			option_labels[i].add_theme_color_override("font_color", color)
			option_labels[i].text = "> " + _active_options[i].label + " <"
		else:
			option_labels[i].add_theme_color_override("font_color", COLOR_NORMAL)
			option_labels[i].text = _active_options[i].label
