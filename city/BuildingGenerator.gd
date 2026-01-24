# BuildingGenerator.gd - Breadth-first modular building growth
# Uses bitmask flags for flexible type/size matching
# Includes direction matching for top/bottom seed discrimination
class_name BuildingGenerator
extends Node3D

# Shorthand for flag enums
const TF = ConnectionPoint.TypeFlags
const SF = ConnectionPoint.SizeFlags

# Block library
var block_library: Array[PackedScene] = []
var block_data: Array[Dictionary] = []

# Generation settings
@export var blocks_folder: String = "res://city/building/"
@export var max_growth_depth: int = 5
@export var branch_probability: float = 0.5
@export var max_blocks_total: int = 500

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _placed_aabbs: Array[AABB] = []
var _growth_queue: Array[Dictionary] = []
var _stats: Dictionary = {}


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
		"seeds_failed_no_blocks": 0,
		"overlap_rejects": 0,
		"no_match_rejects": 0,
		"direction_rejects": 0,
		"rotation_retries": 0,
		"block_retries": 0,
		"depth_distribution": {},
		"type_distribution": {},
	}
	for child in get_children():
		child.queue_free()


func reset_counter():
	reset()


func register_external_aabbs(aabbs: Array[AABB]):
	for aabb in aabbs:
		_placed_aabbs.append(aabb.abs())  # Ensure positive size


# === PUBLIC API ===

func queue_seed(position: Vector3, direction: Vector3, biome_idx: int,
				type_flags: int, size_flags: int, heading: float = 0.0):
	_stats.seeds_received += 1
	_growth_queue.append({
		"pos": position,
		"dir": direction,
		"biome": biome_idx,
		"depth": 0,
		"type_flags": type_flags,
		"size_flags": size_flags,
		"heading": heading,
		"is_seed": true,
	})


func process_queue():
	if _growth_queue.is_empty():
		print("BuildingGenerator: No seeds queued")
		return
	
	print("BuildingGenerator: Processing %d seeds (max depth %d, max blocks %d)" % [
		_stats.seeds_received, max_growth_depth, max_blocks_total
	])
	
	var current_depth = 0
	
	while not _growth_queue.is_empty() and _stats.blocks_placed < max_blocks_total:
		var min_depth = 999
		for entry in _growth_queue:
			min_depth = mini(min_depth, entry.depth)
		
		if min_depth > current_depth:
			current_depth = min_depth
		
		if current_depth >= max_growth_depth:
			_growth_queue.clear()
			break
		
		var entries_at_depth: Array[Dictionary] = []
		var remaining: Array[Dictionary] = []
		
		for entry in _growth_queue:
			if entry.depth == current_depth:
				entries_at_depth.append(entry)
			else:
				remaining.append(entry)
		
		_growth_queue = remaining
		entries_at_depth.shuffle()
		
		for entry in entries_at_depth:
			if _stats.blocks_placed >= max_blocks_total:
				break
			_process_entry(entry)
	
	print("BuildingGenerator: Complete")
	print_stats()


# === INTERNAL ===

func _process_entry(entry: Dictionary):
	var position: Vector3 = entry.pos
	var direction: Vector3 = entry.dir
	var biome_idx: int = entry.biome
	var depth: int = entry.depth
	var type_flags: int = entry.type_flags
	var size_flags: int = entry.size_flags
	var base_heading: float = entry.heading
	var is_seed: bool = entry.get("is_seed", false)
	
	var target_dir = -direction  # The direction the plug needs to face
	
	# Get blocks that have a plug matching our type+size+direction
	var valid_blocks = _get_matching_blocks(biome_idx, depth, type_flags, size_flags, target_dir)
	
	if valid_blocks.is_empty():
		_stats.no_match_rejects += 1
		if is_seed:
			_stats.seeds_failed_no_blocks += 1
		return
	
	var shuffled = valid_blocks.duplicate()
	shuffled.shuffle()
	
	var placed_block: BuildingBlock = null
	
	for attempt_idx in range(mini(5, shuffled.size())):
		var block_info = shuffled[attempt_idx]
		var result = _try_place_block(block_info, position, target_dir, type_flags, size_flags, base_heading)
		
		if result.success:
			placed_block = result.block
			if attempt_idx > 0:
				_stats.block_retries += 1
			break
		elif result.reason == "overlap":
			_stats.overlap_rejects += 1
		elif result.reason == "direction":
			_stats.direction_rejects += 1
	
	if placed_block == null:
		if is_seed:
			_stats.seeds_failed_overlap += 1
		return
	
	# Success
	_stats.blocks_placed += 1
	if is_seed:
		_stats.seeds_succeeded += 1
	
	var depth_key = str(depth)
	_stats.depth_distribution[depth_key] = _stats.depth_distribution.get(depth_key, 0) + 1
	_track_type_stats(type_flags)
	
	# Queue children
	_queue_children(placed_block, biome_idx, depth)


func _track_type_stats(flags: int):
	if flags & TF.SEED:
		_stats.type_distribution["SEED"] = _stats.type_distribution.get("SEED", 0) + 1
	if flags & TF.STRUCTURAL:
		_stats.type_distribution["STRUCTURAL"] = _stats.type_distribution.get("STRUCTURAL", 0) + 1
	if flags & TF.JUNCTION:
		_stats.type_distribution["JUNCTION"] = _stats.type_distribution.get("JUNCTION", 0) + 1
	if flags & TF.CAP:
		_stats.type_distribution["CAP"] = _stats.type_distribution.get("CAP", 0) + 1


func _try_place_block(block_info: Dictionary, position: Vector3, target_dir: Vector3,
					  required_types: int, required_sizes: int, base_heading: float) -> Dictionary:
	var scene: PackedScene = block_info.scene
	var instance = scene.instantiate() as BuildingBlock
	if not instance:
		return {"success": false, "reason": "instantiate_failed"}
	
	add_child(instance)
	
	# Find a plug that matches requirements AND direction
	var anchor = _find_matching_plug(instance, required_types, required_sizes, target_dir)
	if anchor == null:
		instance.queue_free()
		return {"success": false, "reason": "direction"}
	
	# Try rotations
	var rotations = anchor.get_allowed_rotations()
	
	for rot_idx in range(rotations.size()):
		var extra_rotation = rotations[rot_idx]
		_align_block(instance, anchor, position, target_dir, base_heading, extra_rotation)
		
		var block_aabb = _get_block_aabb(instance)
		
		if anchor.ignores_collision or not _overlaps_existing(block_aabb):
			_placed_aabbs.append(block_aabb)
			instance.mark_connection_used(anchor)
			if rot_idx > 0:
				_stats.rotation_retries += 1
			return {"success": true, "block": instance, "anchor": anchor}
	
	instance.queue_free()
	return {"success": false, "reason": "overlap"}


func _find_matching_plug(block: BuildingBlock, required_types: int, required_sizes: int, target_dir: Vector3) -> ConnectionPoint:
	for conn in block.get_connection_points():
		if not conn.is_plug:
			continue
		
		# Check type and size flags overlap
		if (conn.type_flags & required_types) == 0:
			continue
		if (conn.size_flags & required_sizes) == 0:
			continue
		
		# Check direction compatibility
		# Since we only rotate around Y, vertical component of plug direction is fixed
		if not _direction_compatible(conn, target_dir):
			continue
		
		return conn
	
	return null


func _direction_compatible(conn: ConnectionPoint, target_dir: Vector3) -> bool:
	# Get the plug's local direction (points INTO the block)
	# ConnectionPoint's -Z axis points inward
	var local_dir = -conn.basis.z
	
	# Classify both directions as UP, DOWN, or HORIZONTAL
	var plug_vertical = _classify_vertical(local_dir)
	var target_vertical = _classify_vertical(target_dir)
	
	# They must match: UP↔UP, DOWN↔DOWN, HORIZONTAL↔HORIZONTAL
	return plug_vertical == target_vertical


func _classify_vertical(dir: Vector3) -> int:
	# Returns: 1 = UP, -1 = DOWN, 0 = HORIZONTAL
	if dir.y > 0.7:
		return 1   # Pointing up
	elif dir.y < -0.7:
		return -1  # Pointing down
	else:
		return 0   # Horizontal


func _queue_children(block: BuildingBlock, biome_idx: int, parent_depth: int):
	var child_depth = parent_depth + 1
	if child_depth >= max_growth_depth:
		return
	
	var child_heading = block.rotation.y
	
	for conn in block.get_available_connections():
		if not conn.is_socket:
			continue
		
		# CAP-only sockets don't spawn children
		if conn.type_flags == TF.CAP:
			continue
		
		# Probability check (always branch at depth 0)
		if parent_depth > 0 and _rng.randf() > branch_probability:
			continue
		
		var world_pos = block.get_connection_world_position(conn)
		var world_dir = block.get_connection_world_direction(conn)
		block.mark_connection_used(conn)
		
		_growth_queue.append({
			"pos": world_pos,
			"dir": world_dir,
			"biome": biome_idx,
			"depth": child_depth,
			"type_flags": conn.type_flags,
			"size_flags": conn.size_flags,
			"heading": child_heading,
			"is_seed": false,
		})


func _get_matching_blocks(biome_idx: int, depth: int, type_flags: int, size_flags: int, target_dir: Vector3) -> Array:
	var valid: Array = []
	
	for data in block_data:
		if biome_idx < data.min_biome or biome_idx > data.max_biome:
			continue
		
		# Check if any plug matches type+size+direction
		if not _block_has_matching_plug(data, type_flags, size_flags, target_dir):
			continue
		
		# Prefer caps at max depth
		if depth >= max_growth_depth - 1:
			if data.type == BuildingBlock.BlockType.CAP:
				valid.append(data)
		else:
			valid.append(data)
	
	# Fallback
	if valid.is_empty():
		for data in block_data:
			if biome_idx >= data.min_biome and biome_idx <= data.max_biome:
				if _block_has_matching_plug(data, type_flags, size_flags, target_dir):
					valid.append(data)
	
	return valid


func _block_has_matching_plug(data: Dictionary, type_flags: int, size_flags: int, target_dir: Vector3) -> bool:
	var target_vertical = _classify_vertical(target_dir)
	
	for plug in data.get("plugs", []):
		# Check flags overlap
		var types_match = (plug.type_flags & type_flags) != 0
		var sizes_match = (plug.size_flags & size_flags) != 0
		if not types_match or not sizes_match:
			continue
		
		# Check direction compatibility
		if plug.vertical_class == target_vertical:
			return true
	
	return false


func _align_block(block: BuildingBlock, conn: ConnectionPoint, target_pos: Vector3,
				  target_dir: Vector3, base_heading: float, extra_y_rotation: float = 0.0):
	var target_horiz = Vector2(target_dir.x, target_dir.z)
	var conn_local_dir = -conn.basis.z
	var conn_horiz = Vector2(conn_local_dir.x, conn_local_dir.z)
	
	if target_horiz.length() > 0.1 and conn_horiz.length() > 0.1:
		var target_yaw = atan2(target_dir.x, target_dir.z)
		var conn_yaw = atan2(conn_local_dir.x, conn_local_dir.z)
		block.rotation.y = target_yaw - conn_yaw + extra_y_rotation
	else:
		block.rotation.y = base_heading + extra_y_rotation
	
	var rotated_offset = block.basis * conn.position
	block.global_position = target_pos - rotated_offset


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
	
	return combined_aabb.abs()  # Ensure positive size


func _get_shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		return AABB(-shape.size / 2, shape.size)
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
	return AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))


func _transform_aabb(local_aabb: AABB, xform: Transform3D) -> AABB:
	var pos = local_aabb.position
	var size = local_aabb.size
	var corners = [
		xform * pos,
		xform * (pos + Vector3(size.x, 0, 0)),
		xform * (pos + Vector3(0, size.y, 0)),
		xform * (pos + Vector3(0, 0, size.z)),
		xform * (pos + Vector3(size.x, size.y, 0)),
		xform * (pos + Vector3(size.x, 0, size.z)),
		xform * (pos + Vector3(0, size.y, size.z)),
		xform * (pos + size),
	]
	var result = AABB(corners[0], Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(corners[i])
	return result.abs()  # Ensure positive size


func _overlaps_existing(new_aabb: AABB) -> bool:
	var test_aabb = new_aabb.abs().grow(-1.0)  # Ensure positive and shrink by margin
	for existing in _placed_aabbs:
		if test_aabb.intersects(existing.abs()):
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
					block_data.append(_analyze_block(instance, scene, path))
				instance.queue_free()
		file_name = dir.get_next()
	
	print("BuildingGenerator: Loaded %d blocks" % block_library.size())
	_print_block_summary()


func _analyze_block(instance: BuildingBlock, scene: PackedScene, path: String) -> Dictionary:
	var plugs: Array[Dictionary] = []
	var sockets: Array[Dictionary] = []
	
	for conn in instance.get_connection_points():
		# Get the plug/socket direction for vertical classification
		var local_dir = -conn.basis.z
		var vert_class = _classify_vertical(local_dir)
		
		var info = {
			"type_flags": conn.type_flags,
			"size_flags": conn.size_flags,
			"rotation_mode": conn.rotation_mode,
			"vertical_class": vert_class,  # 1=UP, -1=DOWN, 0=HORIZONTAL
		}
		if conn.is_plug:
			plugs.append(info)
		if conn.is_socket:
			sockets.append(info)
	
	return {
		"scene": scene,
		"path": path,
		"type": instance.block_type,
		"can_spawn": instance.can_spawn_people,
		"weight": instance.spawn_weight,
		"min_biome": instance.min_biome,
		"max_biome": instance.max_biome,
		"plugs": plugs,
		"sockets": sockets,
	}


func _print_block_summary():
	for data in block_data:
		var plug_strs: Array[String] = []
		for p in data.plugs:
			plug_strs.append("%s/%s%s" % [
				_type_flags_str(p.type_flags),
				_size_flags_str(p.size_flags),
				_vert_class_str(p.vertical_class)
			])
		
		var socket_strs: Array[String] = []
		for s in data.sockets:
			socket_strs.append("%s/%s%s" % [
				_type_flags_str(s.type_flags),
				_size_flags_str(s.size_flags),
				_vert_class_str(s.vertical_class)
			])
		
		print("  %s: plugs=[%s] sockets=[%s]" % [
			data.path.get_file(),
			", ".join(plug_strs) if plug_strs.size() > 0 else "none",
			", ".join(socket_strs) if socket_strs.size() > 0 else "none"
		])


func _type_flags_str(flags: int) -> String:
	var parts: Array[String] = []
	if flags & TF.SEED: parts.append("Se")
	if flags & TF.STRUCTURAL: parts.append("St")
	if flags & TF.JUNCTION: parts.append("Ju")
	if flags & TF.CAP: parts.append("Ca")
	return "+".join(parts) if parts.size() > 0 else "?"


func _size_flags_str(flags: int) -> String:
	var parts: Array[String] = []
	if flags & SF.SMALL: parts.append("S")
	if flags & SF.MEDIUM: parts.append("M")
	if flags & SF.LARGE: parts.append("L")
	return "+".join(parts) if parts.size() > 0 else "?"


func _vert_class_str(vert: int) -> String:
	match vert:
		1: return "↑"   # Points UP
		-1: return "↓"  # Points DOWN
		_: return "→"   # Horizontal


# === DEBUG ===

func print_stats():
	print("BuildingGenerator stats:")
	print("  Seeds: %d received, %d succeeded (%.1f%%)" % [
		_stats.seeds_received,
		_stats.seeds_succeeded,
		100.0 * _stats.seeds_succeeded / max(_stats.seeds_received, 1)
	])
	print("  Seed failures: %d overlap, %d no matching blocks" % [
		_stats.seeds_failed_overlap,
		_stats.seeds_failed_no_blocks
	])
	print("  Blocks placed: %d" % _stats.blocks_placed)
	print("  Rejects: %d overlap, %d no match, %d direction" % [
		_stats.overlap_rejects,
		_stats.no_match_rejects,
		_stats.direction_rejects
	])
	print("  Retries: %d rotation, %d block" % [
		_stats.rotation_retries,
		_stats.block_retries
	])
	
	var depths = _stats.depth_distribution.keys()
	depths.sort()
	if depths.size() > 0:
		var depth_str = ""
		for d in depths:
			depth_str += "d%s:%d " % [d, _stats.depth_distribution[d]]
		print("  Depth: %s" % depth_str.strip_edges())
	
	var types = _stats.type_distribution.keys()
	if types.size() > 0:
		types.sort()
		var type_str = ""
		for t in types:
			type_str += "%s:%d " % [t, _stats.type_distribution[t]]
		print("  Types: %s" % type_str.strip_edges())


func print_debug_stats():
	print_stats()
