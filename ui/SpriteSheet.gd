class_name SpriteSheet
extends RefCounted

# Loaded texture and frames
var source_texture: Texture2D
var frames: Array[AtlasTexture] = []
var file_path: String

# Frame configuration
var frame_width: int
var frame_height: int
var frame_count: int


func load_horizontal(path: String, width: int, height: int, count: int = -1) -> bool:
	file_path = path
	frame_width = width
	frame_height = height

	# Load the source texture
	source_texture = load(path) as Texture2D
	if not source_texture:
		push_warning("SpriteSheet: Failed to load texture: ", path)
		return false

	# Auto-detect frame count if not specified
	if count < 0:
		frame_count = int(source_texture.get_width() / frame_width)
	else:
		frame_count = count

	# Slice into frames
	_slice_frames()

	return true


func reload() -> bool:
	if file_path.is_empty():
		push_warning("SpriteSheet: No file path set, cannot reload")
		return false

	# Clear existing frames
	frames.clear()

	# Force reload the texture from disk
	source_texture = load(file_path) as Texture2D
	if not source_texture:
		push_warning("SpriteSheet: Failed to reload texture: ", file_path)
		return false

	_slice_frames()
	return true


func _slice_frames() -> void:
	frames.clear()

	for i in range(frame_count):
		var atlas = AtlasTexture.new()
		atlas.atlas = source_texture
		atlas.region = Rect2(
			i * frame_width,  # x
			0,                # y (horizontal strip)
			frame_width,
			frame_height
		)
		frames.append(atlas)


func get_frame(index: int) -> AtlasTexture:
	if index < 0 or index >= frames.size():
		push_warning("SpriteSheet: Frame index out of bounds: ", index)
		return null
	return frames[index]


func get_random_frame() -> AtlasTexture:
	if frames.is_empty():
		return null
	return frames[randi() % frames.size()]


func get_frame_count() -> int:
	return frames.size()
