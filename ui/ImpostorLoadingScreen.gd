# ImpostorLoadingScreen.gd
# A cool loading screen that shows impostor sprites being generated
# Attach to a CanvasLayer node
class_name ImpostorLoadingScreen
extends CanvasLayer

signal loading_complete

# UI Elements
var _background: ColorRect
var _title_label: Label
var _progress_label: Label
var _block_name_label: Label
var _sprite_display: TextureRect
var _sprite_container: Control
var _progress_bar: ProgressBar
var _recent_sprites: Array[TextureRect] = []

# Settings
@export var background_color: Color = Color(0.08, 0.08, 0.1, 1.0)
@export var accent_color: Color = Color(0.4, 0.8, 1.0)
@export var max_recent_sprites: int = 8  # Show last N generated sprites
@export var sprite_display_size: float = 196.0  # Main sprite preview size
@export var recent_sprite_size: float = 64.0  # Small sprite strip size

var _total_blocks: int = 0
var _current_block: int = 0


func _ready():
	layer = 200  # Above everything
	_build_ui()
	hide_screen()


func _build_ui():
	# Full screen dark background
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = background_color
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)
	
	# Main container
	var main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_preset(Control.PRESET_CENTER)
	main_container.anchor_left = 0.5
	main_container.anchor_right = 0.5
	main_container.anchor_top = 0.5
	main_container.anchor_bottom = 0.5
	main_container.offset_left = -200
	main_container.offset_right = 200
	main_container.offset_top = -200
	main_container.offset_bottom = 200
	main_container.add_theme_constant_override("separation", 16)
	add_child(main_container)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "GENERATING IMPOSTORS"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", accent_color)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_title_label)
	
	# Sprite display container (centered)
	_sprite_container = Control.new()
	_sprite_container.custom_minimum_size = Vector2(sprite_display_size, sprite_display_size)
	main_container.add_child(_sprite_container)
	
	# Main sprite display (shows current block from all angles)
	_sprite_display = TextureRect.new()
	_sprite_display.name = "SpriteDisplay"
	_sprite_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sprite_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_display.custom_minimum_size = Vector2(sprite_display_size, sprite_display_size)
	_sprite_display.set_anchors_preset(Control.PRESET_CENTER)
	_sprite_display.position = Vector2(-sprite_display_size / 2, -sprite_display_size / 2)
	_sprite_display.size = Vector2(sprite_display_size, sprite_display_size)
	_sprite_container.add_child(_sprite_display)
	
	# Block name label
	_block_name_label = Label.new()
	_block_name_label.text = "..."
	_block_name_label.add_theme_font_size_override("font_size", 14)
	_block_name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_block_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_block_name_label)
	
	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(300, 20)
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.show_percentage = false
	
	# Style the progress bar
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.2)
	bar_bg.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	
	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = accent_color
	bar_fill.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	
	main_container.add_child(_progress_bar)
	
	# Progress text
	_progress_label = Label.new()
	_progress_label.text = "0 / 0"
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_progress_label)
	
	# Recent sprites strip (shows last N generated)
	var recent_container = HBoxContainer.new()
	recent_container.name = "RecentSprites"
	recent_container.add_theme_constant_override("separation", 8)
	recent_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(recent_container)
	
	for i in range(max_recent_sprites):
		var recent_sprite = TextureRect.new()
		recent_sprite.custom_minimum_size = Vector2(recent_sprite_size, recent_sprite_size)
		recent_sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		recent_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		recent_sprite.modulate = Color(1, 1, 1, 0.3)  # Dim until used
		recent_container.add_child(recent_sprite)
		_recent_sprites.append(recent_sprite)


func show_screen():
	visible = true
	_progress_bar.value = 0
	_progress_label.text = "Preparing..."
	_block_name_label.text = "..."
	_sprite_display.texture = null
	
	# Clear recent sprites
	for sprite in _recent_sprites:
		sprite.texture = null
		sprite.modulate = Color(1, 1, 1, 0.3)


func hide_screen():
	visible = false


func set_total_blocks(count: int):
	_total_blocks = count
	_current_block = 0
	_progress_bar.max_value = count
	_progress_label.text = "0 / %d" % count


func update_progress(current: int, block_name: String, texture: ImageTexture):
	_current_block = current
	
	# Update progress bar
	_progress_bar.value = current
	_progress_label.text = "%d / %d" % [current, _total_blocks]
	
	# Update block name (trim path, show just filename without extension)
	var display_name = block_name.get_basename() if block_name else "..."
	_block_name_label.text = display_name
	
	# Update main sprite display
	if texture:
		_sprite_display.texture = texture
		
		# Shift recent sprites and add new one
		_shift_recent_sprites(texture)


func _shift_recent_sprites(new_texture: ImageTexture):
	# Shift all sprites to the left
	for i in range(_recent_sprites.size() - 1):
		_recent_sprites[i].texture = _recent_sprites[i + 1].texture
		_recent_sprites[i].modulate = _recent_sprites[i + 1].modulate
	
	# Add new texture at the end
	var last_idx = _recent_sprites.size() - 1
	_recent_sprites[last_idx].texture = new_texture
	_recent_sprites[last_idx].modulate = Color(1, 1, 1, 1.0)  # Full brightness


func finish_loading():
	_progress_label.text = "Complete!"
	_block_name_label.text = "All impostors generated"
	
	# Brief delay before hiding
	await get_tree().create_timer(0.5).timeout
	
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
