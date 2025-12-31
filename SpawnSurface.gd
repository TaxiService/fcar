@tool
class_name SpawnSurface
extends Node3D

# Configuration
@export var enabled: bool = false:
	set(value):
		enabled = value
		_update_editor_visual()
@export var max_people: int = 5
@export var spawn_height_offset: float = 0.01  # Slightly above surface to avoid z-fighting
@export var color_set_index: int = 0  # Which color set from PeopleManager to use

# Bounds definition (local coordinates, centered on this node)
@export var bounds_size: Vector3 = Vector3(10, 0, 10):
	set(value):
		bounds_size = value
		_update_editor_visual()

# Editor visualization
var _editor_mesh: MeshInstance3D

# Runtime state
var spawned_people: Array[Person] = []
var registered: bool = false


func _ready():
	if Engine.is_editor_hint():
		_create_editor_visual()
	else:
		# Remove editor visual if it exists at runtime
		if _editor_mesh:
			_editor_mesh.queue_free()
			_editor_mesh = null
		# Register with PeopleManager if it exists
		_register_with_manager()


func _create_editor_visual():
	if _editor_mesh:
		return

	_editor_mesh = MeshInstance3D.new()
	add_child(_editor_mesh)

	# Create box mesh
	var box = BoxMesh.new()
	_editor_mesh.mesh = box

	# Create semi-transparent material
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_editor_mesh.material_override = mat

	_update_editor_visual()


func _update_editor_visual():
	if not Engine.is_editor_hint() or not _editor_mesh:
		return

	# Update mesh size
	var box = _editor_mesh.mesh as BoxMesh
	if box:
		box.size = Vector3(bounds_size.x, 0.1, bounds_size.z)

	# Update color based on enabled state
	var mat = _editor_mesh.material_override as StandardMaterial3D
	if mat:
		if enabled:
			mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)  # Green when enabled
		else:
			mat.albedo_color = Color(0.8, 0.2, 0.2, 0.3)  # Red when disabled


func _register_with_manager():
	# Deferred to ensure PeopleManager is ready
	if not registered:
		var manager = _find_people_manager()
		if manager:
			manager.register_surface(self)
			registered = true


func _find_people_manager() -> Node:
	# Look for PeopleManager in the scene
	# First check if it's an autoload
	if has_node("/root/PeopleManager"):
		return get_node("/root/PeopleManager")

	# Otherwise search up the tree
	var node = get_parent()
	while node:
		if node.has_method("register_surface"):
			return node
		# Check children of this node
		for child in node.get_children():
			if child.has_method("register_surface"):
				return child
		node = node.get_parent()

	# Search from root
	return _find_in_tree(get_tree().root)


func _find_in_tree(node: Node) -> Node:
	if node.has_method("register_surface"):
		return node
	for child in node.get_children():
		var found = _find_in_tree(child)
		if found:
			return found
	return null


func get_bounds_world() -> Dictionary:
	# Returns world-space min/max bounds
	var half_size = bounds_size / 2.0
	var center = global_position

	return {
		"min": Vector3(center.x - half_size.x, center.y, center.z - half_size.z),
		"max": Vector3(center.x + half_size.x, center.y, center.z + half_size.z)
	}


func get_random_spawn_position() -> Vector3:
	var bounds = get_bounds_world()
	return Vector3(
		randf_range(bounds.min.x, bounds.max.x),
		global_position.y + spawn_height_offset,
		randf_range(bounds.min.z, bounds.max.z)
	)


func can_spawn_more() -> bool:
	# Clean up any freed people
	spawned_people = spawned_people.filter(func(p): return is_instance_valid(p))
	return enabled and spawned_people.size() < max_people


func add_person(person: Person):
	spawned_people.append(person)


func remove_person(person: Person):
	spawned_people.erase(person)


func get_people_count() -> int:
	spawned_people = spawned_people.filter(func(p): return is_instance_valid(p))
	return spawned_people.size()


# Debug visualization in editor
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not enabled:
		warnings.append("SpawnSurface is disabled - set 'enabled' to true to spawn people")
	return warnings
