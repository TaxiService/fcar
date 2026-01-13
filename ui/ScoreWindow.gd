class_name ScoreWindow
extends Control

# Score display window for shift progress

var window_title: String = "Shift status"

var shift_manager: Node = null
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1

# UI Elements
var score_label: Label
var fare_count_label: Label
var last_fare_label: Label
var status_label: Label

# Last fare flash animation
var last_fare_timer: float = 0.0
const LAST_FARE_DISPLAY_TIME: float = 2.0


func _ready():
	_build_ui()
	call_deferred("_find_shift_manager")


func _find_shift_manager():
	# Try to find ShiftManager in the scene
	var root = get_tree().root
	shift_manager = _find_node_by_class(root, "ShiftManager")
	if shift_manager:
		# Connect to signals
		if not shift_manager.fare_completed.is_connected(_on_fare_completed):
			shift_manager.fare_completed.connect(_on_fare_completed)
		if not shift_manager.shift_ended.is_connected(_on_shift_ended):
			shift_manager.shift_ended.connect(_on_shift_ended)
		if not shift_manager.shift_started.is_connected(_on_shift_started):
			shift_manager.shift_started.connect(_on_shift_started)
		print("ScoreWindow: Connected to ShiftManager")
	else:
		push_warning("ScoreWindow: ShiftManager not found")


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == class_name_str:
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


func _build_ui():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Score display (large)
	score_label = Label.new()
	score_label.text = "0 ₧"
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score_label)

	# Fare count
	fare_count_label = Label.new()
	fare_count_label.text = "Fare 0/10"
	fare_count_label.add_theme_font_size_override("font_size", 14)
	fare_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	fare_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(fare_count_label)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Last fare earned (flashes then fades)
	last_fare_label = Label.new()
	last_fare_label.text = ""
	last_fare_label.add_theme_font_size_override("font_size", 16)
	last_fare_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	last_fare_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_fare_label.modulate.a = 0.0  # Start invisible
	vbox.add_child(last_fare_label)

	# Status label (for shift complete message)
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(status_label)


func _process(delta: float):
	# Update last fare flash animation
	if last_fare_timer > 0:
		last_fare_timer -= delta
		# Fade out over time
		var alpha = last_fare_timer / LAST_FARE_DISPLAY_TIME
		last_fare_label.modulate.a = alpha
		if last_fare_timer <= 0:
			last_fare_label.text = ""

	# Throttled updates
	update_timer += delta
	if update_timer < UPDATE_INTERVAL:
		return
	update_timer = 0.0

	_update_display()


func _update_display():
	if not shift_manager:
		score_label.text = "--- ₧"
		fare_count_label.text = "No shift"
		return

	# Update score
	var score = shift_manager.get_score()
	score_label.text = "%d ₧" % score

	# Update fare count
	var fare_count = shift_manager.get_fare_count()
	var fares_per_shift = shift_manager.fares_per_shift
	fare_count_label.text = "%d / %d fares" % [fare_count, fares_per_shift]

	# Update status based on shift state
	if not shift_manager.is_shift_active() and fare_count == 0:
		status_label.text = "Press R to start new shift"
		status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))


func _on_fare_completed(score: int, breakdown: Dictionary):
	# Show the fare earned with a flash
	if breakdown.get("ejected", false):
		if score > 0:
			last_fare_label.text = "+%d₧ (partial)" % score
		else:
			last_fare_label.text = "Ejected - no pay"
			last_fare_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		last_fare_label.text = "+%d₧" % score
		last_fare_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))

	last_fare_label.modulate.a = 1.0
	last_fare_timer = LAST_FARE_DISPLAY_TIME


func _on_shift_started():
	status_label.text = ""


func _on_shift_ended(total_score: int):
	status_label.text = "Shift Complete!\nPress R to start new shift"
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))

	# Show final score flash
	last_fare_label.text = "SHIFT TOTAL: %d₧" % total_score
	last_fare_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	last_fare_label.modulate.a = 1.0
	last_fare_timer = LAST_FARE_DISPLAY_TIME * 2  # Show longer for shift end


func set_shift_manager(manager: Node):
	shift_manager = manager
	if shift_manager:
		if not shift_manager.fare_completed.is_connected(_on_fare_completed):
			shift_manager.fare_completed.connect(_on_fare_completed)
		if not shift_manager.shift_ended.is_connected(_on_shift_ended):
			shift_manager.shift_ended.connect(_on_shift_ended)
		if not shift_manager.shift_started.is_connected(_on_shift_started):
			shift_manager.shift_started.connect(_on_shift_started)
