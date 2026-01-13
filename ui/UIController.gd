class_name UIController
extends Node

# Main controller for the windowed UI system
# Add this as a child of your main scene or FCar

@export var car_node_path: NodePath  # Path to FCar node
@export var auto_open_debug: bool = true  # Open debug window on start
@export var auto_open_score: bool = true  # Open score window on start

var window_manager: WindowManager
var car_ref: Node
var shift_manager: Node


func _ready():
	# Find the car
	if car_node_path:
		car_ref = get_node_or_null(car_node_path)
	if not car_ref:
		# Try to find it automatically
		car_ref = _find_car()

	# Create the window manager
	window_manager = WindowManager.new()
	window_manager.name = "WindowManager"
	get_tree().root.add_child.call_deferred(window_manager)

	# Wait a frame for window manager to initialize
	await get_tree().process_frame

	# Find shift manager
	shift_manager = _find_node_by_class(get_tree().root, "ShiftManager")

	# Open default windows
	if auto_open_debug:
		open_debug_window()
	if auto_open_score:
		open_score_window()


func _find_car() -> Node:
	# Try common locations
	var root = get_tree().root
	for child in root.get_children():
		var found = _find_node_with_property(child, "is_ready_for_fares")
		if found:
			return found
	return null


func _find_node_with_property(node: Node, prop: String) -> Node:
	if prop in node:
		return node
	for child in node.get_children():
		var found = _find_node_with_property(child, prop)
		if found:
			return found
	return null


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == class_name_str:
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


# Public API for opening specific windows

func open_debug_window() -> UIWindow:
	if not window_manager:
		return null

	# Create content first to get its preferred title
	var content = DebugWindow.new()
	if car_ref:
		content.set_car(car_ref)

	# Check if already open (using content's title)
	var existing = window_manager.get_window_by_title(content.window_title)
	if existing:
		window_manager.bring_window_to_front(existing)
		content.queue_free()  # Don't need this instance
		return existing

	var window = window_manager.create_window_with_content(
		content.window_title,
		content,
		Vector2(20, 20),
		Vector2(220, 260)
	)
	window.min_size = Vector2(180, 240)
	return window


func open_score_window() -> UIWindow:
	if not window_manager:
		return null

	# Create content first to get its preferred title
	var content = ScoreWindow.new()
	if shift_manager:
		content.set_shift_manager(shift_manager)

	# Check if already open (using content's title)
	var existing = window_manager.get_window_by_title(content.window_title)
	if existing:
		window_manager.bring_window_to_front(existing)
		content.queue_free()
		return existing

	var window = window_manager.create_window_with_content(
		content.window_title,
		content,
		Vector2(20, 300),  # Below the debug window
		Vector2(180, 140)
	)
	window.min_size = Vector2(150, 120)
	return window


func open_custom_window(title: String, content: Control, pos: Vector2 = Vector2(100, 100), win_size: Vector2 = Vector2(300, 200)) -> UIWindow:
	if not window_manager:
		return null
	return window_manager.create_window_with_content(title, content, pos, win_size)


func get_window_manager() -> WindowManager:
	return window_manager


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				toggle_debug_window()
				get_viewport().set_input_as_handled()
			KEY_F2:
				toggle_score_window()
				get_viewport().set_input_as_handled()


func toggle_debug_window():
	if not window_manager:
		return

	# Check if window exists by looking for the title
	var existing = window_manager.get_window_by_title("Car status")
	if existing:
		existing.closed.emit()  # Notify WindowManager to remove from tracking
		existing.queue_free()
	else:
		open_debug_window()


func toggle_score_window():
	if not window_manager:
		return

	var existing = window_manager.get_window_by_title("Shift")
	if existing:
		existing.closed.emit()  # Notify WindowManager to remove from tracking
		existing.queue_free()
	else:
		open_score_window()
