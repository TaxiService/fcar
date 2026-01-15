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
