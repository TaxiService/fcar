# BuildingBlock.gd - Attach to root of each modular building block scene
# Connection points are defined as child ConnectionPoint nodes (Marker3D with script)
# Each ConnectionPoint has size flags and shows a visual cone in editor
class_name BuildingBlock
extends Node3D

enum BlockType {
	STRUCTURAL,  # Basic mass/volume blocks
	FLOOR,       # Has surface where people can spawn
	CAP,         # Decorative terminator (antenna, dome, etc.)
	JUNCTION,    # Allows branching/sideways connections
}

# Grid constants for alignment
const GRID_H: float = 30.0   # Horizontal grid (420m / 14 = 30m)
const GRID_V: float = 2.5    # Vertical grid (heightlock compatible)

# Block properties
@export var block_type: BlockType = BlockType.STRUCTURAL
@export var can_spawn_people: bool = false  # True for floors/platforms
@export var spawn_weight: float = 1.0  # Probability weight for random selection
@export var min_biome: int = 0  # Lowest biome this block can appear in (0 = bottom)
@export var max_biome: int = 3  # Highest biome this block can appear in (3 = top)

# Optional: limit what block types can connect here
@export var allowed_connections: Array[BlockType] = []  # Empty = allow all

# Visibility/LOD settings - applies to all MeshInstance3D children
@export_category("Visibility Range")
@export var use_visibility_range: bool = false  # Enable distance-based visibility
@export var visibility_range_begin: float = 0.0:  # Visible starting from this distance (usually 0)
	set(value):
		visibility_range_begin = value
		if use_visibility_range:
			_apply_visibility_range()

@export var visibility_range_end: float = 1000.0:  # Hidden beyond this distance
	set(value):
		visibility_range_end = value
		if use_visibility_range:
			_apply_visibility_range()

@export var visibility_fade_mode: int = 1:  # 0=Disabled (pop), 1=Self (smooth fade), 2=Dependencies
	set(value):
		visibility_fade_mode = value
		if use_visibility_range:
			_apply_visibility_range()


func _ready():
	# Apply visibility range on spawn if enabled
	if use_visibility_range:
		_apply_visibility_range()


func _apply_visibility_range():
	"""Apply visibility range settings to all MeshInstance3D children (recursive)."""
	_apply_visibility_to_node(self)


func _apply_visibility_to_node(node: Node):
	"""Recursively apply visibility settings to a node and its children."""
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		mesh_inst.visibility_range_begin = visibility_range_begin
		mesh_inst.visibility_range_end = visibility_range_end
		mesh_inst.visibility_range_fade_mode = visibility_fade_mode as GeometryInstance3D.VisibilityRangeFadeMode
	
	# Also apply to CollisionShape3D (optional - can disable for performance)
	# Note: Collision still works even when mesh is hidden, which may or may not be desired
	
	for child in node.get_children():
		_apply_visibility_to_node(child)


func set_visibility_range(begin: float, end: float, fade: int = 0):
	"""Convenience function to set visibility range at runtime."""
	visibility_range_begin = begin
	visibility_range_end = end
	visibility_fade_mode = fade
	use_visibility_range = true
	_apply_visibility_range()


func disable_visibility_range():
	"""Disable visibility range (show at all distances)."""
	use_visibility_range = false
	# Reset all meshes to no range limit
	_reset_visibility_range(self)


func _reset_visibility_range(node: Node):
	"""Reset visibility range on all meshes."""
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		mesh_inst.visibility_range_begin = 0.0
		mesh_inst.visibility_range_end = 0.0  # 0 = no limit
		mesh_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	
	for child in node.get_children():
		_reset_visibility_range(child)


# Get all ConnectionPoint children
func get_connection_points() -> Array[ConnectionPoint]:
	var points: Array[ConnectionPoint] = []
	for child in get_children():
		if child is ConnectionPoint:
			points.append(child)
	return points


# Get connection points that haven't been used yet
func get_available_connections() -> Array[ConnectionPoint]:
	var available: Array[ConnectionPoint] = []
	for point in get_connection_points():
		if not point.get_meta("used", false):
			available.append(point)
	return available


# Mark a connection point as used
func mark_connection_used(point: ConnectionPoint):
	point.set_meta("used", true)


# Check if two connection points can connect (delegates to ConnectionPoint)
static func can_connect(point_a: ConnectionPoint, point_b: ConnectionPoint) -> bool:
	return point_a.is_compatible_with(point_b)


# Snap a position to the building grid
static func snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / GRID_H) * GRID_H,
		round(pos.y / GRID_V) * GRID_V,
		round(pos.z / GRID_H) * GRID_H
	)


# Snap only horizontal, keep exact vertical
static func snap_horizontal(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / GRID_H) * GRID_H,
		pos.y,
		round(pos.z / GRID_H) * GRID_H
	)


# Snap only vertical (for heightlock alignment)
static func snap_vertical(pos: Vector3) -> Vector3:
	return Vector3(
		pos.x,
		round(pos.y / GRID_V) * GRID_V,
		pos.z
	)


# Get world position of a connection point
func get_connection_world_position(point: ConnectionPoint) -> Vector3:
	return point.global_position


# Get world direction of a connection point
func get_connection_world_direction(point: ConnectionPoint) -> Vector3:
	return point.get_world_direction()
