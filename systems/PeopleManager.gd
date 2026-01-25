# PeopleManager.gd - Optimized with object pooling and batched spawning
# Performance improvements:
# 1. Object pool - pre-instantiate people, reuse instead of create/destroy
# 2. Batched spawning - spawn 1-2 per frame instead of all at once
# 3. Material caching - share materials by color to enable GPU batching
# 4. Smart processing - disable _process on distant/hidden people
class_name PeopleManager
extends Node

# Signals for monitoring
signal pool_ready(pool_size: int)
signal spawn_complete(count: int)

# Spritesheet configuration
@export var spritesheet_path: String = "res://files/people5.png"
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

# Pool configuration
@export_category("Object Pool")
@export var pool_size: int = 200  # Pre-instantiate this many people
@export var pool_growth_size: int = 20  # Grow pool by this many if exhausted
@export var warm_pool_on_start: bool = true  # Create pool during loading

@export_category("Performance")
@export var despawn_distance: float = 550.0  # Remove people beyond this (should be >= LOD hide distance)
@export var despawn_check_interval: float = 3.0  # Check every N seconds
@export var max_total_people: int = 2000  # Hard cap on total people

# Spawning configuration  
@export_category("Spawning")
@export var spawn_interval: float = 2.0
@export var auto_spawn: bool = true
@export var spawns_per_frame: int = 2  # Max spawns per frame (spreads cost)
@export var spawn_queue_enabled: bool = true  # Use queued spawning

# Quest/destination configuration
@export_category("Destinations")
@export_range(0.0, 1.0) var spawn_with_destination_chance: float = 0.3
@export_range(0.0, 1.0) var in_a_hurry_chance: float = 0.1
@export var hurry_time: float = 60.0
@export var min_fare_distance: float = 100.0

# Group configuration
@export_category("Groups")
@export_range(0.0, 1.0) var group_spawn_chance: float = 0.3
@export var default_group_size: int = 2

# Hailing animation
@export_category("Hailing Animation")
@export var bob_rate_base: float = 1.5
@export var bob_rate_variance: float = 0.3
@export var bob_hurry_multiplier: float = 2.0
@export var bob_height: float = 0.2

# Color sets
@export_category("Color Sets")
@export_dir var color_sets_folder: String = "res://color_sets"

# Smart processing
@export_category("Performance")
@export var process_distance: float = 300.0  # Only process people within this range
@export var process_check_interval: float = 1.0  # How often to update process states
@export var verbose_logging: bool = false

# Runtime state
var spritesheet: SpriteSheet
var registered_surfaces: Array[SpawnSurface] = []
var registered_pois: Array[PointOfInterest] = []
var all_people: Array[Person] = []  # Active people
var spawn_timer: float = 0.0
var spawn_counter: int = 0
var next_group_id: int = 1

# Object pool
var _pool: Array[Person] = []  # Inactive, ready to use
var _pool_container: Node  # Hidden container for pooled objects
var _pool_ready: bool = false

# Spawn queue (for batched spawning)
var _spawn_queue: Array[Dictionary] = []  # [{surface, wants_dest, wants_group, group_size}]

# Material cache (shared materials for GPU batching)
var _material_cache: Dictionary = {}  # color_hash -> ShaderMaterial
var _shader: Shader

# Pixel LOD materials (small set for maximum batching)
var _pixel_material_cache: Dictionary = {}  # quantized_color_key -> ShaderMaterial
var _pixel_texture: ImageTexture = null  # 1x1 white texture for pixel sprites
const PIXEL_LOD_COLOR_LEVELS: int = 4  # Quantize to 4 levels per channel = 64 colors max


# Color sets
var color_sets: Array[PackedColorArray] = []

# Process management
var _process_check_timer: float = 0.0
var _player_position: Vector3 = Vector3.ZERO
var _has_player_position: bool = false
var _camera: Camera3D = null
var _despawn_timer: float = 0.0

func _ready():
	_load_spritesheet()
	_load_color_sets()
	_shader = load("res://mats/person_sprite.gdshader")
	_create_pixel_texture()

	# Create pool container (keeps pooled nodes in tree but hidden)
	_pool_container = Node.new()
	_pool_container.name = "PersonPool"
	add_child(_pool_container)
	
	if warm_pool_on_start:
		# Defer pool creation to avoid blocking scene load
		call_deferred("_warm_pool")


func _warm_pool():
	print("PeopleManager: Warming object pool (%d people)..." % pool_size)
	var start_time = Time.get_ticks_msec()
	
	for i in range(pool_size):
		var person = _create_pooled_person()
		_pool.append(person)
		
		# Yield every 10 to keep UI responsive during loading
		if i % 10 == 0 and i > 0:
			await get_tree().process_frame
	
	var elapsed = Time.get_ticks_msec() - start_time
	print("PeopleManager: Pool ready (%d people in %dms)" % [_pool.size(), elapsed])
	_pool_ready = true
	pool_ready.emit(_pool.size())


func _create_pooled_person() -> Person:
	var person = Person.new()
	
	# Configure (these don't change per-spawn)
	person.walk_speed_min = walk_speed_min
	person.walk_speed_max = walk_speed_max
	person.walk_duration_min = walk_duration_min
	person.walk_duration_max = walk_duration_max
	person.wait_duration_min = wait_duration_min
	person.wait_duration_max = wait_duration_max
	person.bob_height = bob_height
	person.bob_hurry_multiplier = bob_hurry_multiplier
	
	# Add to pool container (in tree but won't render)
	_pool_container.add_child(person)
	person.visible = false
	person.set_process(false)
	person.set_physics_process(false)
	
	return person


func _acquire_from_pool() -> Person:
	if _pool.is_empty():
		# Pool exhausted - grow it
		if verbose_logging:
			print("PeopleManager: Pool exhausted, growing by %d" % pool_growth_size)
		for i in range(pool_growth_size):
			_pool.append(_create_pooled_person())
	
	var person = _pool.pop_back()
	
	# Move from pool container to manager (makes it renderable)
	_pool_container.remove_child(person)
	add_child(person)
	
	# Reset state
	person.visible = true
	person.set_process(true)
	person._reset_for_reuse()
	
	return person


func _return_to_pool(person: Person):
	if not is_instance_valid(person):
		return
	
	# Remove from active tracking
	all_people.erase(person)
	
	# Clean up state
	person.visible = false
	person.set_process(false)
	person.set_physics_process(false)
	person.destination = null
	person.target_car = null
	person.group_id = -1
	
	# Move back to pool container
	remove_child(person)
	_pool_container.add_child(person)
	_pool.append(person)


func _process(delta: float):
	# Process spawn queue (batched)
	if spawn_queue_enabled and not _spawn_queue.is_empty():
		_process_spawn_queue()
	
	# Auto spawn timer
	if auto_spawn and _pool_ready:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_queue_spawns_on_surfaces()
	
	# Smart process management (periodically enable/disable _process on distant people)
	_process_check_timer += delta
	if _process_check_timer >= process_check_interval:
		_process_check_timer = 0.0
		_update_process_states()
	
	# Despawn distant people and enforce cap
	_despawn_timer += delta
	if _despawn_timer >= despawn_check_interval:
		_despawn_timer = 0.0
		_despawn_distant_people()
		_enforce_population_cap()
	# Debug print (every 300 frames)
	if verbose_logging and Engine.get_frames_drawn() % 300 == 0:
		print("=== PeopleManager ===")
		print("  Materials: %d close + %d pixel" % [_material_cache.size(), _pixel_material_cache.size()])
		print("  Total people: ", all_people.size())
		print("  Pool available: ", _pool.size())


func _process_spawn_queue():
	var spawned_this_frame = 0

	while not _spawn_queue.is_empty() and spawned_this_frame < spawns_per_frame:
		# Enforce cap
		if all_people.size() >= max_total_people:
			_spawn_queue.clear()
			break

		var spawn_data = _spawn_queue.pop_front()

		# Check if surface is still valid (might have been freed)
		if not is_instance_valid(spawn_data.surface):
			continue

		if spawn_data.wants_group:
			_do_spawn_group(spawn_data.surface, spawn_data.group_size)
		else:
			var person = _do_spawn_person(spawn_data.surface)
			if person and spawn_data.wants_dest:
				_assign_destination(person, spawn_data.surface)

		spawned_this_frame += 1


func _queue_spawns_on_surfaces():
	# Enforce population cap - don't queue spawns if at limit
	if all_people.size() >= max_total_people:
		return

	# Clean up stale references
	registered_surfaces = registered_surfaces.filter(func(s): return is_instance_valid(s))

	for surface in registered_surfaces:
		if not surface.enabled:
			continue
		if not surface.can_spawn_more():
			continue

		# Check cap again (might have queued enough already)
		if all_people.size() + _spawn_queue.size() >= max_total_people:
			break

		var wants_destination = randf() < spawn_with_destination_chance
		var wants_group = wants_destination and randf() < group_spawn_chance

		_spawn_queue.append({
			"surface": surface,
			"wants_dest": wants_destination,
			"wants_group": wants_group,
			"group_size": default_group_size,
		})

func _despawn_distant_people():
	if not Person.lod_camera:
		return
	
	var camera_pos = Person.lod_camera.global_position
	var despawn_dist_sq = despawn_distance * despawn_distance
	var despawned = 0
	
	# Iterate backwards for safe removal
	for i in range(all_people.size() - 1, -1, -1):
		var person = all_people[i]
		if not is_instance_valid(person):
			all_people.remove_at(i)
			continue
		
		# Don't despawn people actively involved with player
		if person.current_state in [Person.State.BOARDING, Person.State.RIDING, 
									 Person.State.EXITING, Person.State.HAILING]:
			continue
		
		var dx = person.global_position.x - camera_pos.x
		var dz = person.global_position.z - camera_pos.z
		var dist_sq = dx * dx + dz * dz
		
		if dist_sq > despawn_dist_sq:
			# Remove from surface tracking
			for surface in registered_surfaces:
				if is_instance_valid(surface):
					surface.spawned_people.erase(person)

			# Return to pool (removes from all_people internally)
			_return_to_pool(person)
			despawned += 1
	
	if despawned > 0 and verbose_logging:
		print("PeopleManager: Despawned %d distant people, %d remaining" % [despawned, all_people.size()])


func _enforce_population_cap():
	# If over max, cull the furthest people
	var overflow = all_people.size() - max_total_people
	if overflow <= 0:
		return

	if not Person.lod_camera:
		return

	var camera_pos = Person.lod_camera.global_position

	# Build list of (person, distance_sq) for cullable people
	var cullable: Array = []
	for person in all_people:
		if not is_instance_valid(person):
			continue
		# Don't cull people interacting with player
		if person.current_state in [Person.State.BOARDING, Person.State.RIDING,
									 Person.State.EXITING, Person.State.HAILING]:
			continue
		var dx = person.global_position.x - camera_pos.x
		var dz = person.global_position.z - camera_pos.z
		cullable.append({"person": person, "dist_sq": dx * dx + dz * dz})

	# Sort by distance (furthest first)
	cullable.sort_custom(func(a, b): return a.dist_sq > b.dist_sq)

	# Cull the furthest ones
	var culled = 0
	for i in range(min(overflow, cullable.size())):
		var person = cullable[i].person
		for surface in registered_surfaces:
			if is_instance_valid(surface):
				surface.spawned_people.erase(person)
		_return_to_pool(person)
		culled += 1

	if culled > 0 and verbose_logging:
		print("PeopleManager: Culled %d overflow people, %d remaining" % [culled, all_people.size()])


func _do_spawn_person(surface: SpawnSurface) -> Person:
	if not spritesheet or spritesheet.get_frame_count() == 0:
		return null
	
	if not is_instance_valid(surface):
		return null
	
	var person = _acquire_from_pool()
	
	# Per-spawn configuration
	person.bob_rate = bob_rate_base + randf_range(-bob_rate_variance, bob_rate_variance)
	person.walk_speed = randf_range(walk_speed_min, walk_speed_max)
	
	# Material (cached by color)
	# Resolve color set index (handles -1 = random, cached per surface)
	var resolved_set_index = _resolve_color_set_index(surface)
	
	# Pick sprite first (needed for material cache key)
	var sprite_index = randi() % spritesheet.get_frame_count()
	var sprite_tex = spritesheet.get_frame(sprite_index)
	
	# Get color for this surface
	var color = get_color_from_set(surface.color_set_index, spawn_counter)
	spawn_counter += 1
	
	# Get cached material (shared with others using same color+sprite)
	var mat = _get_cached_material(color, sprite_tex)
	person.set_shared_material(mat)

	# Also set pixel LOD material (quantized color for better batching)
	var pixel_mat = _get_pixel_material(color)
	person.set_pixel_material(pixel_mat)
	
	# Set sprite (texture already in material, but Sprite3D needs it too)
	person.set_sprite(sprite_tex, sprite_index)
	
	# Position and bounds
	var bounds = surface.get_bounds_world()
	person.set_bounds(bounds.min, bounds.max)
	person.global_position = surface.get_random_spawn_position()
	
	# Track
	surface.add_person(person)
	all_people.append(person)
	
	return person


func _do_spawn_group(surface: SpawnSurface, group_size: int):
	var available = surface.max_people - surface.get_people_count()
	if available < group_size:
		var person = _do_spawn_person(surface)
		if person:
			_assign_destination(person, surface)
		return
	
	var group_id = next_group_id
	next_group_id += 1
	
	var base_pos = surface.get_random_spawn_position()
	var group_members: Array[Person] = []
	
	for i in range(group_size):
		var person = _do_spawn_person(surface)
		if not person:
			continue
		
		person.group_id = group_id
		var offset = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		person.global_position = base_pos + offset
		group_members.append(person)
	
	if group_members.is_empty():
		return
	
	var destination = _find_valid_destination(group_members[0], surface)
	if not destination:
		for person in group_members:
			person.group_id = -1
		return
	
	var is_hurry = randf() < in_a_hurry_chance
	for person in group_members:
		person.set_destination(destination)
		if is_hurry:
			person.in_a_hurry = true
			person.hurry_timer = hurry_time


func _get_cached_material(color: Color, sprite_tex: AtlasTexture) -> ShaderMaterial:
	# Create cache key from color and texture
	var color_key = "%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	var tex_id = sprite_tex.get_instance_id()
	var cache_key = "%s_%d" % [color_key, tex_id]
	
	# Return cached material if exists
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	
	# Create new material
	var mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("color_add", Vector3(color.r, color.g, color.b))
	mat.set_shader_parameter("texture_albedo", sprite_tex)
	
	# Cache and return
	_material_cache[cache_key] = mat
	return mat


func _update_process_states():
	# Find camera
	if not _camera or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	
	if not _camera:
		return
	
	var camera_pos = _camera.global_position
	var dist_sq = process_distance * process_distance
	
	for person in all_people:
		if not is_instance_valid(person):
			continue
		
		# Always process certain states
		if person.current_state in [Person.State.BOARDING, Person.State.RIDING, Person.State.EXITING]:
			person.set_process(true)
			continue
		
		# Distance check
		var dx = person.global_position.x - camera_pos.x
		var dz = person.global_position.z - camera_pos.z
		var person_dist_sq = dx * dx + dz * dz
		
		person.set_process(person_dist_sq <= dist_sq)


func _assign_destination(person: Person, source_surface: SpawnSurface):
	var target = _find_valid_destination(person, source_surface)
	if not target:
		return
	
	person.set_destination(target)
	
	if randf() < in_a_hurry_chance:
		person.in_a_hurry = true
		person.hurry_timer = hurry_time


func _find_valid_destination(person: Person, _source_surface: SpawnSurface) -> Node:
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


# === PUBLIC API ===

func set_player_position(pos: Vector3):
	# Call this from FCar._process() to enable proximity-based spawning
	_player_position = pos
	_has_player_position = true


func spawn_person_on_surface(surface: SpawnSurface) -> Person:
	return _do_spawn_person(surface)


func spawn_person_at(position: Vector3, bounds_min: Vector3 = Vector3.ZERO, bounds_max: Vector3 = Vector3.ZERO) -> Person:
	if not spritesheet or spritesheet.get_frame_count() == 0:
		return null
	
	var person = _acquire_from_pool()
	
	person.bob_rate = bob_rate_base + randf_range(-bob_rate_variance, bob_rate_variance)
	person.walk_speed = randf_range(walk_speed_min, walk_speed_max)
	
	# Pick random sprite
	var sprite_index = randi() % spritesheet.get_frame_count()
	var sprite_tex = spritesheet.get_frame(sprite_index)
	
	# Use black tint for manually spawned (or pass color as parameter)
	var color = Color.BLACK
	var mat = _get_cached_material(color, sprite_tex)
	person.set_shared_material(mat)
	person.set_pixel_material(_get_pixel_material(color))
	person.set_sprite(sprite_tex, sprite_index)
	
	if bounds_min != Vector3.ZERO or bounds_max != Vector3.ZERO:
		person.set_bounds(bounds_min, bounds_max)
	
	person.global_position = position
	all_people.append(person)
	
	return person


func remove_person(person: Person):
	_return_to_pool(person)


func remove_all_people():
	for person in all_people.duplicate():  # Duplicate to avoid modifying while iterating
		_return_to_pool(person)
	all_people.clear()
	_surface_color_cache.clear()  # Reset random color assignments


func get_people_count() -> int:
	all_people = all_people.filter(func(p): return is_instance_valid(p))
	return all_people.size()


func register_surface(surface: SpawnSurface):
	if surface not in registered_surfaces:
		registered_surfaces.append(surface)


func unregister_surface(surface: SpawnSurface):
	registered_surfaces.erase(surface)
	# Clean up color cache for this surface
	if is_instance_valid(surface):
		_surface_color_cache.erase(surface.get_instance_id())


func register_poi(poi: PointOfInterest):
	if poi not in registered_pois:
		registered_pois.append(poi)


func unregister_poi(poi: PointOfInterest):
	registered_pois.erase(poi)


func get_enabled_pois() -> Array[PointOfInterest]:
	var enabled: Array[PointOfInterest] = []
	for poi in registered_pois:
		if is_instance_valid(poi) and poi.enabled:
			enabled.append(poi)
	return enabled


func get_nearest_surface(pos: Vector3) -> SpawnSurface:
	var nearest: SpawnSurface = null
	var nearest_dist: float = INF
	
	for surface in registered_surfaces:
		if not is_instance_valid(surface) or not surface.enabled:
			continue
		var dist = pos.distance_to(surface.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = surface
	
	return nearest


# === COLOR SETS ===

func _load_color_sets():
	color_sets.clear()
	
	var dir = DirAccess.open(color_sets_folder)
	if not dir:
		color_sets.append(PackedColorArray([Color.BLACK]))
		return
	
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".txt"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	files.sort()
	
	for fname in files:
		var colors = _parse_color_file(color_sets_folder + "/" + fname)
		if colors.size() > 0:
			color_sets.append(colors)
	
	if color_sets.is_empty():
		color_sets.append(PackedColorArray([Color.BLACK]))
	
	print("PeopleManager: Loaded %d color sets" % color_sets.size())


func _parse_color_file(path: String) -> PackedColorArray:
	var colors = PackedColorArray()
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return colors
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var color = _parse_color_line(line)
		if color != null:
			colors.append(color)
	
	return colors


func _parse_color_line(line: String) -> Variant:
	if line.begins_with("#"):
		line = line.substr(1)
	
	if line.length() == 6 and line.is_valid_hex_number():
		var hex = line.hex_to_int()
		return Color(
			((hex >> 16) & 0xFF) / 255.0,
			((hex >> 8) & 0xFF) / 255.0,
			(hex & 0xFF) / 255.0
		)
	
	var parts = line.split(",")
	if parts.size() >= 3:
		var r = parts[0].strip_edges().to_float()
		var g = parts[1].strip_edges().to_float()
		var b = parts[2].strip_edges().to_float()
		if r > 1.0 or g > 1.0 or b > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
		return Color(r, g, b)
	
	return null


func _get_color_set(index: int) -> PackedColorArray:
	if color_sets.is_empty():
		return PackedColorArray([Color.BLACK])
	
	# -1 means pick a random color set (caller should use _resolve_color_set_index for surfaces)
	if index < 0:
		index = randi() % color_sets.size()
	
	if index >= color_sets.size():
		return color_sets[0]
	
	return color_sets[index]


# Cache for resolved random color set indices (surface instance_id -> resolved index)
var _surface_color_cache: Dictionary = {}

func _resolve_color_set_index(surface: SpawnSurface) -> int:
	# Returns the color set index for this surface
	# If surface.color_set_index is -1, picks a random set and caches it
	var set_index = surface.color_set_index
	
	if set_index >= 0:
		return set_index
	
	# Random mode: check cache first
	var surface_id = surface.get_instance_id()
	if _surface_color_cache.has(surface_id):
		return _surface_color_cache[surface_id]
	
	# Pick random and cache
	var random_index = randi() % max(color_sets.size(), 1)
	_surface_color_cache[surface_id] = random_index
	return random_index


func get_color_from_set(set_index: int, person_index: int) -> Color:
	var colors = _get_color_set(set_index)
	if colors.size() == 0:
		return Color.BLACK
	return colors[person_index % colors.size()]


# === SPRITESHEET ===

func _load_spritesheet():
	spritesheet = SpriteSheet.new()
	if spritesheet.load_horizontal(spritesheet_path, sprite_width, sprite_height, sprite_count):
		print("PeopleManager: Loaded %d person sprites" % spritesheet.get_frame_count())
	else:
		push_warning("PeopleManager: Failed to load spritesheet")


func reload_sprites():
	_material_cache.clear()
	if spritesheet and spritesheet.reload():
		for person in all_people:
			if is_instance_valid(person):
				var tex = spritesheet.get_frame(person.sprite_index)
				if tex:
					person.refresh_sprite(tex)


# === PIXEL LOD ===

func _create_pixel_texture():
	# Create a 1x1 white texture for pixel LOD sprites
	var img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_pixel_texture = ImageTexture.create_from_image(img)


func _quantize_color(color: Color) -> Color:
	# Quantize color to reduce unique materials for better batching
	# With 4 levels per channel: 0, 0.33, 0.66, 1.0
	var step = 1.0 / (PIXEL_LOD_COLOR_LEVELS - 1)
	var r = round(color.r / step) * step
	var g = round(color.g / step) * step
	var b = round(color.b / step) * step
	return Color(r, g, b)


func _get_pixel_material(color: Color) -> ShaderMaterial:
	# Get or create a pixel LOD material for this (quantized) color
	var quantized = _quantize_color(color)
	var key = "%02x%02x%02x" % [int(quantized.r * 255), int(quantized.g * 255), int(quantized.b * 255)]

	if _pixel_material_cache.has(key):
		return _pixel_material_cache[key]

	# Create new pixel material
	var mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("color_add", Vector3(quantized.r, quantized.g, quantized.b))
	mat.set_shader_parameter("texture_albedo", _pixel_texture)

	_pixel_material_cache[key] = mat
	return mat


# === DEBUG ===

func print_status():
	print("PeopleManager Status:")
	print("  Pool: %d available, %d active" % [_pool.size(), all_people.size()])
	print("  Spawn queue: %d pending" % _spawn_queue.size())
	print("  Materials cached: %d (close) + %d (pixel)" % [_material_cache.size(), _pixel_material_cache.size()])
	print("  Surfaces: %d registered" % registered_surfaces.size())
