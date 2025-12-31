class_name DirectionLights
extends RefCounted

# Light mesh references
var forward_light: MeshInstance3D
var backward_light: MeshInstance3D
var left_light: MeshInstance3D
var right_light: MeshInstance3D

# Materials (captured from the scene)
var material_on: Material
var material_off: Material


func initialize(directionlights_node: Node3D, mat_on: Material, mat_off: Material) -> bool:
	if not directionlights_node:
		return false

	# Get direction lights
	forward_light = directionlights_node.get_node_or_null("forwards") as MeshInstance3D
	backward_light = directionlights_node.get_node_or_null("backwards") as MeshInstance3D
	left_light = directionlights_node.get_node_or_null("leftwards") as MeshInstance3D
	right_light = directionlights_node.get_node_or_null("rightwards") as MeshInstance3D

	if not forward_light or not backward_light or not left_light or not right_light:
		push_warning("DirectionLights: Could not find all direction light meshes")
		return false

	# Use materials passed in (shared with StatusLights)
	material_on = mat_on
	material_off = mat_off

	if not material_on or not material_off:
		push_warning("DirectionLights: Materials not provided")
		return false

	# Start with all lights off
	update(false, false, false, false)

	return true


func update(forward: bool, backward: bool, left: bool, right: bool) -> void:
	_set_light(forward_light, forward)
	_set_light(backward_light, backward)
	_set_light(left_light, left)
	_set_light(right_light, right)


func _set_light(light: MeshInstance3D, on: bool) -> void:
	if light:
		light.set_surface_override_material(0, material_on if on else material_off)
