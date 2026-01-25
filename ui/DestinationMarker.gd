class_name DestinationMarker
extends CanvasLayer

# Configuration
var marker_scale_max: float = 2.0  # Scale when very close
var marker_scale_min: float = 0.7  # Scale when far
var marker_scale_edge: float = 1.5  # Scale when at screen edge
var marker_close_distance: float = 2.0  # Distance for max scale
var marker_far_distance: float = 20.0  # Distance for min scale
var marker_edge_margin: float = 45.0  # Screen edge margin
var arrow_edge_offset: float = -55.0  # Arrow offset from edge
var label_edge_offset: float = -85.0  # Label offset from edge

# Visual nodes
var marker_sprite: Sprite2D
var marker_arrow: Sprite2D
var distance_label: Label
var vertical_label: Label

# External reference
var fcar: Node = null


func _ready():
	layer = 100  # Render on top
	_create_visuals()


func _create_visuals():
	# Create marker sprite using sprite sheet
	marker_sprite = Sprite2D.new()
	marker_sprite.name = "WaypointSprite"

	# Load destination marker from sprite sheet (leftmost 48x48 region)
	var sprite_sheet = load("res://files/markers.png")
	if sprite_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = sprite_sheet
		atlas.region = Rect2(0, 0, 48, 48)
		marker_sprite.texture = atlas
		marker_sprite.modulate = Color(1.0, 0.2, 0.8, 0.8) 
	else:
		push_error("DestinationMarker: Failed to load markers.png")

	marker_sprite.scale = Vector2(1.0, 1.0)
	marker_sprite.visible = false
	add_child(marker_sprite)

	# Create arrow for off-screen indication
	marker_arrow = Sprite2D.new()
	marker_arrow.name = "DirectionArrow"

	# For now, create a simple procedural arrow (could be replaced with sprite sheet later)
	var arrow_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	arrow_img.fill(Color(0, 0, 0, 0))

	for y in range(32):
		for x in range(32):
			var cy = abs(y - 16)
			if x > 8 and x < 28 and cy < (28 - x) / 1.5:
				arrow_img.set_pixel(x, y, Color(1.0, 0.2, 0.8, 0.95))

	marker_arrow.texture = ImageTexture.create_from_image(arrow_img)
	marker_arrow.scale = Vector2(1.5, 1.5)
	marker_arrow.visible = false
	add_child(marker_arrow)

	# Create distance label
	distance_label = Label.new()
	distance_label.name = "DistanceLabel"
	distance_label.visible = false
	distance_label.add_theme_font_size_override("font_size", 16)
	distance_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.8, 1.0))  # Magenta
	distance_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))  # Black outline
	distance_label.add_theme_constant_override("outline_size", 6)
	add_child(distance_label)

	# Create vertical distance label
	vertical_label = Label.new()
	vertical_label.name = "VerticalLabel"
	vertical_label.visible = false
	vertical_label.add_theme_font_size_override("font_size", 14)
	vertical_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))  # Black outline
	vertical_label.add_theme_constant_override("outline_size", 5)
	add_child(vertical_label)


func _process(_delta):
	_update_marker()


func _update_marker():
	if not fcar:
		_hide_all()
		return

	# Find the first passenger with a valid destination
	var dest: Node = null
	var passengers = fcar.passengers if "passengers" in fcar else []
	for person in passengers:
		if is_instance_valid(person) and is_instance_valid(person.destination):
			dest = person.destination
			break

	if not dest:
		_hide_all()
		return

	# Get camera for projection
	var camera = get_viewport().get_camera_3d()
	if not camera:
		_hide_all()
		return

	var dest_pos = dest.global_position + Vector3(0, 2, 0)  # Slightly above destination
	var screen_size = get_viewport().get_visible_rect().size

	# Calculate distances
	var car_to_dest_distance = fcar.global_position.distance_to(dest.global_position)
	var camera_distance = camera.global_position.distance_to(dest_pos)

	# Calculate scale based on camera distance
	var scale_t = 0.0
	if marker_far_distance > marker_close_distance:
		scale_t = clamp(
			(camera_distance - marker_close_distance) / (marker_far_distance - marker_close_distance),
			0.0, 1.0
		)
	var current_scale = lerp(marker_scale_max, marker_scale_min, scale_t)
	var scale_vec = Vector2(current_scale, current_scale)

	# Use stable projection (yaw-only, no pitch bobbing)
	var is_in_front = MarkerUtils.is_in_front(camera, dest_pos)
	var screen_pos = MarkerUtils.project_position(camera, dest_pos)

	# Handle behind-camera case
	if not is_in_front:
		screen_pos = screen_size - screen_pos

	# Check if on screen
	var is_on_screen = (
		screen_pos.x >= marker_edge_margin and screen_pos.x <= screen_size.x - marker_edge_margin and
		screen_pos.y >= marker_edge_margin and screen_pos.y <= screen_size.y - marker_edge_margin and
		is_in_front
	)

	# Update distance text
	distance_label.text = MarkerUtils.format_distance(car_to_dest_distance)
	distance_label.visible = true

	# Update vertical distance text
	var vert_info = MarkerUtils.format_vertical_distance(fcar.global_position.y, dest.global_position.y)
	vertical_label.text = vert_info.text
	vertical_label.add_theme_color_override("font_color", vert_info.color)
	vertical_label.visible = true

	if is_on_screen:
		_show_on_screen(screen_pos, scale_vec)
	else:
		_show_off_screen(screen_pos, screen_size)


func _show_on_screen(screen_pos: Vector2, scale_vec: Vector2):
	marker_sprite.visible = true
	marker_sprite.position = screen_pos
	marker_sprite.scale = scale_vec
	marker_arrow.visible = false

	# Position labels next to marker
	distance_label.position = screen_pos + Vector2(20, -12)
	vertical_label.position = screen_pos + Vector2(20, 6)


func _show_off_screen(screen_pos: Vector2, screen_size: Vector2):
	var screen_center = screen_size / 2.0
	var dir_to_marker = (screen_pos - screen_center).normalized()

	# Calculate edge positions for marker, arrow, and label
	var marker_pos = _calc_edge_position(screen_center, dir_to_marker, screen_size, marker_edge_margin, 0.0)
	var arrow_pos = _calc_edge_position(screen_center, dir_to_marker, screen_size, marker_edge_margin, arrow_edge_offset)
	var label_pos = _calc_edge_position(screen_center, dir_to_marker, screen_size, marker_edge_margin, label_edge_offset)

	var edge_scale_vec = Vector2(marker_scale_edge, marker_scale_edge)

	# Show marker at edge
	marker_sprite.visible = true
	marker_sprite.position = marker_pos
	marker_sprite.scale = edge_scale_vec

	# Show arrow pointing toward destination
	marker_arrow.visible = true
	marker_arrow.position = arrow_pos
	marker_arrow.rotation = dir_to_marker.angle()
	marker_arrow.scale = edge_scale_vec

	# Center labels on their positions
	distance_label.position = label_pos - Vector2(distance_label.size.x / 2, distance_label.size.y + 2)
	vertical_label.position = label_pos - Vector2(vertical_label.size.x / 2, -2)


func _calc_edge_position(center: Vector2, direction: Vector2, screen_size: Vector2, margin: float, offset: float) -> Vector2:
	var max_x = screen_size.x / 2.0 - margin + offset
	var max_y = screen_size.y / 2.0 - margin + offset

	if abs(direction.x) < 0.001 and abs(direction.y) < 0.001:
		return center

	var scale_x = max_x / abs(direction.x) if abs(direction.x) > 0.001 else 99999.0
	var scale_y = max_y / abs(direction.y) if abs(direction.y) > 0.001 else 99999.0
	var edge_scale = min(scale_x, scale_y)

	return center + direction * edge_scale


func _hide_all():
	marker_sprite.visible = false
	marker_arrow.visible = false
	distance_label.visible = false
	vertical_label.visible = false
