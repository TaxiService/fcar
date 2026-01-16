class_name PeopleManager
extends Node

# Spritesheet configuration
@export var spritesheet_path: String = "res://people5.png"
@export var sprite_width: int = 300
@export var sprite_height: int = 600
@export var sprite_count: int = 11

# Person configuration
@export_category("Person Movement")
@export var walk_speed_min: float = 0.8
@export var walk_speed_max: float = 1.5
@export var walk_duration_min: float = 2.0
@export var walk_duration_max: float = 5.0
@export var wait_duration_min: float = 1.0
@export var wait_duration_max: float = 4.0

# Spawning configuration
@export_category("Spawning")
@export var spawn_interval: float = 2.0  # Seconds between spawn attempts
@export var auto_spawn: bool = true

# Quest/destination configuration
@export_category("Destinations")
@export_range(0.0, 1.0) var spawn_with_destination_chance: float = 0.3  # 30% of spawns want rides
@export_range(0.0, 1.0) var in_a_hurry_chance: float = 0.1  # 10% of passengers are in a hurry
@export var hurry_time: float = 60.0  # Seconds for in_a_hurry passengers
@export var min_fare_distance: float = 100.0  # Minimum distance for a valid fare (no short walks)

# Group configuration
@export_category("Groups")
@export_range(0.0, 1.0) var group_spawn_chance: float = 0.3  # 30% chance a fare is a group
@export var default_group_size: int = 2  # Default group size when spawning groups

@export_category("Hailing Animation")
@export var bob_rate_base: float = 1.5  # Base bob frequency in Hz (cycles per second)
@export var bob_rate_variance: float = 0.3  # Random variance ± this amount
@export var bob_hurry_multiplier: float = 2.0  # Hurried people bob this much faster
@export var bob_height: float = 0.2  # How high they jump (fraction of ~1.8m sprite height)

# Color sets - loaded from text files in color_sets_folder
# Surfaces reference these by index (0, 1, 2, etc. based on alphabetical filename order)
@export_category("Color Sets")
@export_dir var color_sets_folder: String = "res://color_sets"

@export_category("Debug")
@export var verbose_logging: bool = false  # Print individual spawn messages

# Loaded color sets (populated from text files)
var color_sets: Array[PackedColorArray] = []

# Runtime state
var spritesheet: SpriteSheet
var registered_surfaces: Array[SpawnSurface] = []
var registered_pois: Array[PointOfInterest] = []
var all_people: Array[Person] = []
var spawn_timer: float = 0.0
var spawn_counter: int = 0  # Increments with each spawn, used for deterministic color selection
var next_group_id: int = 1  # Counter for unique group IDs (0 reserved, -1 = solo)


func _ready():
	_load_spritesheet()
	_load_color_sets()


func _load_color_sets():
	color_sets.clear()

	var dir = DirAccess.open(color_sets_folder)
	if not dir:
		push_warning("PeopleManager: Could not open color sets folder: ", color_sets_folder)
		# Add default neutral set as fallback
		color_sets.append(PackedColorArray([Color.BLACK]))
		return

	# Get all .txt files sorted alphabetically
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".txt"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()

	# Load each file as a color set
	for fname in files:
		var colors = _parse_color_file(color_sets_folder + "/" + fname)
		if colors.size() > 0:
			color_sets.append(colors)
			if verbose_logging:
				print("PeopleManager: Loaded color set '", fname, "' with ", colors.size(), " colors")

	if color_sets.size() == 0:
		push_warning("PeopleManager: No color sets loaded, adding default")
		color_sets.append(PackedColorArray([Color.BLACK]))

	print("PeopleManager: Loaded %d color sets" % color_sets.size())


func _parse_color_file(path: String) -> PackedColorArray:
	var colors = PackedColorArray()

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("PeopleManager: Could not open color file: ", path)
		return colors

	while not file.eof_reached():
		var line = file.get_line().strip_edges()

		# Skip empty lines and comments
		if line.is_empty() or line.begins_with("#"):
			continue

		var color = _parse_color_line(line)
		if color != null:
			colors.append(color)

	return colors


func _parse_color_line(line: String) -> Variant:
	# Try hex format: #RRGGBB or RRGGBB
	if line.begins_with("#"):
		line = line.substr(1)

	if line.length() == 6 and line.is_valid_hex_number():
		var hex = line.hex_to_int()
		return Color(
			((hex >> 16) & 0xFF) / 255.0,
			((hex >> 8) & 0xFF) / 255.0,
			(hex & 0xFF) / 255.0
		)

	# Try RGB format: R, G, B (floats 0.0-1.0 or ints 0-255)
	var parts = line.split(",")
	if parts.size() >= 3:
		var r = parts[0].strip_edges().to_float()
		var g = parts[1].strip_edges().to_float()
		var b = parts[2].strip_edges().to_float()

		# If values > 1, assume 0-255 range
		if r > 1.0 or g > 1.0 or b > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0

		return Color(r, g, b)

	return null


func _get_color_set(index: int) -> PackedColorArray:
	if index < 0 or index >= color_sets.size():
		return color_sets[0] if color_sets.size() > 0 else PackedColorArray([Color.BLACK])
	return color_sets[index]


func create_material_for_color(color: Color) -> ShaderMaterial:
	# Create a new material with the given color
	# Each person needs unique material for their texture
	var shader = load("res://person_sprite.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color_add", Vector3(color.r, color.g, color.b))
	return mat


func get_color_from_set(set_index: int, person_index: int) -> Color:
	var colors = _get_color_set(set_index)
	if colors.size() == 0:
		return Color.BLACK  # No tint
	return colors[person_index % colors.size()]


func _process(delta: float):
	if auto_spawn:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_try_spawn_on_surfaces()


func _load_spritesheet():
	spritesheet = SpriteSheet.new()
	if spritesheet.load_horizontal(spritesheet_path, sprite_width, sprite_height, sprite_count):
		print("PeopleManager: Loaded ", spritesheet.get_frame_count(), " person sprites")
	else:
		push_warning("PeopleManager: Failed to load spritesheet: ", spritesheet_path)


func reload_sprites():
	if spritesheet and spritesheet.reload():
		print("PeopleManager: Reloaded spritesheet")
		# Update all existing people with their new textures
		for person in all_people:
			if is_instance_valid(person):
				var new_tex = spritesheet.get_frame(person.sprite_index)
				if new_tex:
					person.refresh_sprite(new_tex)
	else:
		push_warning("PeopleManager: Failed to reload spritesheet")


func register_surface(surface: SpawnSurface):
	if surface not in registered_surfaces:
		registered_surfaces.append(surface)


func unregister_surface(surface: SpawnSurface):
	registered_surfaces.erase(surface)


func register_poi(poi: PointOfInterest):
	if poi not in registered_pois:
		registered_pois.append(poi)
		if verbose_logging:
			print("PeopleManager: Registered POI '", poi.poi_name, "'")


func unregister_poi(poi: PointOfInterest):
	registered_pois.erase(poi)


func get_enabled_pois() -> Array[PointOfInterest]:
	var enabled: Array[PointOfInterest] = []
	for poi in registered_pois:
		if is_instance_valid(poi) and poi.enabled:
			enabled.append(poi)
	return enabled


func get_nearest_surface(pos: Vector3) -> SpawnSurface:
	# Find the nearest enabled SpawnSurface to the given position
	var nearest: SpawnSurface = null
	var nearest_dist: float = INF

	for surface in registered_surfaces:
		if not is_instance_valid(surface) or not surface.enabled:
			continue

		var surface_pos = surface.global_position
		var dist = pos.distance_to(surface_pos)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest = surface

	return nearest


func get_random_point_on_surface(surface: SpawnSurface) -> Vector3:
	# Get a random position within a surface's bounds
	if surface and surface.has_method("get_random_spawn_position"):
		return surface.get_random_spawn_position()
	return Vector3.ZERO


func _try_spawn_on_surfaces():
	# Clean up stale references (surfaces from freed building blocks)
	registered_surfaces = registered_surfaces.filter(func(s): return is_instance_valid(s))

	for surface in registered_surfaces:
		if not surface.enabled:
			continue
		if surface.can_spawn_more():
			# Decide: spawn solo person or group?
			var wants_destination = randf() < spawn_with_destination_chance
			var wants_group = wants_destination and randf() < group_spawn_chance

			if wants_group:
				_spawn_group_on_surface(surface, default_group_size)
			else:
				var person = spawn_person_on_surface(surface)
				# Solo person might want a destination
				if person and wants_destination:
					_assign_destination(person, surface)


func _spawn_group_on_surface(surface: SpawnSurface, group_size: int):
	# Check if surface has room for entire group
	var available = surface.max_people - surface.get_people_count()
	if available < group_size:
		# Not enough room, spawn solo instead
		var person = spawn_person_on_surface(surface)
		if person:
			_assign_destination(person, surface)
		return

	# Generate unique group ID
	var group_id = next_group_id
	next_group_id += 1

	# Spawn group members near each other
	var base_pos = surface.get_random_spawn_position()
	var group_members: Array[Person] = []

	for i in range(group_size):
		var person = spawn_person_on_surface(surface)
		if not person:
			continue

		# Assign group ID
		person.group_id = group_id

		# Position near each other (small offset)
		var offset = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		person.global_position = base_pos + offset

		group_members.append(person)

	if group_members.is_empty():
		return

	# Find a destination for the whole group
	var destination = _find_valid_destination(group_members[0], surface)
	if not destination:
		# No valid destination - group becomes wanderers (no group_id needed)
		for person in group_members:
			person.group_id = -1
		return

	# Assign same destination to all group members
	var is_hurry = randf() < in_a_hurry_chance
	for person in group_members:
		person.set_destination(destination)
		if is_hurry:
			person.in_a_hurry = true
			person.hurry_timer = hurry_time

	if verbose_logging:
		print("Group ", group_id, " spawned with ", group_members.size(), " members. In a hurry: ", is_hurry)


func _find_valid_destination(person: Person, _source_surface: SpawnSurface) -> Node:
	# Returns a valid destination node, or null if none found
	var valid_targets: Array[Node] = []
	var person_pos = person.global_position

	for other in all_people:
		if not is_instance_valid(other):
			continue
		if other == person:
			continue
		if other.destination != null:
			continue
		if other.current_state in [Person.State.BOARDING, Person.State.RIDING, Person.State.HAILING]:
			continue
		if person_pos.distance_to(other.global_position) < min_fare_distance:
			continue
		# Don't target someone in the same group
		if other.group_id != -1 and other.group_id == person.group_id:
			continue
		valid_targets.append(other)

	for poi in registered_pois:
		if is_instance_valid(poi) and poi.enabled:
			if person_pos.distance_to(poi.global_position) < min_fare_distance:
				continue
			valid_targets.append(poi)

	if valid_targets.is_empty():
		return null

	return valid_targets[randi() % valid_targets.size()]


func spawn_person_on_surface(surface: SpawnSurface) -> Person:
	if not spritesheet or spritesheet.get_frame_count() == 0:
		push_warning("PeopleManager: No sprites loaded")
		return null

	# Create person
	var person = Person.new()

	# Configure movement parameters
	person.walk_speed_min = walk_speed_min
	person.walk_speed_max = walk_speed_max
	person.walk_duration_min = walk_duration_min
	person.walk_duration_max = walk_duration_max
	person.wait_duration_min = wait_duration_min
	person.wait_duration_max = wait_duration_max

	# Configure bobbing parameters with per-person variance
	person.bob_rate = bob_rate_base + randf_range(-bob_rate_variance, bob_rate_variance)
	person.bob_height = bob_height
	person.bob_hurry_multiplier = bob_hurry_multiplier

	# Create material with color from surface's color set (deterministic based on spawn order)
	var color = get_color_from_set(surface.color_set_index, spawn_counter)
	spawn_counter += 1
	var mat = create_material_for_color(color)
	person.set_shared_material(mat)

	# Set random sprite (must be after material is set)
	var sprite_index = randi() % spritesheet.get_frame_count()
	person.set_sprite(spritesheet.get_frame(sprite_index), sprite_index)

	# Add to scene first (required before setting global_position)
	add_child(person)

	# Set bounds from surface
	var bounds = surface.get_bounds_world()
	person.set_bounds(bounds.min, bounds.max)

	# Position on surface
	person.global_position = surface.get_random_spawn_position()

	# Track the person
	surface.add_person(person)
	all_people.append(person)

	return person


func _assign_destination(person: Person, source_surface: SpawnSurface):
	# Find a valid destination
	var target = _find_valid_destination(person, source_surface)
	if not target:
		return  # No valid destinations

	# Assign destination
	person.set_destination(target)

	# Maybe make them in a hurry
	if randf() < in_a_hurry_chance:
		person.in_a_hurry = true
		person.hurry_timer = hurry_time

	# Debug output
	var dest_name = ""
	if target is Person:
		dest_name = "another person"
	elif target is PointOfInterest:
		dest_name = "POI: " + target.poi_name
	if verbose_logging:
		print("Solo person spawned with destination: ", dest_name, " | In a hurry: ", person.in_a_hurry)


func spawn_person_at(position: Vector3, bounds_min: Vector3 = Vector3.ZERO, bounds_max: Vector3 = Vector3.ZERO) -> Person:
	# Manual spawn at specific position
	if not spritesheet or spritesheet.get_frame_count() == 0:
		push_warning("PeopleManager: No sprites loaded")
		return null

	var person = Person.new()

	# Configure movement parameters
	person.walk_speed_min = walk_speed_min
	person.walk_speed_max = walk_speed_max
	person.walk_duration_min = walk_duration_min
	person.walk_duration_max = walk_duration_max
	person.wait_duration_min = wait_duration_min
	person.wait_duration_max = wait_duration_max

	# Configure bobbing parameters with per-person variance
	person.bob_rate = bob_rate_base + randf_range(-bob_rate_variance, bob_rate_variance)
	person.bob_height = bob_height
	person.bob_hurry_multiplier = bob_hurry_multiplier

	# Set random sprite
	var sprite_index = randi() % spritesheet.get_frame_count()
	person.set_sprite(spritesheet.get_frame(sprite_index), sprite_index)

	# Add to scene first (required before setting global_position)
	add_child(person)

	# Set bounds if provided
	if bounds_min != Vector3.ZERO or bounds_max != Vector3.ZERO:
		person.set_bounds(bounds_min, bounds_max)

	# Position
	person.global_position = position

	# Track
	all_people.append(person)

	return person


func remove_person(person: Person):
	if is_instance_valid(person):
		all_people.erase(person)
		person.queue_free()


func remove_all_people():
	for person in all_people:
		if is_instance_valid(person):
			person.queue_free()
	all_people.clear()


func get_people_count() -> int:
	# Clean up invalid references
	all_people = all_people.filter(func(p): return is_instance_valid(p))
	return all_people.size()


# Debug: print status
func print_status():
	print("PeopleManager Status:")
	print("  Sprites loaded: ", spritesheet.get_frame_count() if spritesheet else 0)
	print("  Registered surfaces: ", registered_surfaces.size())
	print("  Active people: ", get_people_count())
	if verbose_logging:
		for surface in registered_surfaces:
			if is_instance_valid(surface):
				print("    Surface enabled=", surface.enabled, " people=", surface.get_people_count(), "/", surface.max_people)
