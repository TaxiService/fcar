# BuildingGenerator.gd - Breadth-first modular building growth
# Grows ALL buildings simultaneously, one depth layer at a time
# This prevents early buildings from hogging all the space
class_name BuildingGenerator
extends Node3D

# Block library - loaded from scenes
var block_library: Array[PackedScene] = []
var block_data: Array[Dictionary] = []  # Cached block info for quick filtering

# Generation settings
@export var blocks_folder: String = "res://city/building/"
@export var max_growth_depth: int = 5  # Max blocks from seed point
@export var branch_probability: float = 0.5  # Chance to use each available socket
@export var floor_probability: float = 0.2  # Chance to force a floor block
@export var max_blocks_total: int = 500  # Hard limit to prevent freezing

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _placed_aabbs: Array[AABB] = []  # Track placed block bounds for overlap detection

# The growth queue - each entry represents a potential block placement
# Processed in rounds (all depth-0, then all depth-1, etc.)
var _growth_queue: Array[Dictionary] = []  # [{pos, dir, biome, depth, size_filter, heading, parent_block}]

# Statistics - now tracks per-seed outcomes
var _stats: Dictionary = {
	"blocks_placed": 0,
	"seeds_received": 0,
	"seeds_succeeded": 0,  # At least one block placed
	"seeds_failed_overlap": 0,
	"seeds_failed_no_anchor": 0,
	"seeds_failed_no_valid_blocks": 0,
	"overlap_rejects": 0,
	"no_anchor_rejects": 0,
	"size_filter_rejects": 0,
	"rotation_retries": 0,
	"block_retries": 0,
	"depth_distribution": {},  # depth -> count of blocks placed at that depth
}

# Y-rotation offsets to try for vertical connections (in radians)
const VERTICAL_ROTATION_OFFSETS = [0.0, PI / 2.0, -PI / 2.0, PI]

@export_category("Overlap Detection")
@export var check_overlaps: bool = true
@export var overlap_margin: float = 1.0  # Shrink AABBs by this to allow slight overlaps
@export var max_block_attempts: int = 5  # Max different blocks to try per queue entry

@export_category("Debug")
@export var verbose: bool = false  # Print per-seed outcomes


func _ready():
	_load_block_library()


func reset():
	_placed_aabbs.clear()
	_growth_queue.clear()
	_stats = {
		"blocks_placed": 0,
		"seeds_received": 0,
		"seeds_succeeded": 0,
		"seeds_failed_overlap": 0,
		"seeds_failed_no_anchor": 0,
		"seeds_failed_no_valid_blocks": 0,
		"overlap_rejects": 0,
		"no_anchor_rejects": 0,
		"size_filter_rejects": 0,
		"rotation_retries": 0,
		"block_retries": 0,
		"depth_distribution": {},
	}
	# Clear any existing blocks
	for child in get_children():
		child.queue_free()


# Legacy compatibility
func reset_counter():
	reset()


func register_external_aabbs(aabbs: Array[AABB]):
	for aabb in aabbs:
		_placed_aabbs.append(aabb)
	if verbose:
		print("BuildingGenerator: Registered %d external AABBs" % aabbs.size())


# === PUBLIC API ===

# Queue a seed for later processing (call this for each seed point)
func queue_seed(position: Vector3, direction: Vector3, biome_idx: int, size_filter: String = "any", heading: float = 0.0):
	_stats.seeds_received += 1
	_growth_queue.append({
		"pos": position,
		"dir": direction,
		"biome": biome_idx,
		"depth": 0,
		"size_filter": size_filter,
		"heading": heading,
		"parent_block": null,
		"is_seed": true,  # Track this for statistics
	})


# Process all queued growth in breadth-first order
# Call this AFTER queueing all seeds
func process_queue():
	if _growth_queue.is_empty():
		print("BuildingGenerator: No seeds queued")
		return
	
	print("BuildingGenerator: Processing %d seeds (max depth %d, max blocks %d)" % [
		_stats.seeds_received, max_growth_depth, max_blocks_total
	])
	
	var current_depth = 0
	
	while not _growth_queue.is_empty() and _stats.blocks_placed < max_blocks_total:
		# Find minimum depth in queue
		var min_depth = 999
		for entry in _growth_queue:
			min_depth = mini(min_depth, entry.depth)
		
		if min_depth > current_depth:
			if verbose:
				print("  Depth %d complete, %d blocks placed so far" % [current_depth, _stats.blocks_placed])
			current_depth = min_depth
		
		if current_depth >= max_growth_depth:
			# All remaining entries are at or beyond max depth - terminate them
			if verbose:
				print("  Reached max depth, %d entries terminated" % _growth_queue.size())
			_growth_queue.clear()
			break
		
		# Process all entries at current depth
		var entries_at_depth: Array[Dictionary] = []
		var remaining: Array[Dictionary] = []
		
		for entry in _growth_queue:
			if entry.depth == current_depth:
				entries_at_depth.append(entry)
			else:
				remaining.append(entry)
		
		_growth_queue = remaining
		
		# Shuffle entries at this depth for variety
		entries_at_depth.shuffle()
		
		# Process each entry
		for entry in entries_at_depth:
			if _stats.blocks_placed >= max_blocks_total:
				break
			_process_single_entry(entry)
	
	print("BuildingGenerator: Complete")
	print_stats()


# Legacy API - grow a single seed immediately (depth-first, old behavior)
# Kept for compatibility but now just queues and processes
func _grow_from_seed(position: Vector3, direction: Vector3, biome_idx: int, depth: int, size_filter: String = "any", base_heading: float = 0.0):
	queue_seed(position, direction, biome_idx, size_filter, base_heading)
	# Note: Won't process until process_queue() is called
	# For immediate processing, caller should call process_queue() after all seeds


# === INTERNAL ===

func _process_single_entry(entry: Dictionary):
	var position: Vector3 = entry.pos
	var direction: Vector3 = entry.dir
	var biome_idx: int = entry.biome
	var depth: int = entry.depth
	var size_filter: String = entry.size_filter
	var base_heading: float = entry.heading
	var is_seed: bool = entry.get("is_seed", false)
	
	# Get valid blocks for this biome/depth
	var valid_blocks = _get_valid_blocks(biome_idx, depth)
	if valid_blocks.is_empty():
		if is_seed:
			_stats.seeds_failed_no_valid_blocks += 1
		return
	
	# Filter by required connection size
	if size_filter != "any":
		valid_blocks = valid_blocks.filter(func(b):
			match size_filter:
				"small": return b.has_small_plug
				"medium": return b.has_medium_plug
				"large": return b.has_large_plug
				_: return true
		)
		if valid_blocks.is_empty():
			_stats.size_filter_rejects += 1
			if is_seed:
				_stats.seeds_failed_no_valid_blocks += 1
			return
	
	# Maybe force floor blocks deeper in
	if depth > 0 and _rng.randf() < floor_probability:
		var floor_blocks = valid_blocks.filter(func(b): return b.type == BuildingBlock.BlockType.FLOOR)
		if not floor_blocks.is_empty():
			valid_blocks = floor_blocks
	
	# Shuffle and try blocks until one succeeds
	var shuffled = valid_blocks.duplicate()
	shuffled.shuffle()
	
	var target_dir = -direction  # Connection faces opposite to growth direction
	var attempts = mini(max_block_attempts, shuffled.size())
	var placed_block: BuildingBlock = null
	
	for attempt_idx in range(attempts):
		var block_info = shuffled[attempt_idx]
		var result = _try_place_block(block_info, position, target_dir, base_heading, depth)
		
		if result.success:
			placed_block = result.block
			if attempt_idx > 0:
				_stats.block_retries += 1
			break
		else:
			match result.reason:
				"overlap":
					_stats.overlap_rejects += 1
				"no_anchor":
					_stats.no_anchor_rejects += 1
	
	if placed_block == null:
		if is_seed:
			_stats.seeds_failed_overlap += 1
		return
	
	# Success! Update stats
	_stats.blocks_placed += 1
	if is_seed:
		_stats.seeds_succeeded += 1
	
	var depth_key = str(depth)
	_stats.depth_distribution[depth_key] = _stats.depth_distribution.get(depth_key, 0) + 1
	
	# Queue children from available sockets
	_queue_children(placed_block, biome_idx, depth, size_filter)


func _try_place_block(block_info: Dictionary, position: Vector3, target_dir: Vector3, base_heading: float, depth: int) -> Dictionary:
	var scene: PackedScene = block_info.scene
	var instance = scene.instantiate() as BuildingBlock
	if not instance:
		return {"success": false, "reason": "instantiate_failed"}
	
	add_child(instance)
	
	var connections = instance.get_connection_points()
	
	if connections.is_empty():
		# Block with no connections - just position directly
		instance.global_position = position
		var block_aabb = _get_block_aabb(instance)
		if check_overlaps and _overlaps_existing(block_aabb):
			instance.queue_free()
			return {"success": false, "reason": "overlap"}
		_placed_aabbs.append(block_aabb)
		return {"success": true, "block": instance}
	
	# Find a compatible anchor connection
	var anchor = _find_compatible_connection(connections, target_dir, block_info)
	if anchor == null:
		instance.queue_free()
		return {"success": false, "reason": "no_anchor"}
	
	# Try to place with rotation variants for vertical connections
	var is_vertical = abs(target_dir.y) > 0.9
	var rotations_to_try = VERTICAL_ROTATION_OFFSETS if is_vertical else [0.0]
	
	for rot_idx in range(rotations_to_try.size()):
		var extra_rotation = rotations_to_try[rot_idx]
		_align_block(instance, anchor, position, target_dir, base_heading, extra_rotation)
		
		var block_aabb = _get_block_aabb(instance)
		
		if not check_overlaps or anchor.ignores_collision or not _overlaps_existing(block_aabb):
			# Success!
			_placed_aabbs.append(block_aabb)
			instance.mark_connection_used(anchor)
			if rot_idx > 0:
				_stats.rotation_retries += 1
			return {"success": true, "block": instance}
	
	# All rotations failed
	instance.queue_free()
	return {"success": false, "reason": "overlap"}


func _queue_children(block: BuildingBlock, biome_idx: int, parent_depth: int, parent_size_filter: String):
	var child_depth = parent_depth + 1
	if child_depth >= max_growth_depth:
		return
	
	var available = block.get_available_connections()
	var child_heading = block.rotation.y
	
	for conn in available:
		# Only sockets can spawn children
		if not conn.is_socket:
			continue
		
		# Probability check (but always branch at depth 0 to ensure buildings grow)
		if parent_depth > 0 and _rng.randf() > branch_probability:
			continue
		
		var world_pos = block.get_connection_world_position(conn)
		var world_dir = block.get_connection_world_direction(conn)
		block.mark_connection_used(conn)
		
		# Pick size from connection's available sizes
		var child_size = _pick_random_size(conn)
		
		_growth_queue.append({
			"pos": world_pos,
			"dir": world_dir,
			"biome": biome_idx,
			"depth": child_depth,
			"size_filter": child_size,
			"heading": child_heading,
			"parent_block": block,
			"is_seed": false,
		})


func _find_compatible_connection(connections: Array[ConnectionPoint], target_dir: Vector3, block_info: Dictionary) -> ConnectionPoint:
	# Look for a plug that matches the required size
	for conn in connections:
		if not conn.is_plug:
			continue
		
		# Check size - use block_info's cached size data for efficiency
		# The target_dir tells us what size we need (inherited from parent)
		# For now, any plug of any size works - size filtering happened at block selection
		
		return conn  # Return first available plug
	
	return null


func _align_block(block: BuildingBlock, conn: ConnectionPoint, target_pos: Vector3, target_dir: Vector3, base_heading: float, extra_y_rotation: float = 0.0):
	# Get horizontal components for Y-rotation calculation
	var target_horiz = Vector2(target_dir.x, target_dir.z)
	var conn_local_dir = -conn.basis.z  # Local inward direction (cone points -Z)
	var conn_horiz = Vector2(conn_local_dir.x, conn_local_dir.z)
	
	# Calculate required Y rotation
	if target_horiz.length() > 0.1 and conn_horiz.length() > 0.1:
		var target_yaw = atan2(target_dir.x, target_dir.z)
		var conn_yaw = atan2(conn_local_dir.x, conn_local_dir.z)
		block.rotation.y = target_yaw - conn_yaw + extra_y_rotation
	else:
		# Vertical connection - use base heading
		block.rotation.y = base_heading + extra_y_rotation
	
	# Position block so connection point lands at target_pos
	var rotated_offset = block.basis * conn.position
	block.global_position = target_pos - rotated_offset


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
	
	# Fallback if no caps found
	if valid.is_empty():
		for data in block_data:
			if biome_idx >= data.min_biome and biome_idx <= data.max_biome:
				valid.append(data)
	
	return valid


# === AABB UTILITIES ===

func _get_block_aabb(block: Node3D) -> AABB:
	var combined_aabb = AABB()
	var first = true
	
	for child in block.get_children():
		if child is CollisionShape3D and child.shape:
			var shape_aabb = _get_shape_aabb(child.shape)
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
	
	if first:
		combined_aabb = AABB(block.global_position - Vector3(5, 5, 5), Vector3(10, 10, 10))
	
	return combined_aabb


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
		return AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))


func _transform_aabb(local_aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	var pos = local_aabb.position
	var size = local_aabb.size
	
	corners.append(xform * pos)
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


func _overlaps_existing(new_aabb: AABB) -> bool:
	var test_aabb = new_aabb.grow(-overlap_margin)
	for existing in _placed_aabbs:
		if test_aabb.intersects(existing):
			return true
	return false


# === BLOCK LIBRARY ===

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
			var scene = load(path) as PackedScene
			if scene:
				block_library.append(scene)
				var instance = scene.instantiate()
				if instance is BuildingBlock:
					var has_small_plug = false
					var has_medium_plug = false
					var has_large_plug = false
					var has_small = false
					var has_medium = false
					var has_large = false
					
					for conn in instance.get_connection_points():
						if conn.size_small:
							has_small = true
							if conn.is_plug:
								has_small_plug = true
						if conn.size_medium:
							has_medium = true
							if conn.is_plug:
								has_medium_plug = true
						if conn.size_large:
							has_large = true
							if conn.is_plug:
								has_large_plug = true
					
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
						"has_small_plug": has_small_plug,
						"has_medium_plug": has_medium_plug,
						"has_large_plug": has_large_plug,
					})
				instance.queue_free()
		file_name = dir.get_next()
	
	print("BuildingGenerator: Loaded %d blocks" % block_library.size())


# === DEBUG ===

func print_stats():
	print("BuildingGenerator stats:")
	print("  Seeds: %d received, %d succeeded (%.1f%%)" % [
		_stats.seeds_received,
		_stats.seeds_succeeded,
		100.0 * _stats.seeds_succeeded / max(_stats.seeds_received, 1)
	])
	print("  Seed failures: %d overlap, %d no anchor, %d no valid blocks" % [
		_stats.seeds_failed_overlap,
		_stats.seeds_failed_no_anchor,
		_stats.seeds_failed_no_valid_blocks
	])
	print("  Blocks placed: %d" % _stats.blocks_placed)
	print("  Rejects: %d overlap, %d no anchor, %d size filter" % [
		_stats.overlap_rejects,
		_stats.no_anchor_rejects,
		_stats.size_filter_rejects
	])
	print("  Retries saved: %d rotation, %d block" % [
		_stats.rotation_retries,
		_stats.block_retries
	])
	
	# Depth distribution
	var depths = _stats.depth_distribution.keys()
	depths.sort()
	var depth_str = ""
	for d in depths:
		depth_str += "d%s:%d " % [d, _stats.depth_distribution[d]]
	if depth_str != "":
		print("  Depth distribution: %s" % depth_str.strip_edges())


# Legacy compatibility
func print_debug_stats():
	print_stats()
