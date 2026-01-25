# ImpostorLoadingScreen.gd
# Transparent overlay that shows impostor sprites flashing as they're generated
# Designed to overlay on existing loading screens
class_name ImpostorLoadingScreen
extends CanvasLayer

signal loading_complete

# UI Elements
var _container: Control
var _sprite_display: TextureRect
var _label: Label

# Settings
@export var sprite_size: float = 128.0  # Size of the flashing sprite
@export var margin: float = 20.0  # Margin from screen edge
@export var accent_color: Color = Color(0.4, 0.8, 1.0)
@export var show_label: bool = true  # Show block name and progress

# Position options
enum Position { TOP_RIGHT, TOP_LEFT, BOTTOM_RIGHT, BOTTOM_LEFT, CENTER, TOP }
@export var screen_position: Position = Position.TOP

var _total_blocks: int = 0
var _current_block: int = 0


func _ready():
	layer = 150  # Above game, but can be below other loading UI if needed
	_build_ui()
	hide_screen()


func _build_ui():
	# Main container - positioned based on screen_position
	_container = Control.new()
	_container.name = "ImpostorOverlay"
	add_child(_container)
	
	# VBox to hold sprite and label
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_container.add_child(vbox)
	
	# Sprite display (shows current block sprite sheet)
	_sprite_display = TextureRect.new()
	_sprite_display.name = "SpriteDisplay"
	_sprite_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sprite_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_display.custom_minimum_size = Vector2(sprite_size, sprite_size)
	vbox.add_child(_sprite_display)
	
	# Label for block name and progress
	_label = Label.new()
	_label.text = ""
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", accent_color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.visible = show_label
	vbox.add_child(_label)
	
	# Position the container
	_update_position()


func _update_position():
	if not _container:
		return
	
	# Get viewport size (deferred to ensure it's ready)
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	
	var container_size = Vector2(sprite_size, sprite_size + 20)  # sprite + label
	
	match screen_position:
		Position.TOP_RIGHT:
			_container.position = Vector2(
				viewport_size.x - sprite_size - margin,
				margin
			)
		Position.TOP_LEFT:
			_container.position = Vector2(margin, margin)
		Position.BOTTOM_RIGHT:
			_container.position = Vector2(
				viewport_size.x - sprite_size - margin,
				viewport_size.y - container_size.y - margin
			)
		Position.BOTTOM_LEFT:
			_container.position = Vector2(
				margin,
				viewport_size.y - container_size.y - margin
			)
		Position.CENTER:
			_container.position = Vector2(
				(viewport_size.x - sprite_size) / 2,
				(viewport_size.y - container_size.y) / 2
			)
		Position.TOP:
			_container.position = Vector2(
				(viewport_size.x - sprite_size) / 2, 
				margin
			)


func show_screen():
	visible = true
	_sprite_display.texture = null
	_label.text = "Generating impostors..."


func hide_screen():
	visible = false


func set_total_blocks(count: int):
	_total_blocks = count
	_current_block = 0
	_label.text = "0 / %d" % count


func update_progress(current: int, block_name: String, texture: ImageTexture):
	_current_block = current
	
	# Update sprite display - this creates the "flashing" effect
	if texture:
		_sprite_display.texture = texture
	
	# Update label
	if show_label:
		var display_name = block_name.get_basename() if block_name else "..."
		_label.text = "%s (%d/%d)" % [display_name, current, _total_blocks]


func finish_loading():
	_label.text = "Done!"
	
	# Brief flash then hide
	await get_tree().create_timer(0.3).timeout
	
	loading_complete.emit()
	hide_screen()


# Connect to BuildingImpostorGenerator
func connect_to_generator(generator: BuildingImpostorGenerator):
	generator.generation_started.connect(_on_generation_started)
	generator.generation_progress.connect(_on_generation_progress)
	generator.generation_complete.connect(_on_generation_complete)


func _on_generation_started(block_count: int):
	show_screen()
	set_total_blocks(block_count)


func _on_generation_progress(current: int, block_name: String, texture: ImageTexture):
	update_progress(current, block_name, texture)


func _on_generation_complete(_impostor_data: Dictionary):
	finish_loading()
