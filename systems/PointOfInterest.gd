@tool
class_name PointOfInterest
extends Node3D

# Configuration
@export var poi_name: String = "Unnamed Location":
	set(value):
		poi_name = value
		_update_editor_visual()

@export var arrival_radius: float = 5.0:
	set(value):
		arrival_radius = value
		_update_editor_visual()

@export var poi_type: String = "generic"  # For future categorization (shop, landmark, etc.)

@export var enabled: bool = true:
	set(value):
		enabled = value
		_update_editor_visual()

# Editor visualization
var _editor_mesh: MeshInstance3D
var _editor_label: Label3D

# Runtime state
var registered: bool = false


func _ready():
	if Engine.is_editor_hint():
		_create_editor_visual()
	else:
		# Remove editor visuals at runtime
		if _editor_mesh:
			_editor_mesh.queue_free()
			_editor_mesh = null
		if _editor_label:
			_editor_label.queue_free()
			_editor_label = null
		# Register with PeopleManager
		_register_with_manager()


func _create_editor_visual():
	# Create cylinder mesh to show arrival radius
	if not _editor_mesh:
		_editor_mesh = MeshInstance3D.new()
		add_child(_editor_mesh)

		var cylinder = CylinderMesh.new()
		_editor_mesh.mesh = cylinder

		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_editor_mesh.material_override = mat

	# Create label to show POI name
	if not _editor_label:
		_editor_label = Label3D.new()
		_editor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_editor_label.no_depth_test = true
		_editor_label.fixed_size = true
		_editor_label.pixel_size = 0.01
		add_child(_editor_label)

	_update_editor_visual()


func _update_editor_visual():
	if not Engine.is_editor_hint():
		return

	# Update mesh size
	if _editor_mesh and _editor_mesh.mesh is CylinderMesh:
		var cylinder = _editor_mesh.mesh as CylinderMesh
		cylinder.top_radius = arrival_radius
		cylinder.bottom_radius = arrival_radius
		cylinder.height = 0.2

	# Update color based on enabled state
	if _editor_mesh:
		var mat = _editor_mesh.material_override as StandardMaterial3D
		if mat:
			if enabled:
				mat.albedo_color = Color(0.8, 0.6, 0.2, 0.3)  # Orange/gold when enabled
			else:
				mat.albedo_color = Color(0.4, 0.4, 0.4, 0.3)  # Gray when disabled

	# Update label
	if _editor_label:
		_editor_label.text = poi_name
		_editor_label.position = Vector3(0, 2.0, 0)  # Float above the marker


func _register_with_manager():
	if registered:
		return

	# Deferred registration to ensure PeopleManager is ready
	var manager = _find_people_manager()
	if manager and manager.has_method("register_poi"):
		manager.register_poi(self)
		registered = true


func _find_people_manager() -> Node:
	# Look for PeopleManager in the scene
	if has_node("/root/PeopleManager"):
		return get_node("/root/PeopleManager")

	# Search up the tree
	var node = get_parent()
	while node:
		if node.has_method("register_poi"):
			return node
		for child in node.get_children():
			if child.has_method("register_poi"):
				return child
		node = node.get_parent()

	# Search from root
	return _find_in_tree(get_tree().root)


func _find_in_tree(node: Node) -> Node:
	if node.has_method("register_poi"):
		return node
	for child in node.get_children():
		var found = _find_in_tree(child)
		if found:
			return found
	return null


func is_within_radius(pos: Vector3) -> bool:
	var dist = global_position.distance_to(pos)
	return dist <= arrival_radius


# Debug visualization in editor
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not enabled:
		warnings.append("PointOfInterest is disabled")
	if poi_name == "Unnamed Location":
		warnings.append("Consider giving this POI a descriptive name")
	return warnings
