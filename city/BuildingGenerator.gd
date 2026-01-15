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


func _ready():
	_load_block_library()


func reset_counter():
	_blocks_placed = 0


func _load_block_library():
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
				# Cache block metadata
				var instance = scene.instantiate()
				if instance is BuildingBlock:
					block_data.append({
						"scene": scene,
						"path": path,
						"type": instance.block_type,
						"can_spawn": instance.can_spawn_people,
						"weight": instance.spawn_weight,
						"min_biome": instance.min_biome,
						"max_biome": instance.max_biome,
						"connection_count": instance.get_connection_points().size()
					})
				instance.queue_free()
		file_name = dir.get_next()

	print("BuildingGenerator: Loaded %d blocks from %s" % [block_library.size(), blocks_folder])
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
func _grow_from_seed(position: Vector3, direction: Vector3, biome_idx: int, depth: int):
	# Hard limits
	if depth >= max_growth_depth:
		return
	if _blocks_placed >= max_blocks_total:
		return

	# Pick a block that fits this biome
	var valid_blocks = _get_valid_blocks(biome_idx, depth)
	if valid_blocks.is_empty():
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

	# Position the block - align first available connection to seed point
	var connections = block_instance.get_connection_points()
	if connections.is_empty():
		block_instance.global_position = position
	else:
		# Use first connection point as anchor
		var anchor = connections[0]
		# Rotate block to align connection with incoming direction
		var target_dir = -direction  # We want to connect TO the seed
		_align_block_to_direction(block_instance, anchor, position, target_dir)
		block_instance.mark_connection_used(anchor)

	# Maybe branch to other connections
	var remaining = block_instance.get_available_connections()
	for conn in remaining:
		if _rng.randf() < branch_probability or depth == 0:
			var world_pos = block_instance.get_connection_world_position(conn)
			var world_dir = block_instance.get_connection_world_direction(conn)
			block_instance.mark_connection_used(conn)
			_grow_from_seed(world_pos, world_dir, biome_idx, depth + 1)


# Align a block so its connection point is at target_pos facing target_dir
func _align_block_to_direction(block: BuildingBlock, conn: ConnectionPoint, target_pos: Vector3, target_dir: Vector3):
	# Get connection's local offset from block origin
	var local_offset = conn.position

	# Calculate rotation to align connection direction with target
	var conn_local_dir = -conn.basis.z  # Connection's forward direction
	var rotation_axis = conn_local_dir.cross(target_dir)

	if rotation_axis.length() > 0.001:
		var angle = conn_local_dir.angle_to(target_dir)
		block.rotate(rotation_axis.normalized(), angle)

	# Position block so connection point lands at target_pos
	var rotated_offset = block.basis * local_offset
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
