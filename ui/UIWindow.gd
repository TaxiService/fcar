class_name UIWindow
extends Panel

# Window configuration
@export var window_title: String = "Window":
	set(value):
		window_title = value
		if title_label:
			title_label.text = value

@export var resizable: bool = true
@export var closable: bool = true
@export var draggable_anywhere: bool = false  # If true, can drag from anywhere, not just title bar
@export var lock_aspect_ratio: bool = false  # If true, maintain aspect ratio when resizing
@export var min_size: Vector2 = Vector2(150, 100)

# Signals
signal closed
signal focused
signal moved(new_position: Vector2)
signal window_resized(new_size: Vector2)

# Internal state
var is_dragging: bool = false
var is_resizing: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var resize_edge: int = 0  # Bitfield: 1=left, 2=right, 4=top, 8=bottom
var aspect_ratio: float = 1.5  # Width / Height, set from initial size

const RESIZE_MARGIN: int = 8
const TITLE_BAR_HEIGHT: int = 28

# Child nodes (created in _ready)
var title_bar: Panel
var title_label: Label
var close_button: Button
var content_container: Control


func _ready():
	# Calculate initial aspect ratio
	if size.y > 0:
		aspect_ratio = size.x / size.y

	_build_window_structure()
	_apply_default_style()

	# Ensure we can receive input
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Force layout update now and after a frame (ensures correct sizing)
	_update_layout()
	call_deferred("_update_layout")


func _build_window_structure():
	# Title bar (manually positioned, no anchors to avoid conflicts)
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.position = Vector2.ZERO
	title_bar.custom_minimum_size = Vector2(0, TITLE_BAR_HEIGHT)
	title_bar.size = Vector2(size.x, TITLE_BAR_HEIGHT)
	# Pass mouse events through to the window for drag handling
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(title_bar)

	# Title label
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = window_title
	title_label.position = Vector2(8, 4)
	title_label.size = Vector2(size.x - 40, TITLE_BAR_HEIGHT - 8)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_label)

	# Close button
	if closable:
		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.text = "X"
		close_button.size = Vector2(24, 24)
		close_button.position = Vector2(size.x - 28, 2)
		close_button.pressed.connect(_on_close_pressed)
		title_bar.add_child(close_button)

	# Content container (where window content goes)
	content_container = Control.new()
	content_container.name = "Content"
	content_container.position = Vector2(4, TITLE_BAR_HEIGHT + 4)
	content_container.size = Vector2(size.x - 8, size.y - TITLE_BAR_HEIGHT - 8)
	content_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content_container)


func _apply_default_style():
	# Window background
	var window_style = StyleBoxFlat.new()
	window_style.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	window_style.border_color = Color(0.4, 0.4, 0.45, 1.0)
	window_style.set_border_width_all(1)
	window_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", window_style)

	# Title bar style
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	title_style.set_corner_radius_all(3)
	title_bar.add_theme_stylebox_override("panel", title_style)

	# Title text color
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))

	# Close button style
	if close_button:
		close_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.3, 1.0))


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Bring to front when clicked
				focused.emit()

				# Check for resize edges first
				if resizable:
					resize_edge = _get_resize_edge(mb.position)
					if resize_edge != 0:
						is_resizing = true
						accept_event()
						return

				# Check for drag (title bar or anywhere if enabled)
				if _can_drag_from(mb.position):
					is_dragging = true
					drag_offset = mb.position
					accept_event()
			else:
				is_dragging = false
				is_resizing = false

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion

		if is_dragging:
			position += mm.relative
			moved.emit(position)
			accept_event()

		elif is_resizing:
			_handle_resize(mm.relative)
			accept_event()

		else:
			# Update cursor based on hover position
			_update_cursor(mm.position)


func _can_drag_from(pos: Vector2) -> bool:
	# Can always drag from title bar (but not close button area)
	if pos.y < TITLE_BAR_HEIGHT and pos.x < size.x - 30:
		return true

	# If draggable_anywhere is enabled, can drag from content area too
	# (but not from resize edges)
	if draggable_anywhere:
		var edge = _get_resize_edge(pos)
		return edge == 0

	return false


func _get_resize_edge(pos: Vector2) -> int:
	if not resizable:
		return 0

	var edge = 0
	if pos.x < RESIZE_MARGIN:
		edge |= 1  # Left
	elif pos.x > size.x - RESIZE_MARGIN:
		edge |= 2  # Right
	if pos.y < RESIZE_MARGIN:
		edge |= 4  # Top
	elif pos.y > size.y - RESIZE_MARGIN:
		edge |= 8  # Bottom

	return edge


func _handle_resize(delta: Vector2):
	var new_pos = position
	var new_size = size

	# Left edge
	if resize_edge & 1:
		new_pos.x += delta.x
		new_size.x -= delta.x
	# Right edge
	if resize_edge & 2:
		new_size.x += delta.x
	# Top edge
	if resize_edge & 4:
		new_pos.y += delta.y
		new_size.y -= delta.y
	# Bottom edge
	if resize_edge & 8:
		new_size.y += delta.y

	# Enforce minimum size
	if new_size.x < min_size.x:
		if resize_edge & 1:
			new_pos.x = position.x + size.x - min_size.x
		new_size.x = min_size.x
	if new_size.y < min_size.y:
		if resize_edge & 4:
			new_pos.y = position.y + size.y - min_size.y
		new_size.y = min_size.y

	# Lock aspect ratio if enabled
	if lock_aspect_ratio and aspect_ratio > 0:
		# Determine which dimension to adjust based on resize edge
		var resizing_horizontal = (resize_edge & 1) or (resize_edge & 2)
		var resizing_vertical = (resize_edge & 4) or (resize_edge & 8)

		if resizing_horizontal and not resizing_vertical:
			# Adjust height to match width
			var target_height = new_size.x / aspect_ratio
			if resize_edge & 8:  # Bottom edge - grow down
				new_size.y = target_height
			else:  # Default - keep top anchored
				new_size.y = target_height
		elif resizing_vertical and not resizing_horizontal:
			# Adjust width to match height
			var target_width = new_size.y * aspect_ratio
			if resize_edge & 1:  # Left edge - grow left
				new_pos.x = position.x + size.x - target_width
			new_size.x = target_width
		else:
			# Corner resize - use width as primary
			new_size.y = new_size.x / aspect_ratio

		# Re-enforce minimum size after aspect ratio adjustment
		if new_size.x < min_size.x:
			new_size.x = min_size.x
			new_size.y = min_size.x / aspect_ratio
		if new_size.y < min_size.y:
			new_size.y = min_size.y
			new_size.x = min_size.y * aspect_ratio

	position = new_pos
	size = new_size
	_update_layout()
	window_resized.emit(size)


func _update_cursor(pos: Vector2):
	if not resizable:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return

	var edge = _get_resize_edge(pos)

	match edge:
		1, 2:  # Left or Right
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		4, 8:  # Top or Bottom
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		5, 10:  # Top-left or Bottom-right
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		6, 9:  # Top-right or Bottom-left
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _update_layout():
	# Update title bar width
	if title_bar:
		title_bar.size.x = size.x

	# Update close button position
	if close_button:
		close_button.position.x = size.x - 28

	# Update title label width
	if title_label:
		title_label.size.x = size.x - 40

	# Update content container
	if content_container:
		content_container.size = Vector2(size.x - 8, size.y - TITLE_BAR_HEIGHT - 8)


func _on_close_pressed():
	closed.emit()
	queue_free()


# Public API

func set_content(control: Control):
	# Add a control as the window's content
	if content_container:
		# Clear existing content
		for child in content_container.get_children():
			child.queue_free()

		content_container.add_child(control)
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_content_container() -> Control:
	return content_container


func bring_to_front():
	var parent = get_parent()
	if parent:
		parent.move_child(self, parent.get_child_count() - 1)


func set_aspect_ratio(ratio: float):
	# Manually set aspect ratio (width / height)
	aspect_ratio = ratio


func lock_current_aspect_ratio():
	# Lock to current size's aspect ratio
	if size.y > 0:
		aspect_ratio = size.x / size.y
	lock_aspect_ratio = true
