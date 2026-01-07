class_name WindowManager
extends CanvasLayer

# The UI layer sits above the game world
# Windows can be created, managed, toggled

@export var ui_visible: bool = true:
	set(value):
		ui_visible = value
		_container.visible = value

# Container for all windows
var _container: Control
var _windows: Array[UIWindow] = []

# Signals
signal window_opened(window: UIWindow)
signal window_closed(window: UIWindow)
signal ui_visibility_changed(visible: bool)


func _ready():
	# High layer number to render above game
	layer = 100

	# Create the container that holds all windows
	_container = Control.new()
	_container.name = "WindowContainer"
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass through clicks to windows
	add_child(_container)


func _input(event: InputEvent):
	# Toggle UI visibility (Tab key by default, configurable in Input Map)
	if Input.is_action_just_pressed("toggle_ui"):
		toggle_ui()
		get_viewport().set_input_as_handled()


func toggle_ui():
	ui_visible = !ui_visible
	ui_visibility_changed.emit(ui_visible)
	print("UI Layer: ", "visible" if ui_visible else "hidden")


func show_ui():
	ui_visible = true
	ui_visibility_changed.emit(true)


func hide_ui():
	ui_visible = false
	ui_visibility_changed.emit(false)


# Window creation and management

func create_window(title: String = "Window", pos: Vector2 = Vector2(100, 100), win_size: Vector2 = Vector2(300, 200)) -> UIWindow:
	var window = UIWindow.new()
	window.window_title = title
	window.position = pos
	window.size = win_size

	# Connect signals
	window.closed.connect(_on_window_closed.bind(window))
	window.focused.connect(_on_window_focused.bind(window))

	_container.add_child(window)
	_windows.append(window)

	window_opened.emit(window)
	return window


func create_window_with_content(title: String, content: Control, pos: Vector2 = Vector2(100, 100), win_size: Vector2 = Vector2(300, 200)) -> UIWindow:
	var window = create_window(title, pos, win_size)
	window.set_content(content)
	return window


func close_window(window: UIWindow):
	if window in _windows:
		window.closed.emit()
		# The window will queue_free itself


func close_all_windows():
	for window in _windows.duplicate():  # Duplicate to avoid modifying while iterating
		close_window(window)


func get_windows() -> Array[UIWindow]:
	# Clean up invalid references
	_windows = _windows.filter(func(w): return is_instance_valid(w))
	return _windows


func get_window_by_title(title: String) -> UIWindow:
	for window in _windows:
		if is_instance_valid(window) and window.window_title == title:
			return window
	return null


func bring_window_to_front(window: UIWindow):
	if window in _windows and is_instance_valid(window):
		window.bring_to_front()


func _on_window_closed(window: UIWindow):
	_windows.erase(window)
	window_closed.emit(window)


func _on_window_focused(window: UIWindow):
	bring_window_to_front(window)


# Utility: cascade windows from a starting position
func cascade_windows(start_pos: Vector2 = Vector2(50, 50), offset: Vector2 = Vector2(30, 30)):
	var pos = start_pos
	for window in _windows:
		if is_instance_valid(window):
			window.position = pos
			pos += offset


# Utility: tile windows in a grid
func tile_windows(columns: int = 2, padding: Vector2 = Vector2(10, 10)):
	var viewport_size = get_viewport().get_visible_rect().size
	var window_count = _windows.size()
	if window_count == 0:
		return

	var rows = ceili(float(window_count) / columns)
	var win_size = Vector2(
		(viewport_size.x - padding.x * (columns + 1)) / columns,
		(viewport_size.y - padding.y * (rows + 1)) / rows
	)

	var i = 0
	for window in _windows:
		if is_instance_valid(window):
			var col = i % columns
			var row = i / columns
			window.position = Vector2(
				padding.x + col * (win_size.x + padding.x),
				padding.y + row * (win_size.y + padding.y)
			)
			window.size = win_size
			i += 1
