class_name GameOverScreen
extends CanvasLayer

var shift_manager: ShiftManager = null
var justice_system: JusticeSystem = null

var _overlay: ColorRect
var _title_label: Label
var _stats_label: Label
var _prompt_label: Label


func _ready():
	layer = 200
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui():
	# Dark overlay
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# GAME OVER title
	_title_label = Label.new()
	_title_label.text = "GAME OVER"
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_title_label.add_theme_constant_override("outline_size", 8)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Stats
	_stats_label = Label.new()
	_stats_label.text = ""
	_stats_label.add_theme_font_size_override("font_size", 20)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats_label)

	# Key prompts
	_prompt_label = Label.new()
	_prompt_label.text = "[R] Restart    [N] New Game    [Esc] Quit"
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_label)


func show_game_over():
	# Build stats text
	var lines: Array[String] = []

	if shift_manager:
		lines.append("Score: %d" % shift_manager.get_score())
		lines.append("Fares completed: %d" % shift_manager.get_fare_count())

	if justice_system:
		lines.append("People broken: %d" % justice_system.total_people_broken)
		lines.append("Cores squished: %d" % justice_system.total_cores_squished)

	_stats_label.text = "\n".join(lines)

	visible = true
	get_tree().paused = true


func _unhandled_input(event: InputEvent):
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_restart_same_seed()
			KEY_N:
				_new_game()
			KEY_ESCAPE:
				get_tree().paused = false
				get_tree().quit()


func _restart_same_seed():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _new_game():
	# Set CityGenerator to use random seed before reload
	if has_node("/root/CityGrid"):
		var city_grid = get_node("/root/CityGrid")
		if city_grid.get("city_generator") and city_grid.city_generator:
			city_grid.city_generator.use_random_seed = true
	get_tree().paused = false
	get_tree().reload_current_scene()
