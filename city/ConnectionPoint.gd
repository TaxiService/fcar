# ConnectionPoint.gd - Connection point for modular buildings
# Uses bitmask flags for flexible type/size matching
#
# Direction convention: The marker's -Z axis points INWARD (into the block).
@tool
class_name ConnectionPoint
extends Marker3D

# === CONNECTION TYPE FLAGS ===
# Multiple types can be enabled - connection matches if ANY type overlaps
enum TypeFlags {
	SEED = 1,        # Root attachment to crosslinks
	STRUCTURAL = 2,  # Vertical stacking (up/down)
	JUNCTION = 4,    # Horizontal branching (sideways)
	CAP = 8,         # Terminal pieces (ends branches)
}

# Checkboxes in editor: ☐ Seed ☑ Structural ☐ Junction ☐ Cap
@export_flags("Seed", "Structural", "Junction", "Cap") var type_flags: int = TypeFlags.STRUCTURAL:
	set(v):
		type_flags = v
		_update_visual()

# === CONNECTION SIZE FLAGS ===
# Multiple sizes can be enabled - connection matches if ANY size overlaps
enum SizeFlags {
	SMALL = 1,
	MEDIUM = 2,
	LARGE = 4,
}

# Checkboxes in editor: ☐ Small ☑ Medium ☐ Large
@export_flags("Small", "Medium", "Large") var size_flags: int = SizeFlags.MEDIUM:
	set(v):
		size_flags = v
		_update_visual()

# === PLUG/SOCKET ===
@export_category("Behavior")
@export var is_plug: bool = true      # Can be used as anchor point
@export var is_socket: bool = true    # Can spawn children

# === ROTATION MODE ===
enum RotationMode {
	FREE,      # Any Y rotation
	CARDINAL,  # 0°, 90°, 180°, 270° only
	FIXED,     # No rotation allowed
}

@export var rotation_mode: RotationMode = RotationMode.FREE

# === COLLISION ===
@export var ignores_collision: bool = false

# === DEBUG VISUAL ===
@export_category("Debug")
@export var visual_size: float = 3.0:
	set(v):
		visual_size = v
		_update_visual()

var _visual_mesh: MeshInstance3D = null


func _enter_tree():
	if Engine.is_editor_hint():
		_create_visual()


func _exit_tree():
	if _visual_mesh and is_instance_valid(_visual_mesh):
		_visual_mesh.queue_free()
		_visual_mesh = null


# === PUBLIC API ===

# Get world-space direction this connection faces (outward)
func get_world_direction() -> Vector3:
	return -global_basis.z


# Check if this connection can connect to another
func can_connect_to(other: ConnectionPoint) -> bool:
	# One must be plug, other must be socket (or both have both)
	var plug_socket_ok = (is_plug and other.is_socket) or (is_socket and other.is_plug)
	if not plug_socket_ok:
		return false
	
	# Types must overlap
	if not types_overlap(other.type_flags):
		return false
	
	# Sizes must overlap
	if not sizes_overlap(other.size_flags):
		return false
	
	return true


# Check if type flags overlap (any bit in common)
func types_overlap(other_flags: int) -> bool:
	return (type_flags & other_flags) != 0


# Check if size flags overlap (any bit in common)
func sizes_overlap(other_flags: int) -> bool:
	return (size_flags & other_flags) != 0


# Check if this plug matches specific requirements from a seed/parent
func matches_requirements(required_types: int, required_sizes: int) -> bool:
	if not is_plug:
		return false
	if (type_flags & required_types) == 0:
		return false
	if (size_flags & required_sizes) == 0:
		return false
	return true


# Get allowed rotation angles based on rotation_mode
func get_allowed_rotations() -> Array[float]:
	match rotation_mode:
		RotationMode.FREE:
			return [0.0, PI/6, PI/3, PI/2, 2*PI/3, 5*PI/6, PI, 7*PI/6, 4*PI/3, 3*PI/2, 5*PI/3, 11*PI/6]
		RotationMode.CARDINAL:
			return [0.0, PI/2, PI, 3*PI/2]
		RotationMode.FIXED:
			return [0.0]
	return [0.0]


# === HELPER FUNCTIONS ===

# Check if a specific type flag is set
func has_type(type: TypeFlags) -> bool:
	return (type_flags & type) != 0

func has_seed() -> bool:
	return has_type(TypeFlags.SEED)

func has_structural() -> bool:
	return has_type(TypeFlags.STRUCTURAL)

func has_junction() -> bool:
	return has_type(TypeFlags.JUNCTION)

func has_cap() -> bool:
	return has_type(TypeFlags.CAP)


# Check if a specific size flag is set
func has_size(size: SizeFlags) -> bool:
	return (size_flags & size) != 0

func has_small() -> bool:
	return has_size(SizeFlags.SMALL)

func has_medium() -> bool:
	return has_size(SizeFlags.MEDIUM)

func has_large() -> bool:
	return has_size(SizeFlags.LARGE)


# Get human-readable description of this connection
func get_description() -> String:
	var types: Array[String] = []
	if has_seed(): types.append("Seed")
	if has_structural(): types.append("Struct")
	if has_junction(): types.append("Junct")
	if has_cap(): types.append("Cap")
	
	var sizes: Array[String] = []
	if has_small(): sizes.append("S")
	if has_medium(): sizes.append("M")
	if has_large(): sizes.append("L")
	
	var role = ""
	if is_plug and is_socket:
		role = "plug+socket"
	elif is_plug:
		role = "plug"
	elif is_socket:
		role = "socket"
	else:
		role = "none"
	
	return "%s [%s] (%s)" % ["+".join(types), "+".join(sizes), role]


# === EDITOR VISUALS ===

func _create_visual():
	if _visual_mesh and is_instance_valid(_visual_mesh):
		_visual_mesh.queue_free()
	
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "_DebugVisual"
	
	# Shape based on type count (more types = more complex shape)
	var type_count = 0
	if has_seed(): type_count += 1
	if has_structural(): type_count += 1
	if has_junction(): type_count += 1
	if has_cap(): type_count += 1
	
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = visual_size * 0.4
	cone.height = visual_size
	cone.radial_segments = 4 + type_count * 2  # More sides = more types
	_visual_mesh.mesh = cone
	
	# Point in -Z direction
	_visual_mesh.rotation.x = -PI / 2
	_visual_mesh.position.z = -(visual_size*2) + (visual_size/0.5)
	
	# Material - color encodes primary type, brightness encodes size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_visual_color()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual_mesh.material_override = mat
	
	add_child(_visual_mesh)
	_visual_mesh.owner = null


func _update_visual():
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_create_visual()


func _get_visual_color() -> Color:
	# Primary color based on highest-priority type
	var base_color: Color
	if has_seed():
		base_color = Color(1.0, 0.8, 0.0)  # Gold
	elif has_structural():
		base_color = Color(0.2, 0.6, 1.0)  # Blue
	elif has_junction():
		base_color = Color(0.2, 1.0, 0.4)  # Green
	elif has_cap():
		base_color = Color(1.0, 0.3, 0.3)  # Red
	else:
		base_color = Color(0.5, 0.5, 0.5)  # Gray (no type??)
	
	# Mix in secondary types
	var type_count = 0
	if has_seed(): type_count += 1
	if has_structural(): type_count += 1
	if has_junction(): type_count += 1
	if has_cap(): type_count += 1
	
	if type_count > 1:
		# Multiple types: shift toward white/cyan to indicate flexibility
		base_color = base_color.lerp(Color(0.7, 0.9, 1.0), 0.3)
	
	# Brightness based on size flags
	var size_count = 0
	if has_small(): size_count += 1
	if has_medium(): size_count += 1
	if has_large(): size_count += 1
	
	if has_large():
		base_color = base_color.lightened(0.2)
	elif has_small() and not has_medium():
		base_color = base_color.darkened(0.2)
	
	if size_count > 1:
		# Multiple sizes: add slight saturation to indicate flexibility
		base_color.s = min(1.0, base_color.s + 0.2)
	
	base_color.a = 0.7
	return base_color
