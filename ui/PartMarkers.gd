class_name PartMarkers
extends CanvasLayer

# Screen-space markers above resting PersonParts during hospital mode.
# Same visual style as HailingMarkers: nearest part highlighted, off-screen arrows.
# No distance labels, no CORE/BODY color distinction.

@export var max_markers: int = 20
@export var marker_range: float = 300.0
@export var selection_range: float = 15.0
@export var marker_scale: float = 0.5
@export var marker_scale_edge: float = 0.4
@export var marker_edge_margin: float = 45.0
@export var arrow_edge_offset: float = -40.0

# References (set by FCar)
var fcar: Node = null
var people_manager: Node = null

# Marker visuals
var marker_texture: Texture2D
var marker_texture_targeted: Texture2D
var arrow_texture: Texture2D
var marker_sprites: Array[Sprite2D] = []
var arrow_sprites: Array[Sprite2D] = []

# Targeting state
var targeted_part_index: int = -1
var _current_parts: Array = []  # Array of { part, distance }

# Throttle part scanning
var _scan_timer: float = 0.0
var _scan_interval: float = 0.15

var active: bool = false


func _ready():
	layer = 100
	_create_marker_textures()
	_create_marker_pool()
	visible = false


func _create_marker_textures():
	var sprite_sheet = load("res://files/markers.png")
	if not sprite_sheet:
		push_error("PartMarkers: Failed to load markers.png")
		return

	var atlas_normal = AtlasTexture.new()
	atlas_normal.atlas = sprite_sheet
	atlas_normal.region = Rect2(48, 0, 48, 48)
	marker_texture = atlas_normal

	var atlas_targeted = AtlasTexture.new()
	atlas_targeted.atlas = sprite_sheet
	atlas_targeted.region = Rect2(96, 0, 48, 48)
	marker_texture_targeted = atlas_targeted

	# Procedural arrow (same as HailingMarkers)
	var arrow_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	arrow_img.fill(Color(0, 0, 0, 0))
	for y in range(32):
		for x in range(32):
			var cy = abs(y - 16)
			if x > 8 and x < 28 and cy < (28 - x) / 1.5:
				arrow_img.set_pixel(x, y, Color(0.314, 0.791, 0.627, 0.949))
	arrow_texture = ImageTexture.create_from_image(arrow_img)


func _create_marker_pool():
	for i in range(max_markers):
		var sprite = Sprite2D.new()
		sprite.texture = marker_texture
		sprite.scale = Vector2(marker_scale, marker_scale)
		sprite.visible = false
		add_child(sprite)
		marker_sprites.append(sprite)

		var arrow = Sprite2D.new()
		arrow.texture = arrow_texture
		arrow.scale = Vector2(1.0, 1.0)
		arrow.visible = false
		add_child(arrow)
		arrow_sprites.append(arrow)


func set_active(on: bool):
	active = on
	visible = on
	if not on:
		_hide_all()
		targeted_part_index = -1
		_current_parts.clear()


func get_targeted_part() -> PersonPart:
	if targeted_part_index >= 0 and targeted_part_index < _current_parts.size():
		var entry = _current_parts[targeted_part_index]
		if is_instance_valid(entry.part):
			return entry.part
	return null


func _process(delta: float):
	if not active or not fcar or not people_manager:
		_hide_all()
		return

	# Throttle part scanning
	_scan_timer += delta
	if _scan_timer >= _scan_interval:
		_scan_timer = 0.0
		_current_parts = _get_nearby_parts()

	_update_markers()


func _get_nearby_parts() -> Array:
	var result = []
	var car_pos = fcar.global_position

	for part in people_manager.all_parts:
		if not is_instance_valid(part):
			continue
		if not part.at_rest:
			continue

		var dist = car_pos.distance_to(part.global_position)
		if dist > marker_range:
			continue

		result.append({ "part": part, "distance": dist })

	# Sort nearest first, limit to pool size
	result.sort_custom(func(a, b): return a.distance < b.distance)
	if result.size() > max_markers:
		result.resize(max_markers)

	return result


func _update_markers():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		_hide_all()
		targeted_part_index = -1
		return

	var screen_size = get_viewport().get_visible_rect().size
	var screen_center = screen_size / 2.0

	var on_screen_entries: Array = []  # { index, distance, screen_pos }

	for i in range(max_markers):
		if i >= _current_parts.size():
			marker_sprites[i].visible = false
			arrow_sprites[i].visible = false
			continue

		var entry = _current_parts[i]
		var part = entry.part
		if not is_instance_valid(part):
			marker_sprites[i].visible = false
			arrow_sprites[i].visible = false
			continue

		var marker_world_pos = part.global_position + Vector3(0, 0.5, 0)
		var is_in_front = MarkerUtils.is_in_front(camera, marker_world_pos)
		var screen_pos = MarkerUtils.project_position(camera, marker_world_pos)

		if not is_in_front:
			screen_pos = screen_size - screen_pos

		var is_on_screen = (
			screen_pos.x >= marker_edge_margin and screen_pos.x <= screen_size.x - marker_edge_margin and
			screen_pos.y >= marker_edge_margin and screen_pos.y <= screen_size.y - marker_edge_margin and
			is_in_front
		)

		if is_on_screen:
			on_screen_entries.append({
				"index": i,
				"distance": entry.distance,
				"screen_pos": screen_pos
			})

			marker_sprites[i].visible = true
			marker_sprites[i].position = screen_pos
			marker_sprites[i].scale = Vector2(marker_scale, marker_scale)
			arrow_sprites[i].visible = false
		else:
			# Off-screen: edge marker with arrow
			var dir_to_marker = (screen_pos - screen_center).normalized()
			var marker_pos = _calc_edge_position(screen_center, dir_to_marker, screen_size, marker_edge_margin, 0.0)
			var arrow_pos = _calc_edge_position(screen_center, dir_to_marker, screen_size, marker_edge_margin, arrow_edge_offset)

			marker_sprites[i].visible = true
			marker_sprites[i].position = marker_pos
			marker_sprites[i].scale = Vector2(marker_scale_edge, marker_scale_edge)

			arrow_sprites[i].visible = true
			arrow_sprites[i].position = arrow_pos
			arrow_sprites[i].rotation = dir_to_marker.angle()
			arrow_sprites[i].scale = Vector2(marker_scale_edge * 2.0, marker_scale_edge * 2.0)

	# Targeting: nearest on-screen part within selection_range
	var best_target_index = -1
	if on_screen_entries.size() > 0:
		var selectable = on_screen_entries.filter(func(e): return e.distance <= selection_range)
		if selectable.size() > 0:
			selectable.sort_custom(func(a, b): return a.distance < b.distance)
			best_target_index = selectable[0].index

	targeted_part_index = best_target_index

	# Apply textures and colors
	var color_targeted = Color(0.2, 1.0, 0.6, 1.0)
	var color_selectable = Color(1.0, 0.2, 0.8, 1.0)
	var color_off_screen = Color(0.5, 0.5, 0.5, 1.0)

	var on_screen_by_index = {}
	for e in on_screen_entries:
		on_screen_by_index[e.index] = e

	for i in range(max_markers):
		if not marker_sprites[i].visible:
			continue

		if on_screen_by_index.has(i):
			var e = on_screen_by_index[i]
			if i == targeted_part_index:
				marker_sprites[i].texture = marker_texture_targeted
				marker_sprites[i].modulate = color_targeted
			elif e.distance > selection_range:
				marker_sprites[i].texture = marker_texture
				marker_sprites[i].modulate = Color(0.5, 0.5, 0.5, 0.7)
			else:
				marker_sprites[i].texture = marker_texture
				marker_sprites[i].modulate = color_selectable
		else:
			marker_sprites[i].texture = marker_texture
			marker_sprites[i].modulate = color_off_screen
			arrow_sprites[i].modulate = color_off_screen


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
	for sprite in marker_sprites:
		sprite.visible = false
	for arrow in arrow_sprites:
		arrow.visible = false
