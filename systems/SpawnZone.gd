@tool
class_name SpawnZone
extends Node3D

# Configuration
@export var enabled: bool = true:
	set(value):
		enabled = value
		_update_editor_visual()

@export var radius: float = 8.0:
	set(value):
		radius = max(1.0, value)
		_update_editor_visual()

@export var max_people: int = 5
@export var spawn_height_offset: float = 0.01
@export var color_set_index: int = -1  # -1 = random from PeopleManager

# Editor visualization
var _editor_mesh: MeshInstance3D

# Runtime state
var spawned_people: Array[Person] = []
var registered: bool = false


func _ready():
	if Engine.is_editor_hint():
		_create_editor_visual()
	else:
		if _editor_mesh:
			_editor_mesh.queue_free()
			_editor_mesh = null
		_register_with_manager()


func _create_editor_visual():
	if _editor_mesh:
		return

	_editor_mesh = MeshInstance3D.new()
	add_child(_editor_mesh)

	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.1
	_editor_mesh.mesh = cylinder

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_editor_mesh.material_override = mat

	_update_editor_visual()


func _update_editor_visual():
	if not Engine.is_editor_hint() or not _editor_mesh:
		return

	var cylinder = _editor_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius

	var mat = _editor_mesh.material_override as StandardMaterial3D
	if mat:
		if enabled:
			mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
		else:
			mat.albedo_color = Color(0.8, 0.2, 0.2, 0.3)


func _register_with_manager():
	if registered:
		return
	if CityGrid.people_manager:
		CityGrid.people_manager.register_zone(self)
		registered = true
	else:
		push_warning("SpawnZone at %s: CityGrid.people_manager not set" % global_position)


func get_center() -> Vector3:
	return global_position


func get_radius() -> float:
	return radius


func get_random_spawn_position() -> Vector3:
	# Random point in circle using polar coordinates
	var angle = randf() * TAU
	var dist = sqrt(randf()) * radius  # sqrt for uniform distribution
	var local_pos = Vector3(
		cos(angle) * dist,
		spawn_height_offset,
		sin(angle) * dist
	)
	return global_position + local_pos


func can_spawn_more() -> bool:
	spawned_people = spawned_people.filter(func(p): return is_instance_valid(p))
	return enabled and spawned_people.size() < max_people


func add_person(person: Person):
	if person not in spawned_people:
		spawned_people.append(person)


func remove_person(person: Person):
	spawned_people.erase(person)


func get_people_count() -> int:
	spawned_people = spawned_people.filter(func(p): return is_instance_valid(p))
	return spawned_people.size()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not enabled:
		warnings.append("SpawnZone is disabled")
	return warnings
