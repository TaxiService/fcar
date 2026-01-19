class_name ShiftSelector
extends CanvasLayer

# Shift selection popup
# R (confirm) = select current option
# T (cancel) = cycle to next option

enum ShiftType { CANCEL, SINGLE, HALF, FULL }

const SHIFT_OPTIONS = [
	{ "type": ShiftType.CANCEL, "label": "Cancel", "fares": 0 },
	{ "type": ShiftType.SINGLE, "label": "Single Fare", "fares": 1 },
	{ "type": ShiftType.HALF, "label": "Half Shift (5)", "fares": 5 },
	{ "type": ShiftType.FULL, "label": "Full Shift (10)", "fares": 10 },
]

var current_selection: int = 0  # Default to Cancel
var is_open: bool = false

# UI elements
var panel: Panel
var title_label: Label
var option_labels: Array[Label] = []

# Colors
const COLOR_NORMAL = Color(0.6, 0.6, 0.6)
const COLOR_SELECTED = Color(1.0, 0.9, 0.3)
const COLOR_TITLE = Color(0.8, 0.8, 0.8)

# Signals
signal shift_selected(fare_count: int)
signal cancelled


func _ready():
	layer = 110  # Above other UI
	_build_ui()
	hide_selector()


func _build_ui():
	# Semi-transparent background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks
	add_child(bg)

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

	# Option labels
	for i in range(SHIFT_OPTIONS.size()):
		var label = Label.new()
		label.text = SHIFT_OPTIONS[i].label
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", COLOR_NORMAL)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_labels.append(label)
		panel.add_child(label)

	# Instructions
	var hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.text = "T: cycle   R: select"
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint_label)

	# Position elements (will be updated in _update_layout)
	call_deferred("_update_layout")


func _update_layout():
	if not is_instance_valid(panel):
		return

	var viewport_size = get_viewport().get_visible_rect().size

	# Center the panel
	panel.size = Vector2(240, 180)
	panel.position = (viewport_size - panel.size) / 2

	# Layout elements within panel
	var y_offset = 15
	title_label.position = Vector2(0, y_offset)
	title_label.size = Vector2(panel.size.x, 25)
	y_offset += 35

	for i in range(option_labels.size()):
		option_labels[i].position = Vector2(0, y_offset)
		option_labels[i].size = Vector2(panel.size.x, 22)
		y_offset += 26

	# Hint at bottom
	var hint = panel.get_node_or_null("Hint")
	if hint:
		hint.position = Vector2(0, panel.size.y - 25)
		hint.size = Vector2(panel.size.x, 20)


func show_selector():
	current_selection = 0  # Reset to Cancel
	is_open = true
	visible = true
	_update_selection_display()
	_update_layout()


func hide_selector():
	is_open = false
	visible = false


func cycle_selection():
	# Move to next option (wraps around)
	current_selection = (current_selection + 1) % SHIFT_OPTIONS.size()
	_update_selection_display()


func confirm_selection():
	var selected = SHIFT_OPTIONS[current_selection]

	if selected.type == ShiftType.CANCEL:
		cancelled.emit()
	else:
		shift_selected.emit(selected.fares)

	hide_selector()


func _update_selection_display():
	for i in range(option_labels.size()):
		if i == current_selection:
			option_labels[i].add_theme_color_override("font_color", COLOR_SELECTED)
			option_labels[i].text = "> " + SHIFT_OPTIONS[i].label + " <"
		else:
			option_labels[i].add_theme_color_override("font_color", COLOR_NORMAL)
			option_labels[i].text = SHIFT_OPTIONS[i].label
