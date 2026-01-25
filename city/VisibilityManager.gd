# VisibilityManager.gd
# Global manager for visibility ranges and culling optimization
# Attach to your scene and configure distance tiers
class_name VisibilityManager
extends Node

signal visibility_updated(stats: Dictionary)

# Global visibility settings (applied to all building blocks)
@export_category("Distance Tiers")
@export var enable_visibility_ranges: bool = true
@export var max_visibility_distance: float = 800.0  # Hidden beyond this distance
@export var fade_mode: int = 1              # 0=Disabled, 1=Self fade, 2=Dependencies

@export_category("Auto-Apply")
@export var apply_on_ready: bool = true     # Apply to existing blocks on _ready
@export var apply_to_new_blocks: bool = true # Watch for new blocks and apply

@export_category("Performance")
@export var update_interval: float = 2.0    # How often to scan for new blocks
@export var batch_size: int = 100           # Blocks to process per frame during scan

# Reference to building container
var _building_container: Node3D
var _update_timer: float = 0.0
var _known_blocks: Dictionary = {}  # instance_id -> bool (tracked)

# Stats
var _stats = {
	"total_blocks": 0,
	"with_visibility_range": 0,
}


func _ready():
	# Try to find building container
	call_deferred("_find_building_container")
	
	if apply_on_ready:
		call_deferred("apply_to_all_blocks")


func _process(delta: float):
	if not apply_to_new_blocks:
		return
	
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_scan_for_new_blocks()


func _find_building_container():
	"""Find the Buildings container in the scene."""
	# Look for CityGenerator's buildings container
	var city_gen = get_parent().get_node_or_null("CityGenerator")
	if city_gen:
		_building_container = city_gen.get_node_or_null("Buildings")
	
	if not _building_container:
		# Try to find any node named "Buildings"
		_building_container = get_tree().root.find_child("Buildings", true, false)
	
	if _building_container:
		print("VisibilityManager: Found building container: %s" % _building_container.name)
	else:
		push_warning("VisibilityManager: Could not find Buildings container")


func set_building_container(container: Node3D):
	"""Manually set the building container."""
	_building_container = container


func apply_to_all_blocks():
	"""Apply visibility settings to all BuildingBlock nodes."""
	if not _building_container:
		_find_building_container()
	
	if not _building_container:
		push_warning("VisibilityManager: No building container set")
		return
	
	var count = 0
	_apply_to_children(_building_container, count)
	
	_stats.total_blocks = count
	_stats.with_visibility_range = count if enable_visibility_ranges else 0
	
	print("VisibilityManager: Applied visibility range to %d blocks (0-%.0fm)" % [
		count, max_visibility_distance
	])
	
	visibility_updated.emit(_stats)


func _apply_to_children(node: Node, count: int) -> int:
	"""Recursively apply visibility to BuildingBlock children."""
	for child in node.get_children():
		if child is BuildingBlock:
			_apply_to_block(child)
			_known_blocks[child.get_instance_id()] = true
			count += 1
		
		# Recurse into children (BuildingGenerator might have nested structure)
		count = _apply_to_children(child, count)
	
	return count


func _apply_to_block(block: BuildingBlock):
	"""Apply visibility settings to a single block."""
	if enable_visibility_ranges:
		# begin=0 means visible from 0m, end=max means hidden beyond max
		block.set_visibility_range(0.0, max_visibility_distance, fade_mode)
	else:
		block.disable_visibility_range()


func _scan_for_new_blocks():
	"""Scan for newly added blocks and apply visibility."""
	if not _building_container:
		return
	
	var new_count = 0
	_scan_children(_building_container, new_count)
	
	if new_count > 0:
		_stats.total_blocks += new_count
		if enable_visibility_ranges:
			_stats.with_visibility_range += new_count


func _scan_children(node: Node, new_count: int) -> int:
	"""Scan for new BuildingBlock children."""
	for child in node.get_children():
		if child is BuildingBlock:
			var id = child.get_instance_id()
			if not _known_blocks.has(id):
				_apply_to_block(child)
				_known_blocks[id] = true
				new_count += 1
		
		new_count = _scan_children(child, new_count)
	
	return new_count


func set_max_distance(distance: float):
	"""Update max visibility distance and reapply to all blocks."""
	max_visibility_distance = distance
	apply_to_all_blocks()


func toggle_visibility_ranges(enabled: bool):
	"""Enable or disable visibility ranges globally."""
	enable_visibility_ranges = enabled
	apply_to_all_blocks()


func get_stats() -> Dictionary:
	return _stats.duplicate()


# === UTILITY: Apply to spires and connectors too ===

func apply_to_spires(spires_container: Node3D, begin: float = 0.0, end: float = 2000.0):
	"""Apply visibility range to spire meshes."""
	var count = 0
	for spire in spires_container.get_children():
		count += _apply_visibility_to_meshes(spire, begin, end)
	print("VisibilityManager: Applied to %d spire meshes" % count)


func apply_to_connectors(connectors_container: Node3D, begin: float = 0.0, end: float = 1500.0):
	"""Apply visibility range to connector meshes."""
	var count = 0
	for connector in connectors_container.get_children():
		count += _apply_visibility_to_meshes(connector, begin, end)
	print("VisibilityManager: Applied to %d connector meshes" % count)


func _apply_visibility_to_meshes(node: Node, begin: float, end: float) -> int:
	"""Apply visibility range to all MeshInstance3D in a node tree."""
	var count = 0
	
	if node is MeshInstance3D:
		var mesh = node as MeshInstance3D
		mesh.visibility_range_begin = begin
		mesh.visibility_range_end = end
		mesh.visibility_range_fade_mode = fade_mode as GeometryInstance3D.VisibilityRangeFadeMode
		count += 1
	
	for child in node.get_children():
		count += _apply_visibility_to_meshes(child, begin, end)
	
	return count
