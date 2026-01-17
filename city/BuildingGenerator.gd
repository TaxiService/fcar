# BuildingGenerator.gd - Grows modular buildings from connection points
# Attach to a node in your city scene, or call from CityGenerator
class_name BuildingGenerator
extends Node3D

# Block library - loaded from scenes
var block_library: Array[PackedScene] = []
var block_data: Array[Dictionary] = []  # Cached block info for quick filtering

# Generation settings
@export var blocks_folder: String = "res://city/building/"
@export var max_growth_depth: int = 5  # Max blocks from seed point
@export var branch_probability: float = 0.3  # Chance to use multiple connections
@export var floor_probability: float = 0.2  # Chance to force a floor block
@export var max_blocks_total: int = 500  # Hard limit to prevent freezing

@export_category("Seed Points")
@export var seeds_per_connector: int = 2  # How many buildings per connector beam
@export var seed_height_variance: float = 50.0  # Random height offset for seeds

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _blocks_placed: int = 0  # Counter for hard limit
var _recursion_count: int = 0  # Debug counter for catching infinite loops
var _placed_aabbs: Array[AABB] = []  # Track placed block bounds for overlap detection

# Debug counters
var _overlap_rejects: int = 0
var _no_anchor_rejects: int = 0
var _size_filter_rejects: int = 0
var _max_depth_reached: int = 0

@export_category("Overlap Detection")
@export var check_overlaps: bool = true  # Enable/disable overlap checking
@export var overlap_margin: float = 1.0  # Shrink AABBs by this much to allow slight overlaps

@export_category("Connection Matching")
@export var check_direction: bool = false  # Require vertical/horizontal direction match (disable for Y-rotatable blocks)


func _ready():
	_load_block_library()


func reset_counter():
	_blocks_placed = 0
	_recursion_count = 0
	_placed_aabbs.clear()
	_overlap_rejects = 0
	_no_anchor_rejects = 0
	_size_filter_rejects = 0
	_max_depth_reached = 0


func print_debug_stats():
	print("BuildingGenerator stats:")
	print("  Blocks placed: %d" % _blocks_placed)
	print("  Overlap rejects: %d" % _overlap_rejects)
	print("  No anchor rejects: %d" % _no_anchor_rejects)
	print("  Size filter rejects: %d" % _size_filter_rejects)
	print("  Max depth (%d) reached: %d times" % [max_growth_depth, _max_depth_reached])


func _load_block_library():
	print("BuildingGenerator: Loading blocks from %s..." % blocks_folder)
	block_library.clear()
	block_data.clear()

	var dir = DirAccess.open(blocks_folder)
	if not dir:
		push_error("BuildingGenerator: Cannot open blocks folder: %s" % blocks_folder)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			var path = blocks_folder + file_name
			print("  Loading: %s" % file_name)
			var scene = load(path) as PackedScene
			if scene:
				block_library.append(scene)
				# Cache block metadata
				var instance = scene.instantiate()
				if instance is BuildingBlock:
					# Check which sizes this block supports
					var has_small = false
					var has_medium = false
					var has_large = false
					for conn in instance.get_connection_points():
						if conn.size_small: has_small = true
						if conn.size_medium: has_medium = true
						if conn.size_large: has_large = true

					block_data.append({
						"scene": scene,
						"path": path,
						"type": instance.block_type,
						"can_spawn": instance.can_spawn_people,
						"weight": instance.spawn_weight,
						"min_biome": instance.min_biome,
						"max_biome": instance.max_biome,
						"connection_count": instance.get_connection_points().size(),
						"has_small": has_small,
						"has_medium": has_medium,
						"has_large": has_large,
					})
				instance.queue_free()
		file_name = dir.get_next()

	print("BuildingGenerator: Loaded %d blocks" % block_library.size())
	for data in block_data:
		print("  - %s (type=%d, connections=%d)" % [data.path.get_file(), data.type, data.connection_count])


# Generate buildings along a connector beam
func generate_on_connector(start_pos: Vector3, end_pos: Vector3, biome_idx: int):
	var direction = (end_pos - start_pos).normalized()
	var length = start_pos.distance_to(end_pos)

	for i in range(seeds_per_connector):
		# Pick a random point along the connector
		var t = _rng.randf_range(0.2, 0.8)  # Avoid very ends
		var seed_pos = start_pos.lerp(end_pos, t)

		# Add some height variance
		seed_pos.y += _rng.randf_range(-seed_height_variance, seed_height_variance)

		# Pick a random perpendicular direction to grow
		var up = Vector3.UP
		var side = direction.cross(up).normalized()
		if _rng.randf() > 0.5:
			side = -side

		# Start growing
		_grow_from_seed(seed_pos, side, biome_idx, 0)


# Grow a building structure from a seed point
# size_filter: "small", "medium", "large", or "any" - used at all depths
# base_heading: Y-rotation (radians) to align with connector direction (only used at depth 0)
func _grow_from_seed(position: Vector3, direction: Vector3, biome_idx: int, depth: int, size_filter: String = "any", base_heading: float = 0.0):
	_recursion_count += 1
	if _recursion_count > 10000:
		push_error("BuildingGenerator: Recursion limit hit!")
		return

	# Hard limits
	if depth >= max_growth_depth:
		_max_depth_reached += 1
		return
	if _blocks_placed >= max_blocks_total:
		return

	# Pick a block that fits this biome
	var valid_blocks = _get_valid_blocks(biome_idx, depth)
	if valid_blocks.is_empty():
		return

	# Filter by required connection size (uses cached data)
	if size_filter != "any":
		valid_blocks = valid_blocks.filter(func(b):
			match size_filter:
				"small": return b.has_small
				"medium": return b.has_medium
				"large": return b.has_large
				_: return true
		)
		if valid_blocks.is_empty():
			_size_filter_rejects += 1
			return

	# Weight selection towards floors if we're deep in the structure
	var force_floor = depth > 0 and _rng.randf() < floor_probability
	if force_floor:
		valid_blocks = valid_blocks.filter(func(b): return b.type == BuildingBlock.BlockType.FLOOR)
		if valid_blocks.is_empty():
			valid_blocks = _get_valid_blocks(biome_idx, depth)  # Fallback

	# Weighted random selection
	var block_info = _weighted_pick(valid_blocks)
	if not block_info:
		return

	# Instantiate the block
	var block_instance = block_info.scene.instantiate() as BuildingBlock
	if not block_instance:
		return

	add_child(block_instance)
	_blocks_placed += 1

	# Position the block - find a compatible connection point to anchor
	var connections = block_instance.get_connection_points()
	if connections.is_empty():
		block_instance.global_position = position
		# Check overlaps for directly positioned blocks too
		if check_overlaps:
			var block_aabb = _get_block_aabb(block_instance)
			if _overlaps_existing(block_aabb):
				block_instance.queue_free()
				_blocks_placed -= 1
				return
			_placed_aabbs.append(block_aabb)
	else:
		# Find a connection point that can connect (matching size, compatible direction)
		var target_dir = -direction  # We want to connect TO the seed
		var anchor = _find_compatible_connection(connections, target_dir, size_filter)

		if anchor == null:
			# No compatible connection - remove block and abort
			block_instance.queue_free()
			_blocks_placed -= 1
			_no_anchor_rejects += 1
			return

		# Rotate block to align connection with incoming direction
		_align_block_to_direction(block_instance, anchor, position, target_dir, base_heading)
		block_instance.mark_connection_used(anchor)

		# Check for overlaps (unless anchor ignores collision)
		if check_overlaps and not anchor.ignores_collision:
			var block_aabb = _get_block_aabb(block_instance)
			if _overlaps_existing(block_aabb):
				block_instance.queue_free()
				_blocks_placed -= 1
				_overlap_rejects += 1
				return
			_placed_aabbs.append(block_aabb)
		elif check_overlaps:
			# Still track AABB even if we ignored collision for this block
			_placed_aabbs.append(_get_block_aabb(block_instance))

	# Maybe branch to other connections (only from sockets)
	var remaining = block_instance.get_available_connections()
	for conn in remaining:
		# Only sockets can spawn children
		if not conn.is_socket:
			continue
		if _rng.randf() < branch_probability or depth == 0:
			var world_pos = block_instance.get_connection_world_position(conn)
			var world_dir = block_instance.get_connection_world_direction(conn)
			block_instance.mark_connection_used(conn)
			# Determine size filter from parent connection (randomly pick from available)
			var child_size_filter = _pick_random_size(conn)
			_grow_from_seed(world_pos, world_dir, biome_idx, depth + 1, child_size_filter)


# Randomly pick a size from available options on a connection point
func _pick_random_size(conn: ConnectionPoint) -> String:
	var available: Array[String] = []
	if conn.size_small:
		available.append("small")
	if conn.size_medium:
		available.append("medium")
	if conn.size_large:
		available.append("large")

	if available.is_empty():
		return "any"
	return available[_rng.randi() % available.size()]


# Find a connection point that matches size and can align with target direction
func _find_compatible_connection(connections: Array[ConnectionPoint], target_dir: Vector3, size_filter: String) -> ConnectionPoint:
	# Target direction is where we're coming FROM (the parent's outward direction)
	# We need a connection that faces roughly opposite (since cones point inward)
	# After Y-rotation, the connection should face opposite to target_dir

	for conn in connections:
		# Must be a plug (can receive connections)
		if not conn.is_plug:
			continue
		# Check size compatibility
		if size_filter != "any":
			var size_ok = false
			match size_filter:
				"small": size_ok = conn.size_small
				"medium": size_ok = conn.size_medium
				"large": size_ok = conn.size_large
			if not size_ok:
				continue

		# Check direction compatibility (optional - disable for Y-rotatable block designs)
		if check_direction:
			# Connection points face INWARD, so -Z of the marker points into the block
			var conn_dir = -conn.basis.z  # Local direction the connection faces

			# For Y-only rotation, we can only align if both directions are mostly horizontal
			var conn_vertical = abs(conn_dir.y)
			var target_vertical = abs(target_dir.y)

			# If connection is mostly vertical (pointing up/down), it can only connect to vertical targets
			# If connection is mostly horizontal, it can only connect to horizontal targets
			if conn_vertical > 0.7 and target_vertical < 0.3:
				continue  # Vertical connection can't match horizontal target
			if conn_vertical < 0.3 and target_vertical > 0.7:
				continue  # Horizontal connection can't match vertical target

		# This connection is compatible
		return conn

	return null


# Align a block so its connection point is at target_pos facing target_dir
# Only rotates around Y axis - connection point markers encode their own angles
# base_heading: For vertical connections, use this as the Y rotation (align with connector)
func _align_block_to_direction(block: BuildingBlock, conn: ConnectionPoint, target_pos: Vector3, target_dir: Vector3, base_heading: float = 0.0):
	# target_dir points from parent TOWARD child position (= -direction passed to _grow_from_seed)
	# Child's connection INWARD direction (cone) should point INTO child = same as target_dir
	# This ensures child is positioned BEYOND the connection point, not inside parent

	# Get horizontal components for Y-rotation calculation
	var target_horiz = Vector2(target_dir.x, target_dir.z)
	var conn_local_dir = -conn.basis.z  # Local inward direction
	var conn_horiz = Vector2(conn_local_dir.x, conn_local_dir.z)

	# Only rotate if there's meaningful horizontal component (skip for pure vertical)
	if target_horiz.length() > 0.1 and conn_horiz.length() > 0.1:
		var target_yaw = atan2(target_dir.x, target_dir.z)
		var conn_yaw = atan2(conn_local_dir.x, conn_local_dir.z)
		block.rotation.y = target_yaw - conn_yaw
	else:
		# For vertical connections, use base_heading to align with connector direction
		block.rotation.y = base_heading

	# Position block so connection point lands at target_pos
	var rotated_offset = block.basis * conn.position
	block.global_position = target_pos - rotated_offset


func _get_valid_blocks(biome_idx: int, depth: int) -> Array:
	var valid: Array = []
	for data in block_data:
		if biome_idx >= data.min_biome and biome_idx <= data.max_biome:
			# Prefer caps at max depth
			if depth >= max_growth_depth - 1:
				if data.type == BuildingBlock.BlockType.CAP:
					valid.append(data)
			else:
				valid.append(data)
	# Fallback: if no caps found at max depth, use anything
	if valid.is_empty():
		for data in block_data:
			if biome_idx >= data.min_biome and biome_idx <= data.max_biome:
				valid.append(data)
	return valid


func _weighted_pick(blocks: Array) -> Dictionary:
	if blocks.is_empty():
		return {}

	var total_weight = 0.0
	for b in blocks:
		total_weight += b.weight

	var roll = _rng.randf() * total_weight
	var cumulative = 0.0
	for b in blocks:
		cumulative += b.weight
		if roll <= cumulative:
			return b

	return blocks[0]


# Debug: generate test buildings
func generate_test(count: int = 5):
	_rng.randomize()
	for i in range(count):
		var pos = Vector3(
			_rng.randf_range(-100, 100),
			_rng.randf_range(50, 200),
			_rng.randf_range(-100, 100)
		)
		var dir = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		_grow_from_seed(pos, dir, _rng.randi_range(0, 3), 0)
	print("BuildingGenerator: Generated %d test structures" % count)


# Get world-space AABB for a block (from collision shapes or meshes)
func _get_block_aabb(block: Node3D) -> AABB:
	var combined_aabb = AABB()
	var first = true

	# Look for collision shapes first (more accurate for gameplay)
	for child in block.get_children():
		if child is CollisionShape3D and child.shape:
			var shape_aabb = _get_shape_aabb(child.shape)
			# Transform to world space
			var world_aabb = _transform_aabb(shape_aabb, child.global_transform)
			if first:
				combined_aabb = world_aabb
				first = false
			else:
				combined_aabb = combined_aabb.merge(world_aabb)
		elif child is MeshInstance3D and child.mesh:
			var mesh_aabb = child.mesh.get_aabb()
			var world_aabb = _transform_aabb(mesh_aabb, child.global_transform)
			if first:
				combined_aabb = world_aabb
				first = false
			else:
				combined_aabb = combined_aabb.merge(world_aabb)

	# If no shapes/meshes found, use a default box around the block position
	if first:
		combined_aabb = AABB(block.global_position - Vector3(5, 5, 5), Vector3(10, 10, 10))

	return combined_aabb


# Get AABB for various collision shape types
func _get_shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var half = shape.size / 2
		return AABB(-half, shape.size)
	elif shape is SphereShape3D:
		var r = shape.radius
		return AABB(Vector3(-r, -r, -r), Vector3(r * 2, r * 2, r * 2))
	elif shape is CylinderShape3D:
		var r = shape.radius
		var h = shape.height / 2
		return AABB(Vector3(-r, -h, -r), Vector3(r * 2, shape.height, r * 2))
	elif shape is CapsuleShape3D:
		var r = shape.radius
		var h = shape.height / 2
		return AABB(Vector3(-r, -h, -r), Vector3(r * 2, shape.height, r * 2))
	else:
		# Fallback for unknown shapes
		return AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))


# Transform a local AABB to world space (approximation using corners)
func _transform_aabb(local_aabb: AABB, xform: Transform3D) -> AABB:
	# Transform all 8 corners and create new AABB
	var corners: Array[Vector3] = []
	var pos = local_aabb.position
	var size = local_aabb.size

	corners.append(xform * (pos))
	corners.append(xform * (pos + Vector3(size.x, 0, 0)))
	corners.append(xform * (pos + Vector3(0, size.y, 0)))
	corners.append(xform * (pos + Vector3(0, 0, size.z)))
	corners.append(xform * (pos + Vector3(size.x, size.y, 0)))
	corners.append(xform * (pos + Vector3(size.x, 0, size.z)))
	corners.append(xform * (pos + Vector3(0, size.y, size.z)))
	corners.append(xform * (pos + size))

	var result = AABB(corners[0], Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(corners[i])
	return result


# Check if an AABB overlaps any existing placed blocks
func _overlaps_existing(new_aabb: AABB) -> bool:
	# Shrink the AABB by margin to allow slight overlaps
	var test_aabb = new_aabb.grow(-overlap_margin)

	for existing in _placed_aabbs:
		if test_aabb.intersects(existing):
			return true
	return false
