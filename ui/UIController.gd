class_name UIController
extends Node

# Main controller for the windowed UI system
# Add this as a child of your main scene or FCar

@export var car_node_path: NodePath  # Path to FCar node
@export var auto_open_debug: bool = true  # Open debug window on start

var window_manager: WindowManager
var car_ref: Node


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

	# Open default windows
	if auto_open_debug:
		open_debug_window()


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


# Public API for opening specific windows

func open_debug_window() -> UIWindow:
	if not window_manager:
		return null

	# Check if already open
	var existing = window_manager.get_window_by_title("Debug")
	if existing:
		window_manager.bring_window_to_front(existing)
		return existing

	var content = DebugWindow.new()
	if car_ref:
		content.set_car(car_ref)

	var window = window_manager.create_window_with_content(
		"Debug",
		content,
		Vector2(20, 20),
		Vector2(220, 200)
	)
	window.min_size = Vector2(180, 150)
	return window


func open_custom_window(title: String, content: Control, pos: Vector2 = Vector2(100, 100), win_size: Vector2 = Vector2(300, 200)) -> UIWindow:
	if not window_manager:
		return null
	return window_manager.create_window_with_content(title, content, pos, win_size)


func get_window_manager() -> WindowManager:
	return window_manager
