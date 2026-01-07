class_name StatusLights
extends RefCounted

# Light mesh references
var autohover_light: MeshInstance3D
var height_lights: Array[MeshInstance3D] = []  # Index 0=-2, 1=-1, 2=0, 3=+1, 4=+2

# Materials (captured from the scene)
var material_on: Material
var material_off: Material

# Configuration - height grid spacing from CityGrid
var height_grid_spacing: float = 2.5


func initialize(statuslights_node: Node3D) -> bool:
	if not statuslights_node:
		return false

	# Get autohover light
	autohover_light = statuslights_node.get_node_or_null("autohover") as MeshInstance3D
	if not autohover_light:
		push_warning("StatusLights: Could not find autohover light")
		return false

	# Get height lock lights in order: -2, -1, 0, +1, +2
	var heightlock_node = statuslights_node.get_node_or_null("heightlock")
	if not heightlock_node:
		push_warning("StatusLights: Could not find heightlock node")
		return false

	var light_names = ["-2", "-1", "0", "+1", "+2"]
	for light_name in light_names:
		var light = heightlock_node.get_node_or_null(light_name) as MeshInstance3D
		if light:
			height_lights.append(light)
		else:
			push_warning("StatusLights: Could not find light: " + light_name)
			return false

	# Capture materials from light 0 (ON) and light -2 (OFF)
	material_on = height_lights[2].get_surface_override_material(0)  # Light "0" has ON material
	material_off = height_lights[0].get_surface_override_material(0)  # Light "-2" has OFF material

	if not material_on or not material_off:
		push_warning("StatusLights: Could not capture materials")
		return false

	return true


func update(auto_hover_enabled: bool, _lock_height: bool, current_y: float, _target_height: float) -> void:
	# Update autohover light
	_set_light(autohover_light, auto_hover_enabled)

	# Height lights show position within the height grid cell
	# Light 0 = on a grid plane, +/-1,2 = drifting between planes
	# Only one light on at a time

	# Calculate offset from nearest grid plane
	# nearest_plane = round(y / spacing) * spacing
	# offset = y - nearest_plane, range: [-spacing/2, +spacing/2]
	var nearest_plane = round(current_y / height_grid_spacing) * height_grid_spacing
	var offset = current_y - nearest_plane

	# Normalize to [-1, +1] range (where ±1 = halfway between planes)
	# Negate so light shows where the plane is relative to car (above plane = light below)
	var half_spacing = height_grid_spacing / 2.0
	var normalized = -offset / half_spacing if half_spacing > 0 else 0.0

	# Map to light index (0-4 in array, representing -2 to +2)
	# Thresholds divide the range into 5 zones:
	#   [-1.0, -0.6) → -2 (index 0)
	#   [-0.6, -0.2) → -1 (index 1)
	#   [-0.2, +0.2) →  0 (index 2)
	#   [+0.2, +0.6) → +1 (index 3)
	#   [+0.6, +1.0] → +2 (index 4)
	var light_index: int
	if normalized < -0.6:
		light_index = 0  # -2
	elif normalized < -0.2:
		light_index = 1  # -1
	elif normalized < 0.2:
		light_index = 2  # 0
	elif normalized < 0.6:
		light_index = 3  # +1
	else:
		light_index = 4  # +2

	# Turn on only the selected light
	for i in range(height_lights.size()):
		_set_light(height_lights[i], i == light_index)


func _set_light(light: MeshInstance3D, on: bool) -> void:
	if light:
		light.set_surface_override_material(0, material_on if on else material_off)
