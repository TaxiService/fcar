# LoadingScreen.gd - Simple loading screen for city generation
# Add this as a child of your main scene, or instanced when needed
#
# Usage:
#   1. Add this scene to your main scene
#   2. Connect CityGenerator's signals to this
#   3. It auto-hides when generation completes
extends CanvasLayer

@export var city_generator_path: NodePath
@export var auto_hide_delay: float = 0.5  # Seconds to wait before hiding after complete
@export var show_phase: bool = true
@export var show_percentage: bool = true

var _city_generator: Node = null

@onready var panel: PanelContainer = $Panel
@onready var progress_bar: ProgressBar = $Panel/VBox/ProgressBar
@onready var phase_label: Label = $Panel/VBox/PhaseLabel
@onready var message_label: Label = $Panel/VBox/MessageLabel


func _ready():
	# Build UI if not already set up
	if not has_node("Panel"):
		_build_ui()
	
	# Find and connect to CityGenerator
	if city_generator_path:
		_city_generator = get_node_or_null(city_generator_path)
	
	if not _city_generator:
		# Try to find it automatically
		_city_generator = _find_city_generator(get_tree().root)
	
	if _city_generator:
		_connect_signals()
		show_loading()
	else:
		push_warning("LoadingScreen: Could not find CityGenerator")
		hide_loading()


func _find_city_generator(node: Node) -> Node:
	if node is CityGenerator:
		return node
	for child in node.get_children():
		var result = _find_city_generator(child)
		if result:
			return result
	return null


func _connect_signals():
	if _city_generator.has_signal("city_generation_started"):
		_city_generator.city_generation_started.connect(_on_generation_started)
	if _city_generator.has_signal("city_generation_progress"):
		_city_generator.city_generation_progress.connect(_on_generation_progress)
	if _city_generator.has_signal("city_generation_complete"):
		_city_generator.city_generation_complete.connect(_on_generation_complete)


func _build_ui():
	# Create UI programmatically if not designed in editor
	
	# Panel container
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.anchors_preset = Control.PRESET_CENTER
	panel.custom_minimum_size = Vector2(400, 120)
	add_child(panel)
	
	# Center it
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Phase label
	phase_label = Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.text = "Initializing..."
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(phase_label)
	
	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(350, 25)
	progress_bar.value = 0
	progress_bar.show_percentage = show_percentage
	vbox.add_child(progress_bar)
	
	# Message label
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.text = ""
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 12)
	message_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(message_label)
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.3, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)


func show_loading():
	visible = true
	progress_bar.value = 0
	phase_label.text = "Loading..."
	message_label.text = ""


func hide_loading():
	visible = false


func _on_generation_started():
	show_loading()
	phase_label.text = "Generating City"
	message_label.text = "Starting..."


func _on_generation_progress(phase: String, progress: float, message: String):
	progress_bar.value = progress * 100
	
	if show_phase:
		match phase:
			"setup":
				phase_label.text = "Preparing"
			"grid":
				phase_label.text = "Hex Grid"
			"spires":
				phase_label.text = "Spires"
			"crosslinks":
				phase_label.text = "Crosslinks"
			"connectors":
				phase_label.text = "Connectors"
			"buildings":
				phase_label.text = "Buildings"
			"complete":
				phase_label.text = "Complete!"
			_:
				phase_label.text = phase.capitalize()
	
	message_label.text = message


func _on_generation_complete():
	progress_bar.value = 100
	phase_label.text = "Complete!"
	message_label.text = "City generated successfully"
	
	# Hide after delay
	if auto_hide_delay > 0:
		await get_tree().create_timer(auto_hide_delay).timeout
		hide_loading()
	else:
		hide_loading()
