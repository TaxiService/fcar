class_name PeopleManager
extends Node

# Spritesheet configuration
@export var spritesheet_path: String = "res://people4.png"
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

# Runtime state
var spritesheet: SpriteSheet
var registered_surfaces: Array[SpawnSurface] = []
var all_people: Array[Person] = []
var spawn_timer: float = 0.0


func _ready():
	_load_spritesheet()


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
		print("PeopleManager: Registered spawn surface")


func unregister_surface(surface: SpawnSurface):
	registered_surfaces.erase(surface)


func _try_spawn_on_surfaces():
	for surface in registered_surfaces:
		if surface.can_spawn_more():
			spawn_person_on_surface(surface)


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

	# Set random sprite
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
	for surface in registered_surfaces:
		print("    Surface enabled=", surface.enabled, " people=", surface.get_people_count(), "/", surface.max_people)
