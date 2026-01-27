# BuildingGenerator.gd - Four-pass building generation with progress reporting
# Pass 1: Main structural growth (SEED → STRUCTURAL → JUNCTION)
# Pass 2: Functional blocks (spawners, POIs, refuel stations) - gameplay priority
# Pass 3: Decoration/caps on remaining open sockets - visual polish
# Pass 4: Spawn zones on remaining floor sockets - ensures people can spawn
class_name BuildingGenerator
extends Node3D

# Signals for progress reporting
signal generation_started(total_steps: int)
signal generation_progress(current_step: int, message: String)
signal generation_complete(stats: Dictionary)

# Shorthand for flag enums
const TF = ConnectionPoint.TypeFlags
const SF = ConnectionPoint.SizeFlags

# Block library
var block_library: Array[PackedScene] = []
var block_data: Array[Dictionary] = []

# Categorized block lists (populated during loading)
var _structural_blocks: Array[Dictionary] = []  # Has SEED or STRUCTURAL plugs
var _decoration_blocks: Array[Dictionary] = []  # Has CAP plugs (caps, antennas, etc.)
var _functional_blocks: Array[Dictionary] = []  # Gameplay blocks (spawners, POIs, etc.)

# Generation settings
@export var blocks_folder: String = "res://city/building/"
@export var functional_folder: String = "res://city/building/functional/"

@export_category("Pass 1: Structure")
@export var max_growth_depth: int = 5
@export var branch_probability: float = 0.5
@export var max_structural_blocks: int = 500

@export_category("Pass 2: Functional")
@export var functional_enabled: bool = true
@export var min_functional_blocks: int = 840  # Guaranteed minimum (tries harder to place)
@export var max_functional_blocks: int = 1260  # Allow many more
@export var functional_probability: float = 0.7  # Higher chance per eligible socket
@export var prefer_spawners: bool = true  # Prioritize spawner blocks over other functional
@export var spawner_weight: float = 3.0  # How much to favor spawners vs other functional (multiplier)

@export_category("Pass 3: Decoration")
@export var decoration_enabled: bool = true
@export var decoration_probability: float = 0.3  # Chance to decorate each open socket
@export var max_decoration_blocks: int = 200

@export_category("Pass 4: Spawn Zones")
@export var spawn_zones_enabled: bool = true
@export var spawn_zone_probability: float = 1.0  # Chance per unused floor socket
@export var spawn_zone_radius_small: float = 4.0
@export var spawn_zone_radius_medium: float = 8.0
@export var spawn_zone_radius_large: float = 12.0
@export var spawn_zone_max_people_per_meter: float = 0.5  # max_people = radius * this

@export_category("Performance")
@export var yield_every_n_blocks: int = 20  # Yield to main loop periodically
@export var overlap_margin: float = 0.5  # Smaller margin = less aggressive shrinking

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _placed_aabbs: Array[AABB] = []
var _growth_queue: Array[Dictionary] = []
var _placed_blocks: Array[BuildingBlock] = []  # Track for decoration pass
var _stats: Dictionary = {}
var _is_generating: bool = false
var _current_seed: int = 0


func _ready():
	_load_block_library()


func set_seed(seed_value: int):
	_current_seed = seed_value
	_rng.seed = seed_value


func get_seed() -> int:
	return _current_seed


func _shuffle_array(array: Array):
	# Fisher-Yates shuffle using seeded RNG
	for i in range(array.size() - 1, 0, -1):
		var j = _rng.randi() % (i + 1)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp


func reset():
	_placed_aabbs.clear()
	_growth_queue.clear()
	_placed_blocks.clear()
	_stats = {
		"blocks_placed": 0,
		"structural_placed": 0,
		"decoration_placed": 0,
		"functional_placed": 0,
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
		"open_sockets_before_decoration": 0,
		"sockets_decorated": 0,
		"open_sockets_before_functional": 0,
		"sockets_functional": 0,
		"spawners_placed": 0,
		"spawn_zones_created": 0,
		"floor_blocks_found": 0,
		"floor_sockets_available": 0,
	}
	for child in get_children():
		child.queue_free()


func reset_counter():
	reset()


func register_external_aabbs(aabbs: Array[AABB]):
	for aabb in aabbs:
		var safe_aabb = _make_safe_aabb(aabb)
		_placed_aabbs.append(safe_aabb)


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


# Main entry point - runs all four passes
func process_queue():
	if _is_generating:
		push_warning("BuildingGenerator: Already generating!")
		return

	_is_generating = true

	# Estimate total steps for progress
	var estimated_steps = _growth_queue.size() + (max_functional_blocks if functional_enabled else 0) + (max_decoration_blocks if decoration_enabled else 0)
	generation_started.emit(estimated_steps)

	print("BuildingGenerator: Starting generation...")
	print("  Seeds queued: %d" % _stats.seeds_received)
	print("  Max structural: %d, Max functional: %d, Max decoration: %d" % [max_structural_blocks, max_functional_blocks, max_decoration_blocks])

	# Pass 1: Structural growth
	await _run_structural_pass()

	# Pass 2: Functional (spawners, POIs, etc.) - gameplay priority
	if functional_enabled:
		await _run_functional_pass()

	# Pass 3: Decoration - visual polish on remaining sockets
	if decoration_enabled:
		await _run_decoration_pass()

	# Pass 4: Spawn zones on remaining floor sockets
	if spawn_zones_enabled:
		_run_spawn_zone_pass()

	_is_generating = false

	print("BuildingGenerator: Complete")
	print_stats()
	generation_complete.emit(_stats)


# Synchronous version for compatibility (blocks main thread)
func process_queue_sync():
	_is_generating = true
	_run_structural_pass_sync()
	if functional_enabled:
		_run_functional_pass_sync()
	if decoration_enabled:
		_run_decoration_pass_sync()
	if spawn_zones_enabled:
		_run_spawn_zone_pass()
	_is_generating = false
	print_stats()


# === PASS 1: STRUCTURAL ===

func _run_structural_pass():
	generation_progress.emit(0, "Starting structural pass...")
	
	var current_depth = 0
	var blocks_this_batch = 0
	
	while not _growth_queue.is_empty() and _stats.structural_placed < max_structural_blocks:
		var min_depth = 999
		for entry in _growth_queue:
			min_depth = mini(min_depth, entry.depth)
		
		if min_depth > current_depth:
			current_depth = min_depth
		
		if current_depth >= max_growth_depth:
			_growth_queue.clear()
			break
		
		# Process entries at current depth
		var entries_at_depth: Array[Dictionary] = []
		var remaining: Array[Dictionary] = []
		
		for entry in _growth_queue:
			if entry.depth == current_depth:
				entries_at_depth.append(entry)
			else:
				remaining.append(entry)
		
		_growth_queue = remaining
		_shuffle_array(entries_at_depth)
		
		for entry in entries_at_depth:
			if _stats.structural_placed >= max_structural_blocks:
				break
			
			_process_structural_entry(entry)
			blocks_this_batch += 1
			
			# Yield periodically for responsiveness
			if blocks_this_batch >= yield_every_n_blocks:
				generation_progress.emit(_stats.structural_placed, "Structural: depth %d, %d blocks" % [current_depth, _stats.structural_placed])
				await get_tree().process_frame
				blocks_this_batch = 0
	
	generation_progress.emit(_stats.structural_placed, "Structural pass complete: %d blocks" % _stats.structural_placed)


func _run_structural_pass_sync():
	var current_depth = 0
	
	while not _growth_queue.is_empty() and _stats.structural_placed < max_structural_blocks:
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
		_shuffle_array(entries_at_depth)
		
		for entry in entries_at_depth:
			if _stats.structural_placed >= max_structural_blocks:
				break
			_process_structural_entry(entry)


func _process_structural_entry(entry: Dictionary):
	var position: Vector3 = entry.pos
	var direction: Vector3 = entry.dir
	var biome_idx: int = entry.biome
	var depth: int = entry.depth
	var type_flags: int = entry.type_flags
	var size_flags: int = entry.size_flags
	var base_heading: float = entry.heading
	var is_seed: bool = entry.get("is_seed", false)
	
	var target_dir = -direction
	
	# Use structural blocks only for pass 1
	var valid_blocks = _get_matching_blocks(_structural_blocks, biome_idx, depth, type_flags, size_flags, target_dir)
	
	if valid_blocks.is_empty():
		_stats.no_match_rejects += 1
		if is_seed:
			_stats.seeds_failed_no_blocks += 1
		return
	
	var shuffled = valid_blocks.duplicate()
	_shuffle_array(shuffled)
	
	var placed_block: BuildingBlock = null
	
	for attempt_idx in range(mini(5, shuffled.size())):
		var block_info = shuffled[attempt_idx]
		var result = _try_place_block(block_info, position, target_dir, type_flags, size_flags, base_heading)
		
		if result.success:
			placed_block = result.block
			_placed_blocks.append(placed_block)
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
	
	_stats.blocks_placed += 1
	_stats.structural_placed += 1
	if is_seed:
		_stats.seeds_succeeded += 1
	
	var depth_key = str(depth)
	_stats.depth_distribution[depth_key] = _stats.depth_distribution.get(depth_key, 0) + 1
	_track_type_stats(type_flags)
	
	# Queue children (structural only in pass 1)
	_queue_structural_children(placed_block, biome_idx, depth)


func _queue_structural_children(block: BuildingBlock, biome_idx: int, parent_depth: int):
	var child_depth = parent_depth + 1
	if child_depth >= max_growth_depth:
		return
	
	var child_heading = block.rotation.y
	
	for conn in block.get_available_connections():
		if not conn.is_socket:
			continue
		
		# Skip CAP-only sockets (they're for decoration pass)
		if conn.type_flags == TF.CAP:
			continue
		
		# Skip small-only sockets (save for decoration)
		if conn.size_flags == SF.SMALL:
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


# === PASS 3: DECORATION ===

func _run_decoration_pass():
	generation_progress.emit(_stats.structural_placed, "Starting decoration pass...")
	
	# Collect all open sockets from placed blocks
	var open_sockets: Array[Dictionary] = []
	
	for block in _placed_blocks:
		if not is_instance_valid(block):
			continue
		
		var biome = block.get_meta("biome_idx", 0)
		
		for conn in block.get_available_connections():
			if not conn.is_socket:
				continue
			
			open_sockets.append({
				"block": block,
				"conn": conn,
				"biome": biome,
				"pos": block.get_connection_world_position(conn),
				"dir": block.get_connection_world_direction(conn),
				"heading": block.rotation.y,
			})
	
	_stats.open_sockets_before_decoration = open_sockets.size()
	print("  Decoration pass: %d open sockets found" % open_sockets.size())
	
	# Shuffle for variety
	_shuffle_array(open_sockets)
	
	var decorated = 0
	var blocks_this_batch = 0
	
	for socket_data in open_sockets:
		if decorated >= max_decoration_blocks:
			break
		
		# Probability check
		if _rng.randf() > decoration_probability:
			continue
		
		var conn: ConnectionPoint = socket_data.conn
		var block: BuildingBlock = socket_data.block
		
		if not is_instance_valid(block):
			continue
		
		# Try to place a decoration
		var target_dir = -socket_data.dir
		var valid_decorations = _get_matching_blocks(
			_decoration_blocks,
			socket_data.biome,
			max_growth_depth,  # Use max depth to prefer caps
			conn.type_flags | TF.CAP,  # Allow CAP to match anything
			conn.size_flags,
			target_dir
		)
		
		if valid_decorations.is_empty():
			continue
		
		var shuffled = valid_decorations.duplicate()
		_shuffle_array(shuffled)
		
		for deco_info in shuffled.slice(0, 3):  # Try up to 3
			var result = _try_place_block(
				deco_info,
				socket_data.pos,
				target_dir,
				conn.type_flags | TF.CAP,
				conn.size_flags,
				socket_data.heading
			)
			
			if result.success:
				block.mark_connection_used(conn)
				decorated += 1
				_stats.blocks_placed += 1
				_stats.decoration_placed += 1
				_stats.sockets_decorated += 1
				blocks_this_batch += 1
				
				if blocks_this_batch >= yield_every_n_blocks:
					generation_progress.emit(
						_stats.structural_placed + decorated,
						"Decorating: %d/%d" % [decorated, max_decoration_blocks]
					)
					await get_tree().process_frame
					blocks_this_batch = 0
				break
	
	generation_progress.emit(_stats.blocks_placed, "Decoration complete: %d added" % decorated)


func _run_decoration_pass_sync():
	var open_sockets: Array[Dictionary] = []
	
	for block in _placed_blocks:
		if not is_instance_valid(block):
			continue
		
		var biome = block.get_meta("biome_idx", 0)
		
		for conn in block.get_available_connections():
			if not conn.is_socket:
				continue
			
			open_sockets.append({
				"block": block,
				"conn": conn,
				"biome": biome,
				"pos": block.get_connection_world_position(conn),
				"dir": block.get_connection_world_direction(conn),
				"heading": block.rotation.y,
			})
	
	_stats.open_sockets_before_decoration = open_sockets.size()
	_shuffle_array(open_sockets)
	
	var decorated = 0
	
	for socket_data in open_sockets:
		if decorated >= max_decoration_blocks:
			break
		
		if _rng.randf() > decoration_probability:
			continue
		
		var conn: ConnectionPoint = socket_data.conn
		var block: BuildingBlock = socket_data.block
		
		if not is_instance_valid(block):
			continue
		
		var target_dir = -socket_data.dir
		var valid_decorations = _get_matching_blocks(
			_decoration_blocks,
			socket_data.biome,
			max_growth_depth,
			conn.type_flags | TF.CAP,
			conn.size_flags,
			target_dir
		)
		
		if valid_decorations.is_empty():
			continue
		
		var shuffled = valid_decorations.duplicate()
		_shuffle_array(shuffled)
		
		for deco_info in shuffled.slice(0, 3):
			var result = _try_place_block(
				deco_info,
				socket_data.pos,
				target_dir,
				conn.type_flags | TF.CAP,
				conn.size_flags,
				socket_data.heading
			)
			
			if result.success:
				block.mark_connection_used(conn)
				decorated += 1
				_stats.blocks_placed += 1
				_stats.decoration_placed += 1
				_stats.sockets_decorated += 1
				break


# === PASS 2: FUNCTIONAL ===

func _run_functional_pass():
	generation_progress.emit(_stats.blocks_placed, "Starting functional pass...")
	
	if _functional_blocks.is_empty():
		print("  Functional pass: No functional blocks loaded, skipping")
		return
	
	# Collect open sockets that could accept functional blocks
	var open_sockets: Array[Dictionary] = []
	
	for block in _placed_blocks:
		if not is_instance_valid(block):
			continue
		
		var biome = block.get_meta("biome_idx", 0)
		
		for conn in block.get_available_connections():
			if not conn.is_socket:
				continue
			
			open_sockets.append({
				"block": block,
				"conn": conn,
				"biome": biome,
				"pos": block.get_connection_world_position(conn),
				"dir": block.get_connection_world_direction(conn),
				"heading": block.rotation.y,
			})
	
	_stats.open_sockets_before_functional = open_sockets.size()
	print("  Functional pass: %d open sockets, %d functional blocks available" % [open_sockets.size(), _functional_blocks.size()])
	
	# Separate spawner blocks from other functional blocks
	var spawner_blocks: Array[Dictionary] = []
	var other_functional: Array[Dictionary] = []
	
	for func_block in _functional_blocks:
		if func_block.can_spawn:
			spawner_blocks.append(func_block)
		else:
			other_functional.append(func_block)
	
	print("  Functional blocks: %d spawners, %d other" % [spawner_blocks.size(), other_functional.size()])
	
	# Shuffle sockets
	_shuffle_array(open_sockets)
	
	var placed = 0
	var blocks_this_batch = 0
	var guaranteed_phase = true  # First phase: try to meet minimum
	
	for socket_data in open_sockets:
		if placed >= max_functional_blocks:
			break
		
		# After meeting minimum, apply probability
		if placed >= min_functional_blocks:
			guaranteed_phase = false
		
		if not guaranteed_phase and _rng.randf() > functional_probability:
			continue
		
		var conn: ConnectionPoint = socket_data.conn
		var block: BuildingBlock = socket_data.block
		
		if not is_instance_valid(block):
			continue
		
		var target_dir = -socket_data.dir
		
		# Choose block list based on preference and what's available
		var blocks_to_try: Array[Dictionary] = []
		if prefer_spawners and not spawner_blocks.is_empty():
			blocks_to_try = spawner_blocks
		elif not other_functional.is_empty():
			blocks_to_try = other_functional
		else:
			blocks_to_try = _functional_blocks
		
		var valid_blocks = _get_matching_blocks(
			blocks_to_try,
			socket_data.biome,
			max_growth_depth,
			conn.type_flags,
			conn.size_flags,
			target_dir
		)
		
		# Fallback to all functional if preferred type didn't match
		if valid_blocks.is_empty() and blocks_to_try != _functional_blocks:
			valid_blocks = _get_matching_blocks(
				_functional_blocks,
				socket_data.biome,
				max_growth_depth,
				conn.type_flags,
				conn.size_flags,
				target_dir
			)
		
		if valid_blocks.is_empty():
			continue
		
		var shuffled = valid_blocks.duplicate()
		_shuffle_array(shuffled)
		
		for func_info in shuffled.slice(0, 3):
			var result = _try_place_block(
				func_info,
				socket_data.pos,
				target_dir,
				conn.type_flags,
				conn.size_flags,
				socket_data.heading
			)
			
			if result.success:
				block.mark_connection_used(conn)
				placed += 1
				_stats.blocks_placed += 1
				_stats.functional_placed += 1
				_stats.sockets_functional += 1
				
				if func_info.can_spawn:
					_stats.spawners_placed += 1
				
				blocks_this_batch += 1
				
				if blocks_this_batch >= yield_every_n_blocks:
					generation_progress.emit(
						_stats.blocks_placed,
						"Functional: %d/%d (spawners: %d)" % [placed, max_functional_blocks, _stats.spawners_placed]
					)
					await get_tree().process_frame
					blocks_this_batch = 0
				break
	
	generation_progress.emit(_stats.blocks_placed, "Functional complete: %d added (%d spawners)" % [placed, _stats.spawners_placed])


func _run_functional_pass_sync():
	if _functional_blocks.is_empty():
		return
	
	var open_sockets: Array[Dictionary] = []
	
	for block in _placed_blocks:
		if not is_instance_valid(block):
			continue
		
		var biome = block.get_meta("biome_idx", 0)
		
		for conn in block.get_available_connections():
			if not conn.is_socket:
				continue
			
			open_sockets.append({
				"block": block,
				"conn": conn,
				"biome": biome,
				"pos": block.get_connection_world_position(conn),
				"dir": block.get_connection_world_direction(conn),
				"heading": block.rotation.y,
			})
	
	_stats.open_sockets_before_functional = open_sockets.size()
	
	var spawner_blocks: Array[Dictionary] = []
	var other_functional: Array[Dictionary] = []
	
	for func_block in _functional_blocks:
		if func_block.can_spawn:
			spawner_blocks.append(func_block)
		else:
			other_functional.append(func_block)
	
	_shuffle_array(open_sockets)
	
	var placed = 0
	var guaranteed_phase = true
	
	for socket_data in open_sockets:
		if placed >= max_functional_blocks:
			break
		
		if placed >= min_functional_blocks:
			guaranteed_phase = false
		
		if not guaranteed_phase and _rng.randf() > functional_probability:
			continue
		
		var conn: ConnectionPoint = socket_data.conn
		var block: BuildingBlock = socket_data.block
		
		if not is_instance_valid(block):
			continue
		
		var target_dir = -socket_data.dir
		
		var blocks_to_try: Array[Dictionary] = []
		if prefer_spawners and not spawner_blocks.is_empty():
			blocks_to_try = spawner_blocks
		elif not other_functional.is_empty():
			blocks_to_try = other_functional
		else:
			blocks_to_try = _functional_blocks
		
		var valid_blocks = _get_matching_blocks(
			blocks_to_try,
			socket_data.biome,
			max_growth_depth,
			conn.type_flags,
			conn.size_flags,
			target_dir
		)
		
		if valid_blocks.is_empty() and blocks_to_try != _functional_blocks:
			valid_blocks = _get_matching_blocks(
				_functional_blocks,
				socket_data.biome,
				max_growth_depth,
				conn.type_flags,
				conn.size_flags,
				target_dir
			)
		
		if valid_blocks.is_empty():
			continue
		
		var shuffled = valid_blocks.duplicate()
		_shuffle_array(shuffled)
		
		for func_info in shuffled.slice(0, 3):
			var result = _try_place_block(
				func_info,
				socket_data.pos,
				target_dir,
				conn.type_flags,
				conn.size_flags,
				socket_data.heading
			)
			
			if result.success:
				block.mark_connection_used(conn)
				placed += 1
				_stats.blocks_placed += 1
				_stats.functional_placed += 1
				_stats.sockets_functional += 1

				if func_info.can_spawn:
					_stats.spawners_placed += 1
				break


# === PASS 4: SPAWN ZONES ===

func _run_spawn_zone_pass():
	# Find all floor-type blocks and add SpawnZones to unused VERTICAL STRUCTURAL sockets
	# Only creates zones on sockets pointing UP (direction.y > 0.7)

	var floor_blocks: Array[BuildingBlock] = []

	# Debug: count block types
	var type_counts: Dictionary = {}
	for block in _placed_blocks:
		if not is_instance_valid(block):
			continue
		var bt = block.block_type
		type_counts[bt] = type_counts.get(bt, 0) + 1
		# FLOOR = 1 in BuildingBlock.BlockType
		if bt == BuildingBlock.BlockType.FLOOR:
			floor_blocks.append(block)

	print("  Spawn Zone pass: placed block types: %s" % str(type_counts))

	_stats.floor_blocks_found = floor_blocks.size()
	print("  Spawn Zone pass: %d floor blocks found" % floor_blocks.size())

	if floor_blocks.is_empty():
		return

	var zones_created = 0
	var sockets_checked = 0
	var skipped_horizontal = 0
	var skipped_non_structural = 0

	for block in floor_blocks:
		if not is_instance_valid(block):
			continue

		# Get all unused sockets on this floor block
		var available_conns = block.get_available_connections()

		for conn in available_conns:
			if not conn.is_socket:
				continue

			sockets_checked += 1

			# Get world direction of socket
			var world_dir = block.get_connection_world_direction(conn)

			# Only vertical sockets (pointing UP) - direction.y > 0.7 means mostly upward
			if world_dir.y < 0.7:
				skipped_horizontal += 1
				continue

			# Only STRUCTURAL type sockets (not junction/cap only)
			if not (conn.type_flags & TF.STRUCTURAL):
				skipped_non_structural += 1
				continue

			# Probability check
			if _rng.randf() > spawn_zone_probability:
				continue

			# Determine radius based on size flags
			var zone_radius: float = spawn_zone_radius_medium  # default
			if conn.size_flags & SF.LARGE:
				zone_radius = spawn_zone_radius_large
			elif conn.size_flags & SF.SMALL:
				zone_radius = spawn_zone_radius_small

			# Create the SpawnZone
			var zone = SpawnZone.new()
			zone.radius = zone_radius
			zone.max_people = int(zone_radius * spawn_zone_max_people_per_meter)
			zone.max_people = maxi(zone.max_people, 1)  # At least 1 person

			# Add to tree first (required before setting global_position)
			add_child(zone)

			# Position at the socket location, offset upward slightly
			var socket_world_pos = block.get_connection_world_position(conn)
			zone.global_position = socket_world_pos + Vector3(0, 0.1, 0)

			# Mark the socket as used so decoration pass doesn't try to use it
			block.mark_connection_used(conn)

			zones_created += 1

	_stats.floor_sockets_available = sockets_checked
	_stats.spawn_zones_created = zones_created
	print("  Spawn Zone pass: %d zones from %d sockets (skipped %d horizontal, %d non-structural)" % [
		zones_created, sockets_checked, skipped_horizontal, skipped_non_structural
	])


## Register all spawn zones with a PeopleManager (call if automatic registration failed)
func register_spawn_zones_with(manager: Node):
	var count = 0
	for child in get_children():
		if child is SpawnZone and not child.registered:
			manager.register_zone(child)
			child.registered = true
			count += 1
	print("BuildingGenerator: Manually registered %d spawn zones" % count)
	return count


## Get all spawn zones created by this generator
func get_spawn_zones() -> Array[SpawnZone]:
	var zones: Array[SpawnZone] = []
	for child in get_children():
		if child is SpawnZone:
			zones.append(child)
	return zones


# === BLOCK PLACEMENT ===

func _try_place_block(block_info: Dictionary, position: Vector3, target_dir: Vector3,
					  required_types: int, required_sizes: int, base_heading: float) -> Dictionary:
	var scene: PackedScene = block_info.scene
	var instance = scene.instantiate() as BuildingBlock
	if not instance:
		return {"success": false, "reason": "instantiate_failed"}
	
	add_child(instance)
	
	var anchor = _find_matching_plug(instance, required_types, required_sizes, target_dir)
	if anchor == null:
		instance.queue_free()
		return {"success": false, "reason": "direction"}
	
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
		if (conn.type_flags & required_types) == 0:
			continue
		if (conn.size_flags & required_sizes) == 0:
			continue
		if not _direction_compatible(conn, target_dir):
			continue
		return conn
	return null


func _direction_compatible(conn: ConnectionPoint, target_dir: Vector3) -> bool:
	var local_dir = -conn.basis.z
	var plug_vertical = _classify_vertical(local_dir)
	var target_vertical = _classify_vertical(target_dir)
	return plug_vertical == target_vertical


func _classify_vertical(dir: Vector3) -> int:
	if dir.y > 0.7:
		return 1
	elif dir.y < -0.7:
		return -1
	return 0


func _get_matching_blocks(block_list: Array, biome_idx: int, depth: int, type_flags: int, size_flags: int, target_dir: Vector3) -> Array:
	var valid: Array = []
	var target_vertical = _classify_vertical(target_dir)
	
	for data in block_list:
		if biome_idx < data.min_biome or biome_idx > data.max_biome:
			continue
		
		var has_match = false
		for plug in data.get("plugs", []):
			var types_match = (plug.type_flags & type_flags) != 0
			var sizes_match = (plug.size_flags & size_flags) != 0
			var dir_match = plug.vertical_class == target_vertical
			if types_match and sizes_match and dir_match:
				has_match = true
				break
		
		if has_match:
			valid.append(data)
	
	return valid


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


func _track_type_stats(flags: int):
	if flags & TF.SEED:
		_stats.type_distribution["SEED"] = _stats.type_distribution.get("SEED", 0) + 1
	if flags & TF.STRUCTURAL:
		_stats.type_distribution["STRUCTURAL"] = _stats.type_distribution.get("STRUCTURAL", 0) + 1
	if flags & TF.JUNCTION:
		_stats.type_distribution["JUNCTION"] = _stats.type_distribution.get("JUNCTION", 0) + 1
	if flags & TF.CAP:
		_stats.type_distribution["CAP"] = _stats.type_distribution.get("CAP", 0) + 1


# === AABB UTILITIES (with safety checks) ===

func _make_safe_aabb(aabb: AABB) -> AABB:
	# Ensure positive size and minimum dimensions
	var pos = aabb.position
	var size = aabb.size
	
	# Fix negative sizes
	if size.x < 0:
		pos.x += size.x
		size.x = -size.x
	if size.y < 0:
		pos.y += size.y
		size.y = -size.y
	if size.z < 0:
		pos.z += size.z
		size.z = -size.z
	
	# Ensure minimum size (avoid degenerate AABBs)
	size.x = maxf(size.x, 0.1)
	size.y = maxf(size.y, 0.1)
	size.z = maxf(size.z, 0.1)
	
	return AABB(pos, size)


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
	
	return _make_safe_aabb(combined_aabb)


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
	return _make_safe_aabb(result)


func _overlaps_existing(new_aabb: AABB) -> bool:
	var safe_aabb = _make_safe_aabb(new_aabb)
	
	# Only shrink if large enough
	var test_aabb = safe_aabb
	if safe_aabb.size.x > overlap_margin * 2 and safe_aabb.size.y > overlap_margin * 2 and safe_aabb.size.z > overlap_margin * 2:
		test_aabb = safe_aabb.grow(-overlap_margin)
		test_aabb = _make_safe_aabb(test_aabb)  # Safety check after grow
	
	for existing in _placed_aabbs:
		if test_aabb.intersects(existing):
			return true
	return false


# === BLOCK LIBRARY ===

func _load_block_library():
	print("BuildingGenerator: Loading blocks...")
	block_library.clear()
	block_data.clear()
	_structural_blocks.clear()
	_decoration_blocks.clear()
	_functional_blocks.clear()
	
	# Load main blocks folder
	_load_blocks_from_folder(blocks_folder, false)
	
	# Load functional blocks folder (if exists)
	if DirAccess.dir_exists_absolute(functional_folder):
		_load_blocks_from_folder(functional_folder, true)
	else:
		print("  Functional folder not found: %s (skipping)" % functional_folder)
	
	print("BuildingGenerator: Loaded %d blocks (%d structural, %d decoration, %d functional)" % [
		block_library.size(), _structural_blocks.size(), _decoration_blocks.size(), _functional_blocks.size()
	])
	_print_block_summary()


func _load_blocks_from_folder(folder_path: String, is_functional_folder: bool):
	var dir = DirAccess.open(folder_path)
	if not dir:
		push_error("BuildingGenerator: Cannot open folder: %s" % folder_path)
		return
	
	var folder_name = folder_path.get_file()
	if folder_name.is_empty():
		folder_name = folder_path.trim_suffix("/").get_file()
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			var path = folder_path + file_name
			var scene = load(path) as PackedScene
			if scene:
				block_library.append(scene)
				var instance = scene.instantiate()
				if instance is BuildingBlock:
					var data = _analyze_block(instance, scene, path, is_functional_folder)
					block_data.append(data)
					
					# Categorize - blocks can be in multiple categories
					# Structural blocks: have SEED/STRUCTURAL/JUNCTION plugs (main building pieces)
					# Functional blocks: have can_spawn_people OR are in functional folder
					# Decoration blocks: have CAP plugs or are CAP type
					if data.is_structural:
						_structural_blocks.append(data)
					if data.is_decoration:
						_decoration_blocks.append(data)
					if is_functional_folder or data.is_functional:
						_functional_blocks.append(data)
				instance.queue_free()
		file_name = dir.get_next()


func _analyze_block(instance: BuildingBlock, scene: PackedScene, path: String, force_functional: bool = false) -> Dictionary:
	var plugs: Array[Dictionary] = []
	var sockets: Array[Dictionary] = []
	
	var has_structural_plug = false
	var has_cap_plug = false
	
	for conn in instance.get_connection_points():
		var local_dir = -conn.basis.z
		var vert_class = _classify_vertical(local_dir)
		
		var info = {
			"type_flags": conn.type_flags,
			"size_flags": conn.size_flags,
			"rotation_mode": conn.rotation_mode,
			"vertical_class": vert_class,
		}
		
		if conn.is_plug:
			plugs.append(info)
			if conn.type_flags & (TF.SEED | TF.STRUCTURAL | TF.JUNCTION):
				has_structural_plug = true
			if conn.type_flags & TF.CAP:
				has_cap_plug = true
		
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
		"is_structural": has_structural_plug,
		"is_decoration": has_cap_plug or (instance.block_type == BuildingBlock.BlockType.CAP),
		"is_functional": force_functional or instance.can_spawn_people,
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
		
		var category = ""
		if data.is_functional:
			if data.can_spawn:
				category = " [FUNC:SPAWN]"
			else:
				category = " [FUNC]"
		elif data.is_structural and data.is_decoration:
			category = " [STRUCT+DECO]"
		elif data.is_structural:
			category = " [STRUCT]"
		elif data.is_decoration:
			category = " [DECO]"
		
		print("  %s%s: plugs=[%s]" % [
			data.path.get_file(),
			category,
			", ".join(plug_strs) if plug_strs.size() > 0 else "none"
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
		1: return "↑"
		-1: return "↓"
		_: return "→"


# === DEBUG ===

func print_stats():
	print("BuildingGenerator stats:")
	print("  Seeds: %d received, %d succeeded (%.1f%%)" % [
		_stats.seeds_received,
		_stats.seeds_succeeded,
		100.0 * _stats.seeds_succeeded / max(_stats.seeds_received, 1)
	])
	print("  Blocks: %d total (%d structural + %d functional + %d decoration)" % [
		_stats.blocks_placed,
		_stats.structural_placed,
		_stats.get("functional_placed", 0),
		_stats.decoration_placed
	])
	if _stats.get("functional_placed", 0) > 0:
		print("  Functional: %d placed (%d spawners) from %d open sockets" % [
			_stats.get("functional_placed", 0),
			_stats.get("spawners_placed", 0),
			_stats.get("open_sockets_before_functional", 0)
		])
	print("  Decoration: %d/%d open sockets decorated" % [
		_stats.sockets_decorated,
		_stats.open_sockets_before_decoration
	])
	if _stats.get("spawn_zones_created", 0) > 0 or _stats.get("floor_blocks_found", 0) > 0:
		print("  Spawn Zones: %d created from %d floor blocks (%d sockets checked)" % [
			_stats.get("spawn_zones_created", 0),
			_stats.get("floor_blocks_found", 0),
			_stats.get("floor_sockets_available", 0)
		])
	print("  Rejects: %d overlap, %d no match, %d direction" % [
		_stats.overlap_rejects,
		_stats.no_match_rejects,
		_stats.direction_rejects
	])
	
	var depths = _stats.depth_distribution.keys()
	depths.sort()
	if depths.size() > 0:
		var depth_str = ""
		for d in depths:
			depth_str += "d%s:%d " % [d, _stats.depth_distribution[d]]
		print("  Depth: %s" % depth_str.strip_edges())


func print_debug_stats():
	print_stats()
