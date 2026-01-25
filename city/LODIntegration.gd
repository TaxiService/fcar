# LODIntegration.gd
# Wires together the impostor generation, LOD management, and visibility systems
# Attach this to the VisibilityManager node (or as sibling to CityGenerator)
class_name LODIntegration
extends Node

# References (auto-found or manually assigned)
@export var city_generator_path: NodePath
@export var impostor_generator_path: NodePath
@export var lod_manager_path: NodePath
@export var loading_screen_path: NodePath

# Settings
@export var auto_find_nodes: bool = true
@export var generate_impostors_on_start: bool = true
@export var show_loading_screen: bool = true

# Node references
var city_generator: Node
var building_generator: Node
var impostor_generator: BuildingImpostorGenerator
var lod_manager: BuildingLODManager
var loading_screen: ImpostorLoadingScreen

# State
var _impostors_ready: bool = false
var _camera: Camera3D


func _ready():
	if auto_find_nodes:
		call_deferred("_find_nodes")
	else:
		call_deferred("_setup_from_paths")


func _find_nodes():
	# Find CityGenerator
	city_generator = _find_node_by_class(get_tree().root, "CityGenerator")
	if city_generator:
		print("LODIntegration: Found CityGenerator")
		building_generator = city_generator.get_node_or_null("Buildings/BuildingGenerator")
		if building_generator:
			print("LODIntegration: Found BuildingGenerator")
	
	# Find ImpostorGenerator (check children first, then siblings, then scene)
	impostor_generator = _find_child_by_class(self, "BuildingImpostorGenerator")
	if not impostor_generator:
		impostor_generator = _find_child_by_class(get_parent(), "BuildingImpostorGenerator")
	if not impostor_generator:
		impostor_generator = _find_node_by_class(get_tree().root, "BuildingImpostorGenerator")
	if impostor_generator:
		print("LODIntegration: Found BuildingImpostorGenerator")
	
	# Find LODManager
	lod_manager = _find_child_by_class(self, "BuildingLODManager")
	if not lod_manager:
		lod_manager = _find_child_by_class(get_parent(), "BuildingLODManager")
	if not lod_manager:
		lod_manager = _find_node_by_class(get_tree().root, "BuildingLODManager")
	if lod_manager:
		print("LODIntegration: Found BuildingLODManager")
	
	# Find or create loading screen
	loading_screen = _find_node_by_class(get_tree().root, "ImpostorLoadingScreen")
	if not loading_screen and show_loading_screen:
		loading_screen = ImpostorLoadingScreen.new()
		loading_screen.name = "ImpostorLoadingScreen"
		get_tree().root.add_child(loading_screen)
		print("LODIntegration: Created ImpostorLoadingScreen")
	
	# Set up connections
	_setup_connections()
	
	# Start impostor generation if enabled
	if generate_impostors_on_start:
		call_deferred("_start_impostor_generation")


func _setup_from_paths():
	if city_generator_path:
		city_generator = get_node_or_null(city_generator_path)
	if impostor_generator_path:
		impostor_generator = get_node_or_null(impostor_generator_path)
	if lod_manager_path:
		lod_manager = get_node_or_null(lod_manager_path)
	if loading_screen_path:
		loading_screen = get_node_or_null(loading_screen_path)
	
	_setup_connections()
	
	if generate_impostors_on_start:
		call_deferred("_start_impostor_generation")


func _setup_connections():
	# Connect loading screen to generator
	if loading_screen and impostor_generator:
		loading_screen.connect_to_generator(impostor_generator)
	
	# Connect generator completion to LOD manager setup
	if impostor_generator:
		if not impostor_generator.generation_complete.is_connected(_on_impostors_generated):
			impostor_generator.generation_complete.connect(_on_impostors_generated)
	
	# Try to find camera
	_find_camera()


func _find_camera():
	# Try to find FCar's camera first
	var fcar = _find_node_by_name(get_tree().root, "FCar")
	if fcar:
		_camera = fcar.get_node_or_null("Camera3D")
		if not _camera:
			# Try to find camera as child anywhere
			_camera = _find_child_by_class(fcar, "Camera3D")
	
	# Fallback to FreeCam
	if not _camera:
		var freecam = _find_node_by_name(get_tree().root, "FreeCam")
		if freecam and freecam is Camera3D:
			_camera = freecam
	
	# Last resort: any Camera3D
	if not _camera:
		_camera = _find_node_by_class(get_tree().root, "Camera3D")
	
	if _camera and lod_manager:
		lod_manager.set_camera(_camera)
		print("LODIntegration: Set camera for LOD manager")


func _start_impostor_generation():
	if not impostor_generator:
		push_warning("LODIntegration: No ImpostorGenerator found")
		return
	
	if not building_generator:
		push_warning("LODIntegration: No BuildingGenerator found")
		return
	
	# Get block library from BuildingGenerator
	var block_library: Array[PackedScene] = []
	
	if building_generator.has_method("get_block_library"):
		block_library = building_generator.get_block_library()
	elif "block_library" in building_generator:
		block_library = building_generator.block_library
	
	if block_library.is_empty():
		push_warning("LODIntegration: Block library is empty")
		return
	
	print("LODIntegration: Starting impostor generation for %d blocks" % block_library.size())
	
	# Generate impostors
	await impostor_generator.generate_impostors_for_library(block_library)


func _on_impostors_generated(impostor_data: Dictionary):
	print("LODIntegration: Impostors ready! (%d types)" % impostor_data.size())
	_impostors_ready = true
	
	# Pass data to LOD manager
	if lod_manager:
		lod_manager.set_impostor_data(impostor_data)
	
	# Connect to BuildingGenerator to register new blocks
	_connect_to_block_placement()
	
	# Register any existing blocks
	_register_existing_blocks()
	
	# Make sure camera is set
	_find_camera()


func _connect_to_block_placement():
	if not building_generator:
		return
	
	# Try to connect to block_placed signal if it exists
	if building_generator.has_signal("block_placed"):
		if not building_generator.block_placed.is_connected(_on_block_placed):
			building_generator.block_placed.connect(_on_block_placed)
			print("LODIntegration: Connected to block_placed signal")


func _on_block_placed(block: Node3D, block_path: String):
	if lod_manager and _impostors_ready:
		lod_manager.register_block(block, block_path)


func _register_existing_blocks():
	"""Register any blocks that were placed before impostors were ready."""
	if not lod_manager or not building_generator:
		return
	
	var count = 0
	for child in building_generator.get_children():
		if child is BuildingBlock:
			# Try to get the block's scene path
			var scene_path = child.scene_file_path
			if scene_path and impostor_generator.impostor_data.has(scene_path):
				lod_manager.register_block(child, scene_path)
				count += 1
	
	if count > 0:
		print("LODIntegration: Registered %d existing blocks with LOD manager" % count)


# === Utility functions ===

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if _node_is_class(node, class_name_str):
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


func _find_child_by_class(node: Node, class_name_str: String) -> Node:
	for child in node.get_children():
		if _node_is_class(child, class_name_str):
			return child
	return null


func _find_node_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, node_name)
		if found:
			return found
	return null


func _node_is_class(node: Node, class_name_str: String) -> bool:
	if node.get_script():
		var script = node.get_script()
		if script.get_global_name() == class_name_str:
			return true
	return node.get_class() == class_name_str


# === Public API ===

func is_ready() -> bool:
	return _impostors_ready


func get_stats() -> Dictionary:
	var stats = {
		"impostors_ready": _impostors_ready,
		"impostor_count": 0,
		"lod_stats": {},
	}
	
	if impostor_generator:
		stats.impostor_count = impostor_generator.impostor_data.size()
	
	if lod_manager:
		stats.lod_stats = lod_manager.get_stats()
	
	return stats


func force_lod_update():
	if lod_manager:
		lod_manager.force_update_all()
