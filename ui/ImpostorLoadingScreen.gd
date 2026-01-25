# ImpostorLoadingScreen.gd
# Transparent overlay that shows impostor sprites flashing as they're generated
# Animates through each angle of the spritesheet for a spinning effect
class_name ImpostorLoadingScreen
extends CanvasLayer

signal loading_complete

# UI Elements
var _container: Control
var _sprite_display: Sprite2D  # Changed to Sprite2D for hframes support
var _label: Label

# Settings
@export var sprite_size: float = 128.0  # Size of the displayed sprite
@export var margin: float = 80.0  # Margin from screen edge
@export var accent_color: Color = Color(0.4, 0.8, 1.0)
@export var show_label: bool = true  # Show block name and progress
@export var frames_per_angle: int = 3  # How many frames to show each angle

# Position options
enum Position { TOP_RIGHT, TOP_LEFT, BOTTOM_RIGHT, BOTTOM_LEFT, CENTER, TOP_CENTER }
@export var screen_position: Position = Position.TOP_LEFT

# Animation state
var _current_texture: Texture2D
var _angle_count: int = 8
var _current_angle: int = 0
var _frame_counter: int = 0

var _total_blocks: int = 0
var _current_block: int = 0


func _ready():
	layer = 150  # Above game, but can be below other loading UI
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
	
	# CenterContainer to center the sprite
	var center = CenterContainer.new()
	center.custom_minimum_size = Vector2(sprite_size, sprite_size)
	vbox.add_child(center)
	
	# Sprite2D for individual frame display with hframes
	_sprite_display = Sprite2D.new()
	_sprite_display.name = "SpriteDisplay"
	_sprite_display.centered = true
	# Scale will be set when texture is assigned
	center.add_child(_sprite_display)
	
	# Label for block name and progress
	_label = Label.new()
	_label.text = ""
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", accent_color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.custom_minimum_size = Vector2(sprite_size, 0)
	_label.visible = show_label
	vbox.add_child(_label)
	
	# Position the container
	call_deferred("_update_position")


func _process(_delta: float):
	if not visible or not _current_texture:
		return
	
	# Animate through sprite angles
	_frame_counter += 1
	if _frame_counter >= frames_per_angle:
		_frame_counter = 0
		_current_angle = (_current_angle + 1) % _angle_count
		_sprite_display.frame = _current_angle


func _update_position():
	if not _container:
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	var container_size = Vector2(sprite_size, sprite_size + 24)  # sprite + label
	
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
		Position.TOP_CENTER:
			_container.position = Vector2(
				(viewport_size.x - sprite_size) / 2,
				margin
			)


func show_screen():
	visible = true
	_current_texture = null
	_sprite_display.texture = null
	_label.text = "Generating impostors..."
	_current_angle = 0
	_frame_counter = 0


func hide_screen():
	visible = false


func set_total_blocks(count: int):
	_total_blocks = count
	_current_block = 0
	_label.text = "0 / %d" % count


func update_progress(current: int, block_name: String, texture: ImageTexture):
	_current_block = current
	
	# Update sprite display with new texture
	if texture:
		_current_texture = texture
		_sprite_display.texture = texture
		
		# Calculate angle count from texture dimensions
		# Texture is a horizontal strip: width = sprite_size * angle_count
		var tex_width = texture.get_width()
		var tex_height = texture.get_height()
		_angle_count = maxi(1, tex_width / tex_height)  # Assuming square sprites
		
		# Set up hframes for animation
		_sprite_display.hframes = _angle_count
		_sprite_display.vframes = 1
		_sprite_display.frame = 0
		
		# Scale sprite to fit our display size
		var frame_width = tex_width / _angle_count
		var scale_factor = sprite_size / frame_width
		_sprite_display.scale = Vector2(scale_factor, scale_factor)
		
		# Reset animation
		_current_angle = 0
		_frame_counter = 0
	
	# Update label
	if show_label:
		var display_name = block_name.get_basename() if block_name else "..."
		_label.text = "%s (%d/%d)" % [display_name, current, _total_blocks]


func finish_loading():
	_label.text = "Done!"
	
	# Let it spin a bit more then hide
	await get_tree().create_timer(0.4).timeout
	
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
