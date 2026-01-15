# BuildingBlock.gd - Attach to root of each modular building block scene
# Connection points are defined as child Marker3D nodes
# Marker's -Z axis points outward (connection direction)
# Name format: "Conn_GENDER_SIZE" e.g. "Conn_Socket_Medium", "Conn_Plug_Large"
class_name BuildingBlock
extends Node3D

enum BlockType {
	STRUCTURAL,  # Basic mass/volume blocks
	FLOOR,       # Has surface where people can spawn
	CAP,         # Decorative terminator (antenna, dome, etc.)
	JUNCTION,    # Allows branching/sideways connections
}

enum ConnectorGender {
	PLUG,    # Male - inserts into socket
	SOCKET,  # Female - receives plug
}

enum ConnectorSize {
	SMALL,   # Small connections (railings, antennas)
	MEDIUM,  # Standard building connections
	LARGE,   # Major structural connections
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


# Get all connection points defined as child Marker3D nodes
func get_connection_points() -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for child in get_children():
		if child is Marker3D and child.name.begins_with("Conn_"):
			var parts = child.name.split("_")
			if parts.size() >= 3:
				points.append({
					"node": child,
					"position": child.position,
					"direction": -child.basis.z.normalized(),  # -Z = outward
					"gender": _parse_gender(parts[1]),
					"size": _parse_size(parts[2]),
					"used": false,
				})
	return points


# Get only unused (available) connection points
func get_available_connections() -> Array[Dictionary]:
	return get_connection_points().filter(func(p): return not p.used)


# Check if two connection points can connect
static func can_connect(point_a: Dictionary, point_b: Dictionary) -> bool:
	# Genders must be opposite (plug into socket)
	if point_a.gender == point_b.gender:
		return false

	# Sizes must match
	if point_a.size != point_b.size:
		return false

	# Directions must be roughly opposite (facing each other)
	var dot = point_a.direction.dot(point_b.direction)
	if dot > -0.9:  # Should be close to -1 (opposite directions)
		return false

	return true


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
func get_connection_world_position(point: Dictionary) -> Vector3:
	return global_transform * point.position


# Get world direction of a connection point
func get_connection_world_direction(point: Dictionary) -> Vector3:
	return global_transform.basis * point.direction


func _parse_gender(s: String) -> ConnectorGender:
	match s.to_lower():
		"plug": return ConnectorGender.PLUG
		_: return ConnectorGender.SOCKET


func _parse_size(s: String) -> ConnectorSize:
	match s.to_lower():
		"small": return ConnectorSize.SMALL
		"large": return ConnectorSize.LARGE
		_: return ConnectorSize.MEDIUM


# Debug: draw connection points in editor
func _draw_debug_connections():
	for point in get_connection_points():
		var color = Color.BLUE if point.gender == ConnectorGender.SOCKET else Color.RED
		# Would need immediate geometry or debug draw here
		pass
