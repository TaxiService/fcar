class_name StatusLights
extends RefCounted

# Light mesh references
var autohover_light: MeshInstance3D
var height_lights: Array[MeshInstance3D] = []  # Index 0=-2, 1=-1, 2=0, 3=+1, 4=+2

# Materials (captured from the scene)
var material_on: Material
var material_off: Material

# Configuration
var height_lock_refresh_threshold: float = 0.8


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


func update(auto_hover_enabled: bool, lock_height: bool, current_y: float, target_height: float) -> void:
	# Update autohover light
	_set_light(autohover_light, auto_hover_enabled)

	if not lock_height:
		# Height lock OFF - all height lights off
		for light in height_lights:
			_set_light(light, false)
		return

	# Height lock ON - calculate drift and light up accordingly
	var drift = current_y - target_height
	var drift_normalized = drift / height_lock_refresh_threshold if height_lock_refresh_threshold > 0 else 0.0

	# Light 0 (index 2) is always on when height locked
	_set_light(height_lights[2], true)

	# Determine which lights to turn on based on drift
	# Positive drift (above target): light up +1, +2
	# Negative drift (below target): light up -1, -2
	var abs_drift = abs(drift_normalized)

	# Thresholds: 0.33 for ±1, 0.66 for ±2
	var show_level_1 = abs_drift > 0.33
	var show_level_2 = abs_drift > 0.66

	if drift >= 0:
		# Above target - light up positive side
		_set_light(height_lights[3], show_level_1)  # +1
		_set_light(height_lights[4], show_level_2)  # +2
		_set_light(height_lights[1], false)  # -1
		_set_light(height_lights[0], false)  # -2
	else:
		# Below target - light up negative side
		_set_light(height_lights[1], show_level_1)  # -1
		_set_light(height_lights[0], show_level_2)  # -2
		_set_light(height_lights[3], false)  # +1
		_set_light(height_lights[4], false)  # +2


func _set_light(light: MeshInstance3D, on: bool) -> void:
	if light:
		light.set_surface_override_material(0, material_on if on else material_off)
