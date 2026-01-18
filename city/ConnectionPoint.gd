# ConnectionPoint.gd - Visual connection point for modular buildings
# Shows a colored cone in editor. Colors: Red=Small, Green=Medium, Blue=Large
#
# Direction convention: Cone points INWARD (into the block).
# When two blocks connect, their connection points meet at the interface,
# with cones pointing into their respective blocks (opposite directions).
@tool
class_name ConnectionPoint
extends Marker3D

@export var size_small: bool = false:   # Can connect to small points
	set(v):
		size_small = v
		_update_cone()

@export var size_medium: bool = true:   # Can connect to medium points
	set(v):
		size_medium = v
		_update_cone()

@export var size_large: bool = false:   # Can connect to large points
	set(v):
		size_large = v
		_update_cone()

@export_category("Connection Behavior")
@export var is_plug: bool = true      # Can be used as anchor (other blocks connect TO this)
@export var is_socket: bool = true    # Can branch children (this spawns other blocks)
@export var ignores_collision: bool = false  # Bypasses AABB overlap check during generation

@export_category("Debug")
@export var cone_length: float = 3.0:   # Visual cone size
	set(v):
		cone_length = v
		_update_cone()

var _cone_mesh: MeshInstance3D = null


func _enter_tree():
	if Engine.is_editor_hint():
		_create_debug_cone()


func _exit_tree():
	if _cone_mesh and is_instance_valid(_cone_mesh):
		_cone_mesh.queue_free()
		_cone_mesh = null


func _create_debug_cone():
	# Remove old cone if exists
	if _cone_mesh and is_instance_valid(_cone_mesh):
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
	_cone_mesh.position.z = -(cone_length*2) + (cone_length/0.5)

	# Material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_size_color()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mesh.material_override = mat

	add_child(_cone_mesh)
	# Prevent saving the debug cone with the scene
	_cone_mesh.owner = null


func _update_cone():
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	if not _cone_mesh or not is_instance_valid(_cone_mesh):
		_create_debug_cone()
		return

	# Update size
	var cone = _cone_mesh.mesh as CylinderMesh
	if cone:
		cone.height = cone_length
		cone.bottom_radius = cone_length * 0.3
		_cone_mesh.position.z = -(cone_length*2) + (cone_length/0.5)

	# Update color based on sizes enabled
	var mat = _cone_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = _get_size_color()


func _get_size_color() -> Color:
	# RGB = Small/Medium/Large
	# Red = small, Green = medium, Blue = large
	# Combos blend naturally: S+M = yellow, M+L = cyan, S+L = magenta, all = white
	var r = 1.0 if size_small else 0.0
	var g = 1.0 if size_medium else 0.0
	var b = 1.0 if size_large else 0.0

	# If nothing enabled, dark red warning
	#if not size_small and not size_medium and not size_large:
	#	return Color(0.3, 0.0, 0.0, 0.9)

	return Color(r, g, b, 0.85)


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
	var my_dir = -global_basis.x.normalized()
	var other_dir = -other.global_basis.x.normalized()
	return my_dir.dot(other_dir) < -0.9  # Nearly opposite


# Full compatibility check
func is_compatible_with(other: ConnectionPoint) -> bool:
	return can_connect_to(other) and directions_compatible(other)


# Get the world-space direction this point faces
func get_world_direction() -> Vector3:
	return -global_basis.z.normalized()
