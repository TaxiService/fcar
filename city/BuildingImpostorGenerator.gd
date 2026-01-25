# BuildingImpostorGenerator.gd
# Generates 8-angle sprite sheets for building blocks (like classic Doom sprites)
# Run this once during loading to create impostor textures for all block types
class_name BuildingImpostorGenerator
extends Node

signal generation_started(block_count: int)
signal generation_progress(current: int, block_name: String, preview_texture: ImageTexture)
signal generation_complete(impostor_data: Dictionary)

# Render settings
@export var sprite_size: int = 128  # Size of each sprite (128x128)
@export var angle_count: int = 8  # Number of angles (8 = every 45 degrees)
@export var render_scale: float = 1.0  # Scale factor for rendering
@export var background_color: Color = Color(0, 0, 0, 0)  # Transparent background
@export var camera_distance_multiplier: float = 2.5  # How far camera is from block

# The viewport used for rendering
var _viewport: SubViewport
var _camera: Camera3D
var _light: DirectionalLight3D
var _block_container: Node3D
var _is_setup: bool = false

# Generated data: { "block_path": { "texture": ImageTexture, "size": Vector3 } }
var impostor_data: Dictionary = {}


func _ready():
	# Defer setup to avoid issues with viewport in _ready
	call_deferred("_setup_render_viewport")


func _setup_render_viewport():
	if _is_setup:
		return
	
	# Create SubViewport for offscreen rendering
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(sprite_size, sprite_size)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.own_world_3d = true  # Isolated rendering
	add_child(_viewport)
	
	# Create camera
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	
	# Create directional light (matches main scene lighting roughly)
	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-45, -45, 0)
	_light.light_energy = 1.2
	_viewport.add_child(_light)
	
	# Ambient light for softer shadows
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	
	# Container for the block being rendered
	_block_container = Node3D.new()
	_viewport.add_child(_block_container)
	
	_is_setup = true
	print("BuildingImpostorGenerator: Render viewport ready")


func generate_impostors_for_library(block_scenes: Array[PackedScene]) -> Dictionary:
	"""
	Generate impostor sprite sheets for all block types.
	Returns dictionary mapping block path to impostor data.
	"""
	# Ensure viewport is set up
	if not _is_setup:
		_setup_render_viewport()
		await get_tree().process_frame
	
	impostor_data.clear()
	
	generation_started.emit(block_scenes.size())
	print("BuildingImpostorGenerator: Generating impostors for %d block types..." % block_scenes.size())
	
	for i in range(block_scenes.size()):
		var scene = block_scenes[i]
		var path = scene.resource_path
		
		var data = await _generate_impostor_for_block(scene)
		if data and data.has("texture"):
			impostor_data[path] = data
			# Emit progress with the generated texture for preview
			generation_progress.emit(i + 1, path.get_file(), data.texture)
		else:
			generation_progress.emit(i + 1, path.get_file(), null)
		
		# Yield to prevent freezing and allow UI update
		await get_tree().process_frame
	
	print("BuildingImpostorGenerator: Generated %d impostor sheets" % impostor_data.size())
	generation_complete.emit(impostor_data)
	
	return impostor_data


func _generate_impostor_for_block(scene: PackedScene) -> Dictionary:
	"""Generate an 8-angle sprite sheet for a single block type."""
	
	# Instantiate the block
	var instance = scene.instantiate()
	if not instance:
		return {}
	
	# Clear previous and add new
	for child in _block_container.get_children():
		child.queue_free()
	
	await get_tree().process_frame  # Let queue_free process
	
	_block_container.add_child(instance)
	
	# Wait for the instance to be ready and meshes to load
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Calculate block bounds
	var aabb = _get_node_aabb(instance)
	if aabb.size == Vector3.ZERO:
		instance.queue_free()
		return {}
	
	var block_size = aabb.size
	var block_center = aabb.position + block_size / 2.0
	
	# Position block at origin (centered)
	instance.position = -block_center
	
	# Configure camera for orthographic view that fits the block
	var max_dim = max(block_size.x, max(block_size.y, block_size.z))
	_camera.size = max_dim * 1.2  # Add some padding
	var cam_distance = max_dim * camera_distance_multiplier
	
	# Create image to hold all angles (horizontal strip)
	var sheet_width = sprite_size * angle_count
	var sheet_image = Image.create(sheet_width, sprite_size, false, Image.FORMAT_RGBA8)
	sheet_image.fill(background_color)
	
	# Render from each angle
	for angle_idx in range(angle_count):
		var angle = angle_idx * (TAU / angle_count)
		
		# Position camera around the block
		_camera.position = Vector3(
			sin(angle) * cam_distance,
			block_size.y * 0.3,  # Slightly above center
			cos(angle) * cam_distance
		)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		
		# Render
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		
		# Wait for render to complete
		await RenderingServer.frame_post_draw
		
		# Capture
		var viewport_image = _viewport.get_texture().get_image()
		
		# Copy to sheet
		var dest_x = angle_idx * sprite_size
		sheet_image.blit_rect(
			viewport_image,
			Rect2i(0, 0, sprite_size, sprite_size),
			Vector2i(dest_x, 0)
		)
	
	# Create texture from sheet
	var texture = ImageTexture.create_from_image(sheet_image)
	
	# Clean up
	instance.queue_free()
	
	return {
		"texture": texture,
		"size": block_size,
		"sprite_size": sprite_size,
		"angle_count": angle_count,
	}


func _get_node_aabb(node: Node3D) -> AABB:
	"""Calculate combined AABB of all meshes in a node."""
	var combined = AABB()
	var first = true
	
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			var mesh_aabb = child.mesh.get_aabb()
			var world_aabb = child.transform * mesh_aabb
			if first:
				combined = world_aabb
				first = false
			else:
				combined = combined.merge(world_aabb)
		elif child is Node3D:
			var child_aabb = _get_node_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				var world_aabb = child.transform * child_aabb
				if first:
					combined = world_aabb
					first = false
				else:
					combined = combined.merge(world_aabb)
	
	return combined


func get_impostor_texture(block_path: String) -> ImageTexture:
	"""Get the impostor texture for a block type."""
	if impostor_data.has(block_path):
		return impostor_data[block_path].texture
	return null


func get_impostor_data(block_path: String) -> Dictionary:
	"""Get full impostor data for a block type."""
	return impostor_data.get(block_path, {})
