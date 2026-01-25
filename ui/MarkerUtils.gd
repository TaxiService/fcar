class_name MarkerUtils
extends RefCounted

# ===== TEXTURE GENERATION =====

static func create_diamond_texture(size: int, fill_color: Color, border_color: Color, border_thickness: int = 3) -> ImageTexture:
	# Creates a diamond shape using Manhattan distance
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = size / 2
	var outer_radius = center - 1
	var inner_radius = outer_radius - border_thickness

	for y in range(size):
		for x in range(size):
			var cx = abs(x - center)
			var cy = abs(y - center)
			var dist = cx + cy

			if dist <= outer_radius:
				if dist > inner_radius:
					img.set_pixel(x, y, border_color)
				else:
					img.set_pixel(x, y, fill_color)

	return ImageTexture.create_from_image(img)


static func create_arrow_texture(size: int, fill_color: Color, border_color: Color) -> ImageTexture:
	# Creates a triangular arrow pointing right
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center_y = size / 2

	for y in range(size):
		for x in range(size):
			# Arrow pointing right: wider at left, point at right
			var dist_from_center = abs(y - center_y)
			var max_dist_at_x = (size - x) * 0.5  # Gets narrower as x increases

			if dist_from_center <= max_dist_at_x and x < size - 2:
				# Check if on border
				var is_border = (
					dist_from_center >= max_dist_at_x - 2 or
					x <= 2 or
					x >= size - 4
				)
				if is_border:
					img.set_pixel(x, y, border_color)
				else:
					img.set_pixel(x, y, fill_color)

	return ImageTexture.create_from_image(img)


# ===== DISTANCE FORMATTING =====

static func format_distance(dist: float) -> String:
	if dist < 1000:
		# Round to nearest 10 meters
		var rounded = int(round(dist / 10.0) * 10)
		return str(rounded) + "m"
	else:
		# Format as X.Xkm for kilometers
		return str(snapped(dist / 1000.0, 0.1)) + "km"


static func format_vertical_distance(car_y: float, target_y: float) -> Dictionary:
	var diff = target_y - car_y
	var abs_diff = int(round(abs(diff) / 10.0) * 10)

	if diff > 50.0:
		return { "text": str(abs_diff) + "m \u2191", "color": Color(0.3, 1.0, 0.3) }  # Green, up arrow
	elif diff < -50.0:
		return { "text": str(abs_diff) + "m \u2193", "color": Color(1.0, 0.2, 0.8) }  # Magenta, down arrow
	else:
		return { "text": str(abs_diff) + "m \u2195", "color": Color(0.6, 0.6, 0.6) }  # Grey, up-down arrow


# ===== PROJECTION =====

static func project_position(camera: Camera3D, world_pos: Vector3) -> Vector2:
	# Simple wrapper around camera projection
	return camera.unproject_position(world_pos)


static func is_in_front(camera: Camera3D, world_pos: Vector3) -> bool:
	# Check if position is in front of camera
	var cam_forward = -camera.global_transform.basis.z
	var to_target = (world_pos - camera.global_position).normalized()
	return cam_forward.dot(to_target) > 0


static func clamp_to_screen_edge(screen_pos: Vector2, screen_size: Vector2, margin: float) -> Dictionary:
	# Clamps position to screen edge with margin, returns direction to original position
	var screen_center = screen_size / 2.0
	var dir_to_pos = (screen_pos - screen_center).normalized()

	# Check if already on screen
	var is_on_screen = (
		screen_pos.x >= margin and screen_pos.x <= screen_size.x - margin and
		screen_pos.y >= margin and screen_pos.y <= screen_size.y - margin
	)

	if is_on_screen:
		return { "position": screen_pos, "direction": dir_to_pos, "is_clamped": false }

	# Find intersection with screen edge
	var max_x = screen_size.x / 2.0 - margin
	var max_y = screen_size.y / 2.0 - margin

	var clamped_pos = screen_center
	if abs(dir_to_pos.x) > 0.001 or abs(dir_to_pos.y) > 0.001:
		var scale_x = max_x / abs(dir_to_pos.x) if abs(dir_to_pos.x) > 0.001 else 99999.0
		var scale_y = max_y / abs(dir_to_pos.y) if abs(dir_to_pos.y) > 0.001 else 99999.0
		var edge_scale = min(scale_x, scale_y)
		clamped_pos = screen_center + dir_to_pos * edge_scale

	return { "position": clamped_pos, "direction": dir_to_pos, "is_clamped": true }
