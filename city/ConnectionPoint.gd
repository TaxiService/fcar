# ConnectionPoint.gd - Visual connection point for modular buildings
# Attach to Marker3D nodes. Shows direction cone in editor.
# The marker's -Z axis is the connection direction (outward).
@tool
class_name ConnectionPoint
extends Marker3D

@export var size_small: bool = false   # Can connect to small points
@export var size_medium: bool = true   # Can connect to medium points
@export var size_large: bool = false   # Can connect to large points

@export_category("Debug")
@export var cone_length: float = 3.0   # Visual cone size
@export var cone_color: Color = Color(0.2, 0.8, 1.0, 0.8)  # Cyan default

var _cone_mesh: MeshInstance3D = null


func _ready():
	_create_debug_cone()


func _process(_delta):
	# Update cone in editor when properties change
	if Engine.is_editor_hint():
		_update_cone()


func _create_debug_cone():
	# Remove old cone if exists
	if _cone_mesh:
		_cone_mesh.queue_free()

	_cone_mesh = MeshInstance3D.new()
	_cone_mesh.name = "_DebugCone"

	# Create cone mesh pointing in -Z direction
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = cone_length * 0.3
	cone.height = cone_length
	cone.radial_segments = 6
	_cone_mesh.mesh = cone

	# Rotate so cone points in -Z (the connection direction)
	_cone_mesh.rotation.x = -PI / 2
	_cone_mesh.position.z = -cone_length / 2

	# Material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = cone_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mesh.material_override = mat

	# Don't save the debug mesh with the scene
	_cone_mesh.set_meta("_edit_lock_", true)

	add_child(_cone_mesh, false, Node.INTERNAL_MODE_BACK)


func _update_cone():
	if not _cone_mesh:
		_create_debug_cone()
		return

	# Update size
	var cone = _cone_mesh.mesh as CylinderMesh
	if cone:
		cone.height = cone_length
		cone.bottom_radius = cone_length * 0.3
		_cone_mesh.position.z = -cone_length / 2

	# Update color based on sizes enabled
	var mat = _cone_mesh.material_override as StandardMaterial3D
	if mat:
		# Color code: more sizes = brighter
		var enabled_count = int(size_small) + int(size_medium) + int(size_large)
		match enabled_count:
			1: mat.albedo_color = Color(0.2, 0.6, 1.0, 0.7)   # Blue - single
			2: mat.albedo_color = Color(0.2, 1.0, 0.6, 0.7)   # Green - dual
			3: mat.albedo_color = Color(1.0, 1.0, 0.2, 0.7)   # Yellow - all
			_: mat.albedo_color = Color(1.0, 0.2, 0.2, 0.7)   # Red - none!


# Check if this point can connect to another
func can_connect_to(other: ConnectionPoint) -> bool:
	# At least one size must match
	if size_small and other.size_small:
		return true
	if size_medium and other.size_medium:
		return true
	if size_large and other.size_large:
		return true
	return false


# Check if directions are compatible (facing each other)
func directions_compatible(other: ConnectionPoint) -> bool:
	var my_dir = -global_basis.z.normalized()
	var other_dir = -other.global_basis.z.normalized()
	return my_dir.dot(other_dir) < -0.9  # Nearly opposite


# Full compatibility check
func is_compatible_with(other: ConnectionPoint) -> bool:
	return can_connect_to(other) and directions_compatible(other)


# Get the world-space direction this point faces
func get_world_direction() -> Vector3:
	return -global_basis.z.normalized()
