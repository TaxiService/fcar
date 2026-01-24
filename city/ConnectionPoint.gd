# ConnectionPoint.gd - Connection point for modular buildings
# Defines how blocks can connect to each other using type + size matching
#
# Direction convention: The marker's -Z axis points INWARD (into the block).
# When two blocks connect, their connection points meet at the interface,
# with markers pointing into their respective blocks (opposite directions).
@tool
class_name ConnectionPoint
extends Marker3D

# === CONNECTION TYPE ===
# Determines what KIND of connection this is (must match for connection)
enum ConnectionType {
	SEED,        # For attaching to crosslink/edge seeds (root of building)
	STRUCTURAL,  # Vertical stacking (up/down growth)
	JUNCTION,    # Horizontal branching (sideways growth)
	CAP,         # Terminal pieces (ends branches, spawns nothing)
}

@export var connection_type: ConnectionType = ConnectionType.STRUCTURAL:
	set(v):
		connection_type = v
		_update_visual()

# === CONNECTION SIZE ===
# Must match for connection (large↔large, etc.)
enum ConnectionSize {
	LARGE,
	MEDIUM,
	SMALL,
}

@export var connection_size: ConnectionSize = ConnectionSize.MEDIUM:
	set(v):
		connection_size = v
		_update_visual()

# === PLUG/SOCKET ===
# Plug: can be used as anchor (other blocks connect TO this)
# Socket: can spawn children (this block spawns others FROM here)
@export_category("Behavior")
@export var is_plug: bool = true
@export var is_socket: bool = true

# === ROTATION MODE ===
# Controls how the connecting block can be rotated
enum RotationMode {
	FREE,      # Any Y rotation allowed
	CARDINAL,  # Only 0°, 90°, 180°, 270°
	FIXED,     # No rotation - must match exactly
}

@export var rotation_mode: RotationMode = RotationMode.FREE

# === COLLISION ===
@export var ignores_collision: bool = false  # Bypass AABB overlap check

# === DEBUG VISUAL ===
@export_category("Debug")
@export var visual_size: float = 3.0:
	set(v):
		visual_size = v
		_update_visual()

@export var show_direction_arrow: bool = true:
	set(v):
		show_direction_arrow = v
		_update_visual()

var _visual_mesh: MeshInstance3D = null
var _arrow_mesh: MeshInstance3D = null


func _enter_tree():
	if Engine.is_editor_hint():
		_create_visual()


func _exit_tree():
	if _visual_mesh and is_instance_valid(_visual_mesh):
		_visual_mesh.queue_free()
		_visual_mesh = null
	if _arrow_mesh and is_instance_valid(_arrow_mesh):
		_arrow_mesh.queue_free()
		_arrow_mesh = null


# === PUBLIC API ===

# Get the world-space direction this connection faces (outward from block)
func get_world_direction() -> Vector3:
	return -global_basis.z  # -Z is the "inward" direction, so we return it as outward


# Check if this connection can connect to another
func can_connect_to(other: ConnectionPoint) -> bool:
	# One must be plug, one must be socket
	if not (is_plug or other.is_plug):
		return false
	if not (is_socket or other.is_socket):
		return false
	
	# Type must match (with CAP special case)
	if not _types_compatible(connection_type, other.connection_type):
		return false
	
	# Size must match
	if connection_size != other.connection_size:
		return false
	
	return true


# Check if this connection matches a seed's requirements
func matches_seed_type(seed_type: ConnectionType, seed_size: ConnectionSize) -> bool:
	if not is_plug:
		return false
	if connection_type != seed_type:
		return false
	if connection_size != seed_size:
		return false
	return true


# Get allowed rotation angles based on rotation_mode
func get_allowed_rotations() -> Array[float]:
	match rotation_mode:
		RotationMode.FREE:
			# Return a sampling of rotations (could be made continuous)
			return [0.0, PI/6, PI/3, PI/2, 2*PI/3, 5*PI/6, PI, 7*PI/6, 4*PI/3, 3*PI/2, 5*PI/3, 11*PI/6]
		RotationMode.CARDINAL:
			return [0.0, PI/2, PI, 3*PI/2]
		RotationMode.FIXED:
			return [0.0]
	return [0.0]


# === INTERNAL ===

func _types_compatible(type_a: ConnectionType, type_b: ConnectionType) -> bool:
	# Same type always compatible
	if type_a == type_b:
		return true
	
	# CAP can connect to anything (it's a universal terminator)
	if type_a == ConnectionType.CAP or type_b == ConnectionType.CAP:
		return true
	
	return false


# === EDITOR VISUALS ===

func _create_visual():
	_clear_visuals()
	
	# Main shape - cone pointing inward (-Z)
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "_DebugVisual"
	
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = visual_size * 0.4
	cone.height = visual_size
	cone.radial_segments = _get_visual_segments()
	_visual_mesh.mesh = cone
	
	# Rotate so cone points in -Z direction
	_visual_mesh.rotation.x = -PI / 2
	_visual_mesh.position.z = -(visual_size*2) + (visual_size/0.5)
	
	# Material based on type and size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_visual_color()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual_mesh.material_override = mat
	
	add_child(_visual_mesh)
	_visual_mesh.owner = null
	
	# Direction arrow (small cylinder showing -Z)
	if show_direction_arrow:
		_arrow_mesh = MeshInstance3D.new()
		_arrow_mesh.name = "_DirectionArrow"
		
		var arrow = CylinderMesh.new()
		arrow.top_radius = visual_size * 0.1
		arrow.bottom_radius = visual_size * 0.1
		arrow.height = visual_size * 1.5
		arrow.radial_segments = 4
		_arrow_mesh.mesh = arrow
		
		_arrow_mesh.rotation.x = -PI / 2
		_arrow_mesh.position.z = (visual_size*2) - (visual_size)
		
		var arrow_mat = StandardMaterial3D.new()
		arrow_mat.albedo_color = Color(1, 1, 1, 0.3)
		arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arrow_mesh.material_override = arrow_mat
		
		add_child(_arrow_mesh)
		_arrow_mesh.owner = null


func _clear_visuals():
	if _visual_mesh and is_instance_valid(_visual_mesh):
		_visual_mesh.queue_free()
		_visual_mesh = null
	if _arrow_mesh and is_instance_valid(_arrow_mesh):
		_arrow_mesh.queue_free()
		_arrow_mesh = null


func _update_visual():
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	_create_visual()  # Recreate with new settings


func _get_visual_color() -> Color:
	# Color encodes both type and size
	# Type = hue, Size = saturation/brightness
	
	var base_color: Color
	match connection_type:
		ConnectionType.SEED:
			base_color = Color(1.0, 0.8, 0.0)  # Gold/yellow
		ConnectionType.STRUCTURAL:
			base_color = Color(0.2, 0.6, 1.0)  # Blue
		ConnectionType.JUNCTION:
			base_color = Color(0.2, 1.0, 0.4)  # Green
		ConnectionType.CAP:
			base_color = Color(1.0, 0.3, 0.3)  # Red
	
	# Size affects brightness
	match connection_size:
		ConnectionSize.LARGE:
			base_color = base_color.lightened(0.2)
		ConnectionSize.MEDIUM:
			pass  # Keep as-is
		ConnectionSize.SMALL:
			base_color = base_color.darkened(0.3)
	
	base_color.a = 0.7
	return base_color


func _get_visual_segments() -> int:
	# More segments = rounder = larger visual distinction
	match connection_size:
		ConnectionSize.LARGE:
			return 8
		ConnectionSize.MEDIUM:
			return 6
		ConnectionSize.SMALL:
			return 4
	return 6
