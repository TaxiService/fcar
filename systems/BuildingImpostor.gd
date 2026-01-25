# BuildingImpostor.gd
# A billboard sprite that displays a building block from the correct angle
# Similar to Person.gd but for static building blocks
class_name BuildingImpostor
extends Sprite3D

# Configuration
var block_path: String = ""
var block_size: Vector3 = Vector3.ONE
var angle_count: int = 8
var impostor_texture: Texture2D

# Cached
var _sprite_width: float = 0.0
var _current_frame: int = 0
var _camera: Camera3D


func _ready():
	# Billboard toward camera (Y-axis only for buildings)
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	
	# Transparent
	transparent = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	
	# No shadows from impostors (they're approximations)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Find camera
	_camera = get_viewport().get_camera_3d()


func setup(texture: Texture2D, size: Vector3, angles: int = 8):
	"""Initialize the impostor with its texture and size."""
	impostor_texture = texture
	block_size = size
	angle_count = angles
	
	self.texture = texture
	
	# Calculate sprite width (texture is horizontal strip)
	var tex_width = texture.get_width()
	var tex_height = texture.get_height()
	_sprite_width = tex_width / float(angle_count)
	
	# Set up horizontal frames
	hframes = angle_count
	vframes = 1
	frame = 0
	
	# Scale sprite to match block size (approximately)
	var max_dim = max(size.x, max(size.y, size.z))
	pixel_size = max_dim / tex_height * 1.1  # Slight padding


func _process(_delta: float):
	if not _camera or not impostor_texture:
		return
	
	# Calculate which angle to show based on camera direction
	var to_camera = _camera.global_position - global_position
	var angle = atan2(to_camera.x, to_camera.z)
	
	# Convert angle to frame index
	# Angle 0 = looking from +Z, increases clockwise
	var normalized_angle = fmod(angle + TAU, TAU)  # 0 to TAU
	var frame_float = normalized_angle / TAU * angle_count
	var new_frame = int(round(frame_float)) % angle_count
	
	if new_frame != _current_frame:
		_current_frame = new_frame
		frame = new_frame


# Static helper to create an impostor from data
static func create_from_data(data: Dictionary, block_path: String) -> BuildingImpostor:
	var impostor = BuildingImpostor.new()
	impostor.block_path = block_path
	impostor.setup(data.texture, data.size, data.angle_count)
	return impostor
