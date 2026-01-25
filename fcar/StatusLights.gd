class_name StatusLights
extends RefCounted

# Light mesh references
var autohover_light: MeshInstance3D
var height_lights: Array[MeshInstance3D] = []  # Index 0=-2, 1=-1, 2=0, 3=+1, 4=+2
var handbrake_light: MeshInstance3D

# Materials (captured from the scene)
var material_on: Material
var material_off: Material
var handbrake_material_on: Material  # Unique red material for handbrake

# Configuration - height grid spacing from CityGrid
var height_grid_spacing: float = 2.5

# Dynamic scaling: at high vertical speeds, display "zooms out" to show larger scale
# This naturally reduces flash rate without losing responsiveness
const SCALE_SPEED_THRESHOLD: float = 5.0  # Start scaling above this vertical speed (m/s)
const SCALE_DOUBLING_SPEED: float = 7.0  # Speed increment to double the scale
const MAX_SCALE_FACTOR: float = 16.0  # Maximum scale multiplier

# Photosensitive mode: hard rate limit instead of dynamic scaling (for accessibility)
var photosensitive_mode: bool = false
var display_light_index: int = 2  # For photosensitive mode
var time_since_change: float = 1.0
const MIN_CHANGE_INTERVAL: float = 0.15


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

	# Get handbrake light (optional - don't fail if missing)
	handbrake_light = statuslights_node.get_node_or_null("handbrake") as MeshInstance3D
	if handbrake_light:
		# Capture its unique on material (red), then turn it off initially
		handbrake_material_on = handbrake_light.get_surface_override_material(0)
		handbrake_light.set_surface_override_material(0, material_off)

	return true


func update(auto_hover_enabled: bool, _lock_height: bool, current_y: float, _target_height: float, delta: float, vertical_velocity: float = 0.0) -> void:
	# Update autohover light
	_set_light(autohover_light, auto_hover_enabled)

	# Height lights show position within the height grid cell
	# Light 0 = on a grid plane, +/-1,2 = drifting between planes
	# Only one light on at a time

	# Calculate effective spacing - scales up at high vertical speeds
	var effective_spacing = _get_effective_spacing(vertical_velocity)

	# Calculate offset from nearest grid plane (using effective spacing)
	# nearest_plane = round(y / spacing) * spacing
	# offset = y - nearest_plane, range: [-spacing/2, +spacing/2]
	var nearest_plane = round(current_y / effective_spacing) * effective_spacing
	var offset = current_y - nearest_plane

	# Normalize to [-1, +1] range (where ±1 = halfway between planes)
	# Negate so light shows where the plane is relative to car (above plane = light below)
	var half_spacing = effective_spacing / 2.0
	var normalized = -offset / half_spacing if half_spacing > 0 else 0.0

	# Map to target light index (0-4 in array, representing -2 to +2)
	# Thresholds divide the range into 5 zones:
	#   [-1.0, -0.6) → -2 (index 0)
	#   [-0.6, -0.2) → -1 (index 1)
	#   [-0.2, +0.2) →  0 (index 2)
	#   [+0.2, +0.6) → +1 (index 3)
	#   [+0.6, +1.0] → +2 (index 4)
	var target_index: int
	if normalized < -0.6:
		target_index = 0  # -2
	elif normalized < -0.2:
		target_index = 1  # -1
	elif normalized < 0.2:
		target_index = 2  # 0
	elif normalized < 0.6:
		target_index = 3  # +1
	else:
		target_index = 4  # +2

	# Apply display update (with optional rate limiting for photosensitive mode)
	var final_index = target_index
	if photosensitive_mode:
		time_since_change += delta
		if target_index != display_light_index and time_since_change >= MIN_CHANGE_INTERVAL:
			display_light_index = target_index
			time_since_change = 0.0
		final_index = display_light_index

	# Turn on only the selected light
	for i in range(height_lights.size()):
		_set_light(height_lights[i], i == final_index)


func _get_effective_spacing(vertical_velocity: float) -> float:
	# Dynamic scaling: "zoom out" at high vertical speeds to reduce flash rate
	# This keeps the display responsive while preventing rapid flashing
	var vertical_speed = abs(vertical_velocity)

	if vertical_speed <= SCALE_SPEED_THRESHOLD:
		return height_grid_spacing

	# Exponential scaling: double the spacing for every SCALE_DOUBLING_SPEED m/s above threshold
	var excess_speed = vertical_speed - SCALE_SPEED_THRESHOLD
	var scale_factor = pow(2.0, excess_speed / SCALE_DOUBLING_SPEED)
	scale_factor = min(scale_factor, MAX_SCALE_FACTOR)

	return height_grid_spacing * scale_factor


func _set_light(light: MeshInstance3D, on: bool) -> void:
	if light:
		light.set_surface_override_material(0, material_on if on else material_off)


func set_handbrake(active: bool) -> void:
	if handbrake_light and handbrake_material_on:
		handbrake_light.set_surface_override_material(0, handbrake_material_on if active else material_off)
