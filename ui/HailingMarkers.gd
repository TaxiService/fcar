class_name HailingMarkers
extends CanvasLayer

# Configuration
@export var max_markers: int = 10
@export var marker_range: float = 300.0  # meters - shows markers
@export var selection_range: float = 15.0  # meters - max distance to select/confirm a group
@export var look_at_angle_threshold: float = 35.0  # degrees - shows distance label
@export var targeting_angle_threshold: float = 15.0  # degrees - tiebreaker when groups are similar distance
@export var distance_tiebreaker_threshold: float = 15.0  # meters - groups within this of nearest can be selected by looking
@export var marker_scale: float = 0.5  # Scale for the marker sprites
@export var label_offset: Vector2 = Vector2(14, -8)  # Offset from marker to label

# References (set by FCar)
var fcar: Node = null
var people_manager: Node = null

# Marker visuals
var marker_texture: Texture2D  # Selectable (magenta)
var marker_texture_targeted: Texture2D  # Currently targeted (cyan/green)
var marker_texture_out_of_range: Texture2D  # Too far to select (small, gray)
var marker_sprites: Array[Sprite2D] = []
var distance_labels: Array[Label] = []
var vertical_labels: Array[Label] = []  # Vertical distance indicators

# Targeting state
var current_groups: Array = []  # Updated periodically
var targeted_group_index: int = -1  # Index into current_groups, -1 = none

# Cached distance info (calculate once per marker, not every frame)
# Dictionary: group_id -> { horizontal_distance: String, vertical_text: String, vertical_color: Color }
var cached_distances: Dictionary = {}

# Performance: throttle expensive group scanning
var group_scan_timer: float = 0.0
var group_scan_interval: float = 0.15  # Scan for groups every 150ms

# Performance: track current label colors to avoid redundant theme overrides
var label_colors: Array[Color] = []  # Current color per distance_label
var vert_label_colors: Array[Color] = []  # Current color per vertical_label

# Performance: track current label text to avoid redundant updates
var label_texts: Array[String] = []
var vert_label_texts: Array[String] = []


func _ready():
	layer = 100  # Same layer as destination marker HUD
	_create_marker_textures()
	_create_marker_pool()


func _create_marker_textures():
	# Load marker sprite sheet (144x48, three 48x48 markers)
	# Layout: [destination | unselected fare | selected fare]
	var sprite_sheet = load("res://files/markers.png")
	if not sprite_sheet:
		push_error("HailingMarkers: Failed to load markers.png")
		return

	# Create atlas textures for each marker region
	# Unselected fare marker (middle, 48-96)
	var atlas_normal = AtlasTexture.new()
	atlas_normal.atlas = sprite_sheet
	atlas_normal.region = Rect2(48, 0, 48, 48)
	marker_texture = atlas_normal

	# Selected fare marker (rightmost, 96-144)
	var atlas_targeted = AtlasTexture.new()
	atlas_targeted.atlas = sprite_sheet
	atlas_targeted.region = Rect2(96, 0, 48, 48)
	marker_texture_targeted = atlas_targeted

	# Out of range marker (reuse unselected, will be grayed via modulate)
	marker_texture_out_of_range = atlas_normal


func _create_marker_pool():
	var default_color = Color(1.0, 0.2, 0.8, 1.0)  # Magenta

	for i in range(max_markers):
		# Create marker sprite
		var sprite = Sprite2D.new()
		sprite.texture = marker_texture
		sprite.scale = Vector2(marker_scale, marker_scale)
		sprite.visible = false
		add_child(sprite)
		marker_sprites.append(sprite)

		# Create distance label
		var label = Label.new()
		label.visible = false
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", default_color)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		label.add_theme_constant_override("outline_size", 5)
		add_child(label)
		distance_labels.append(label)
		label_colors.append(default_color)
		label_texts.append("")

		# Create vertical distance label
		var vert_label = Label.new()
		vert_label.visible = false
		vert_label.add_theme_font_size_override("font_size", 12)
		vert_label.add_theme_color_override("font_color", default_color)
		vert_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		vert_label.add_theme_constant_override("outline_size", 4)
		add_child(vert_label)
		vertical_labels.append(vert_label)
		vert_label_colors.append(default_color)
		vert_label_texts.append("")


# Performance helper: only update label color if it changed
func _set_label_color(index: int, color: Color):
	if label_colors[index] != color:
		label_colors[index] = color
		distance_labels[index].add_theme_color_override("font_color", color)


func _set_vert_label_color(index: int, color: Color):
	if vert_label_colors[index] != color:
		vert_label_colors[index] = color
		vertical_labels[index].add_theme_color_override("font_color", color)


# Performance helper: only update label text if it changed
func _set_label_text(index: int, text: String):
	if label_texts[index] != text:
		label_texts[index] = text
		distance_labels[index].text = text


func _set_vert_label_text(index: int, text: String):
	if vert_label_texts[index] != text:
		vert_label_texts[index] = text
		vertical_labels[index].text = text


func _process(delta):
	if not fcar or not people_manager:
		_hide_all()
		targeted_group_index = -1
		current_groups = []
		cached_distances.clear()
		return

	# Check if a group is currently boarding - show only their marker
	if fcar.confirmed_boarding_group.size() > 0:
		current_groups = [_get_boarding_group_data()]
		targeted_group_index = 0
		_update_markers_boarding_mode(current_groups)
		return

	if not fcar.is_ready_for_fares:
		_hide_all()
		targeted_group_index = -1
		current_groups = []
		cached_distances.clear()
		return

	# Throttle expensive group scanning (every 150ms instead of every frame)
	group_scan_timer += delta
	if group_scan_timer >= group_scan_interval:
		group_scan_timer = 0.0
		current_groups = _get_nearby_hailing_groups()

	# Update marker positions every frame (smooth), but groups list is throttled
	_update_markers(current_groups)


func get_targeted_group():
	# Returns the currently targeted group data, or null if none
	if targeted_group_index >= 0 and targeted_group_index < current_groups.size():
		return current_groups[targeted_group_index]
	return null


func clear_target():
	# Clears the current target selection
	targeted_group_index = -1


func _get_boarding_group_data() -> Dictionary:
	# Build group data for the currently boarding group
	var members = fcar.confirmed_boarding_group.filter(func(p): return is_instance_valid(p))
	if members.is_empty():
		return {"position": Vector3.ZERO, "destination": null, "members": [], "group_key": -999}

	# Calculate average position
	var avg_pos = Vector3.ZERO
	for p in members:
		avg_pos += p.global_position
	avg_pos /= members.size()

	# Use the group_id of the first member as the key, or a special boarding key
	var gid = members[0].group_id if members[0].group_id != -1 else -999

	return {
		"position": avg_pos,
		"destination": members[0].destination if is_instance_valid(members[0].destination) else null,
		"members": members,
		"group_key": gid
	}


func _update_markers_boarding_mode(groups: Array):
	# Simplified marker update for boarding mode - only show the boarding group
	var camera = get_viewport().get_camera_3d()
	if not camera or groups.is_empty():
		_hide_all()
		return

	var group = groups[0]
	if group.members.is_empty():
		_hide_all()
		return

	var marker_world_pos = group.position + Vector3(0, 2, 0)

	# Hide all markers except the first one
	for i in range(1, max_markers):
		marker_sprites[i].visible = false
		distance_labels[i].visible = false
		vertical_labels[i].visible = false

	# Check if in front of camera (using stable projection)
	if not MarkerUtils.is_in_front(camera, marker_world_pos):
		marker_sprites[0].visible = false
		distance_labels[0].visible = false
		vertical_labels[0].visible = false
		return

	# Project to screen (stable projection - no pitch bobbing)
	var screen_pos = MarkerUtils.project_position(camera, marker_world_pos)
	var screen_size = get_viewport().get_visible_rect().size

	# Clamp to screen edges if off-screen
	var margin = 40.0
	screen_pos.x = clamp(screen_pos.x, margin, screen_size.x - margin)
	screen_pos.y = clamp(screen_pos.y, margin, screen_size.y - margin)

	# Show the boarding group marker (always targeted/highlighted)
	marker_sprites[0].visible = true
	marker_sprites[0].position = screen_pos
	marker_sprites[0].texture = marker_texture_targeted
	marker_sprites[0].modulate = Color.WHITE  # Full color

	# Show distance to destination (with targeted color)
	if is_instance_valid(group.destination):
		var dist_to_dest = group.position.distance_to(group.destination.global_position)
		var targeted_color = Color(0.2, 1.0, 0.6, 1.0)  # Cyan/green

		_set_label_text(0, _format_distance(dist_to_dest))
		distance_labels[0].position = screen_pos + label_offset
		_set_label_color(0, targeted_color)
		distance_labels[0].visible = true

		# Show vertical distance (person to destination, not car to destination)
		var vert_info = MarkerUtils.format_vertical_distance(group.position.y, group.destination.global_position.y)
		_set_vert_label_text(0, vert_info.text)
		_set_vert_label_color(0, vert_info.color)
		vertical_labels[0].position = screen_pos + label_offset + Vector2(0, 16)
		vertical_labels[0].visible = true
	else:
		distance_labels[0].visible = false
		vertical_labels[0].visible = false


func _get_nearby_hailing_groups() -> Array:
	# Returns array of dictionaries: { position: Vector3, destination: Node, members: Array }
	var groups_by_id = {}  # group_id -> array of persons

	for person in people_manager.all_people:
		if not is_instance_valid(person):
			continue
		if not person.wants_ride():
			continue

		# Check distance from car
		var dist = fcar.global_position.distance_to(person.global_position)
		if dist > marker_range:
			continue

		# Group by group_id (-1 means solo, treat each solo as unique)
		var gid = person.group_id
		if gid == -1:
			# Solo - use unique negative key based on instance id
			gid = -person.get_instance_id()

		if not groups_by_id.has(gid):
			groups_by_id[gid] = []
		groups_by_id[gid].append(person)

	# Convert to array with average positions
	var result = []
	for gid in groups_by_id:
		var members = groups_by_id[gid]
		var avg_pos = Vector3.ZERO
		for p in members:
			avg_pos += p.global_position
		avg_pos /= members.size()

		# Get destination from first member (all group members share destination)
		var dest = members[0].destination

		result.append({
			"position": avg_pos,
			"destination": dest,
			"members": members,
			"group_key": gid  # For caching distance calculations
		})

	# Sort by distance (nearest first) and limit to max_markers
	result.sort_custom(func(a, b):
		return fcar.global_position.distance_to(a.position) < fcar.global_position.distance_to(b.position)
	)

	if result.size() > max_markers:
		result.resize(max_markers)

	return result


func _update_markers(groups: Array):
	var camera = get_viewport().get_camera_3d()
	if not camera:
		_hide_all()
		targeted_group_index = -1
		return

	var screen_size = get_viewport().get_visible_rect().size
	var cam_forward = -camera.global_transform.basis.z

	# Track which groups are currently visible (for cache cleanup)
	var visible_group_keys = []

	# First pass: determine visibility and calculate angles
	var visible_groups: Array = []  # Array of { index, angle, distance_from_car }

	for i in range(max_markers):
		if i >= groups.size():
			marker_sprites[i].visible = false
			distance_labels[i].visible = false
			vertical_labels[i].visible = false
			continue

		var group = groups[i]
		var marker_world_pos = group.position + Vector3(0, 2, 0)  # Slightly above group

		# Check if in front of camera (using stable projection)
		if not MarkerUtils.is_in_front(camera, marker_world_pos):
			marker_sprites[i].visible = false
			distance_labels[i].visible = false
			vertical_labels[i].visible = false
			continue

		# Project to screen (stable projection - no pitch bobbing)
		var screen_pos = MarkerUtils.project_position(camera, marker_world_pos)

		# Check if on screen (with small margin)
		var margin = 20.0
		if screen_pos.x < -margin or screen_pos.x > screen_size.x + margin:
			marker_sprites[i].visible = false
			distance_labels[i].visible = false
			vertical_labels[i].visible = false
			continue
		if screen_pos.y < -margin or screen_pos.y > screen_size.y + margin:
			marker_sprites[i].visible = false
			distance_labels[i].visible = false
			vertical_labels[i].visible = false
			continue

		# Calculate angle from camera forward (for targeting)
		var to_group = (marker_world_pos - camera.global_position).normalized()
		var dot = cam_forward.dot(to_group)
		var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))

		# Calculate distance from car
		var dist_from_car = fcar.global_position.distance_to(group.position)

		# Track visible group info
		visible_groups.append({
			"index": i,
			"angle": angle,
			"distance": dist_from_car,
			"screen_pos": screen_pos
		})

		# Show marker (texture will be set after we determine target)
		marker_sprites[i].visible = true
		marker_sprites[i].position = screen_pos

		# Show distance label if within look_at threshold
		if angle <= look_at_angle_threshold and is_instance_valid(group.destination):
			var group_key = group.group_key
			visible_group_keys.append(group_key)

			# Check cache first (calculate once per group, not every frame!)
			if not cached_distances.has(group_key):
				var dist_to_dest = group.position.distance_to(group.destination.global_position)
				var vert_info = MarkerUtils.format_vertical_distance(group.position.y, group.destination.global_position.y)
				cached_distances[group_key] = {
					"horizontal_text": _format_distance(dist_to_dest),
					"vertical_text": vert_info.text,
					"vertical_color": vert_info.color
				}

			# Use cached values (only update text if changed)
			var cached = cached_distances[group_key]
			_set_label_text(i, cached.horizontal_text)
			distance_labels[i].position = screen_pos + label_offset
			distance_labels[i].visible = true

			_set_vert_label_text(i, cached.vertical_text)
			_set_vert_label_color(i, cached.vertical_color)
			vertical_labels[i].position = screen_pos + label_offset + Vector2(0, 16)
			vertical_labels[i].visible = true
		else:
			distance_labels[i].visible = false
			vertical_labels[i].visible = false

	# Determine target: closest to car wins, unless similar distance then angle breaks tie
	# Only groups within selection_range can be targeted
	var best_target_index = -1

	if visible_groups.size() > 0:
		# Filter to only groups within selection range
		var selectable_groups = visible_groups.filter(func(vg): return vg.distance <= selection_range)

		if selectable_groups.size() > 0:
			# Sort by distance from car (nearest first)
			selectable_groups.sort_custom(func(a, b): return a.distance < b.distance)

			# Default: nearest selectable group
			best_target_index = selectable_groups[0].index
			var nearest_distance = selectable_groups[0].distance

			# Check if any other group is within tiebreaker threshold AND being looked at
			var best_looked_at_angle = INF
			for vg in selectable_groups:
				if vg.distance <= nearest_distance + distance_tiebreaker_threshold:
					# This group is close enough to be a tiebreaker candidate
					if vg.angle <= targeting_angle_threshold and vg.angle < best_looked_at_angle:
						best_looked_at_angle = vg.angle
						best_target_index = vg.index

	# Update targeted group
	targeted_group_index = best_target_index

	# Build a map of index -> distance for texture selection
	var distance_by_index = {}
	for vg in visible_groups:
		distance_by_index[vg.index] = vg.distance

	# Colors matching marker fill colors
	var color_targeted = Color(0.2, 1.0, 0.6, 1.0)  # Cyan/green
	var color_selectable = Color(1.0, 0.2, 0.8, 1.0)  # Magenta
	var color_out_of_range = Color(0.5, 0.5, 0.5, 1.0)  # Gray

	# Apply textures and label colors based on targeting and distance
	for i in range(max_markers):
		if not marker_sprites[i].visible:
			continue
		if i == targeted_group_index:
			marker_sprites[i].texture = marker_texture_targeted
			marker_sprites[i].modulate = color_targeted
			_set_label_color(i, color_targeted)
		elif distance_by_index.has(i) and distance_by_index[i] > selection_range:
			marker_sprites[i].texture = marker_texture_out_of_range
			marker_sprites[i].modulate = Color(0.5, 0.5, 0.5, 0.7)  # Gray and semi-transparent
			_set_label_color(i, color_out_of_range)
		else:
			marker_sprites[i].texture = marker_texture
			marker_sprites[i].modulate = color_selectable
			_set_label_color(i, color_selectable)

	# Clean up cached distances for groups that are no longer visible
	var keys_to_remove = []
	for key in cached_distances:
		if not visible_group_keys.has(key):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		cached_distances.erase(key)


func _format_distance(dist: float) -> String:
	return MarkerUtils.format_distance(dist)


func _hide_all():
	for sprite in marker_sprites:
		sprite.visible = false
	for label in distance_labels:
		label.visible = false
	for label in vertical_labels:
		label.visible = false
