# BuildingLODManager.gd
# Manages LOD swapping between 3D building blocks and 2D impostors
# Tracks all placed blocks and swaps them based on camera distance
class_name BuildingLODManager
extends Node

signal lod_stats_updated(stats: Dictionary)

# Distance thresholds
@export var impostor_distance: float = 500.0  # Switch to impostor beyond this
@export var hysteresis: float = 50.0  # Prevents rapid switching at boundary
@export var update_interval: float = 0.5  # How often to check distances
@export var batch_size: int = 50  # How many blocks to process per update

# Impostor data (from BuildingImpostorGenerator)
var impostor_data: Dictionary = {}  # block_path -> {texture, size, angle_count}

# Tracked blocks: Array of {block: Node3D, impostor: BuildingImpostor, path: String, is_impostor: bool}
var _tracked_blocks: Array[Dictionary] = []

# State
var _update_timer: float = 0.0
var _current_batch_index: int = 0
var _camera: Camera3D
var _impostor_container: Node3D

# Stats
var _stats = {
	"total_tracked": 0,
	"showing_3d": 0,
	"showing_impostor": 0,
	"last_update_ms": 0.0,
}


func _ready():
	# Create container for impostors
	_impostor_container = Node3D.new()
	_impostor_container.name = "ImpostorContainer"
	add_child(_impostor_container)


func _process(delta: float):
	_update_timer += delta
	
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_process_lod_batch()


func set_impostor_data(data: Dictionary):
	"""Set the impostor texture data from BuildingImpostorGenerator."""
	impostor_data = data
	print("BuildingLODManager: Loaded impostor data for %d block types" % data.size())


func register_block(block: Node3D, block_path: String):
	"""
	Register a placed building block for LOD management.
	Call this for each block placed by BuildingGenerator.
	"""
	if not impostor_data.has(block_path):
		# No impostor available for this block type
		return
	
	var entry = {
		"block": block,
		"impostor": null,  # Created lazily when needed
		"path": block_path,
		"is_impostor": false,
		"position": block.global_position,
	}
	
	_tracked_blocks.append(entry)
	_stats.total_tracked = _tracked_blocks.size()


func unregister_block(block: Node3D):
	"""Remove a block from LOD tracking."""
	for i in range(_tracked_blocks.size() - 1, -1, -1):
		var entry = _tracked_blocks[i]
		if entry.block == block:
			# Clean up impostor if exists
			if entry.impostor and is_instance_valid(entry.impostor):
				entry.impostor.queue_free()
			_tracked_blocks.remove_at(i)
			break
	
	_stats.total_tracked = _tracked_blocks.size()


func clear_all():
	"""Remove all tracked blocks and impostors."""
	for entry in _tracked_blocks:
		if entry.impostor and is_instance_valid(entry.impostor):
			entry.impostor.queue_free()
	
	_tracked_blocks.clear()
	_stats.total_tracked = 0
	_stats.showing_3d = 0
	_stats.showing_impostor = 0


func set_camera(camera: Camera3D):
	"""Set the camera to use for distance calculations."""
	_camera = camera


func _process_lod_batch():
	"""Process a batch of blocks for LOD switching."""
	if _tracked_blocks.is_empty() or not _camera:
		return
	
	var start_time = Time.get_ticks_msec()
	var camera_pos = _camera.global_position
	
	# Process batch
	var count = 0
	var showing_3d = 0
	var showing_impostor = 0
	
	while count < batch_size and _current_batch_index < _tracked_blocks.size():
		var entry = _tracked_blocks[_current_batch_index]
		
		# Skip invalid entries
		if not is_instance_valid(entry.block):
			_tracked_blocks.remove_at(_current_batch_index)
			continue
		
		# Calculate distance
		var dist = camera_pos.distance_to(entry.position)
		
		# Determine desired state with hysteresis
		var should_be_impostor: bool
		if entry.is_impostor:
			should_be_impostor = dist > (impostor_distance - hysteresis)
		else:
			should_be_impostor = dist > (impostor_distance + hysteresis)
		
		# Switch if needed
		if should_be_impostor != entry.is_impostor:
			_switch_lod(entry, should_be_impostor)
		
		# Count
		if entry.is_impostor:
			showing_impostor += 1
		else:
			showing_3d += 1
		
		_current_batch_index += 1
		count += 1
	
	# Wrap around
	if _current_batch_index >= _tracked_blocks.size():
		_current_batch_index = 0
		# Update stats at end of full cycle
		_stats.showing_3d = showing_3d
		_stats.showing_impostor = showing_impostor
	
	_stats.last_update_ms = Time.get_ticks_msec() - start_time
	lod_stats_updated.emit(_stats)


func _switch_lod(entry: Dictionary, to_impostor: bool):
	"""Switch a block between 3D and impostor representation."""
	if to_impostor:
		# Switch to impostor
		if not entry.impostor:
			# Create impostor lazily
			var data = impostor_data.get(entry.path, {})
			if data.is_empty():
				return
			
			entry.impostor = BuildingImpostor.create_from_data(data, entry.path)
			_impostor_container.add_child(entry.impostor)
		
		# Position impostor at block center
		entry.impostor.global_position = entry.position
		entry.impostor.visible = true
		
		# Hide 3D block (don't free - we might need it again)
		entry.block.visible = false
		
		# Disable processing on 3D block for performance
		entry.block.set_process(false)
		entry.block.set_physics_process(false)
		
	else:
		# Switch to 3D
		entry.block.visible = true
		entry.block.set_process(true)
		entry.block.set_physics_process(true)
		
		# Hide impostor (keep it for later)
		if entry.impostor:
			entry.impostor.visible = false
	
	entry.is_impostor = to_impostor


func force_update_all():
	"""Force immediate update of all blocks (expensive!)."""
	if not _camera:
		return
	
	var camera_pos = _camera.global_position
	
	for entry in _tracked_blocks:
		if not is_instance_valid(entry.block):
			continue
		
		var dist = camera_pos.distance_to(entry.position)
		var should_be_impostor = dist > impostor_distance
		
		if should_be_impostor != entry.is_impostor:
			_switch_lod(entry, should_be_impostor)


func get_stats() -> Dictionary:
	return _stats.duplicate()


func print_stats():
	print("BuildingLODManager stats:")
	print("  Total tracked: %d" % _stats.total_tracked)
	print("  Showing 3D: %d" % _stats.showing_3d)
	print("  Showing impostor: %d" % _stats.showing_impostor)
	print("  Last update: %.2f ms" % _stats.last_update_ms)
