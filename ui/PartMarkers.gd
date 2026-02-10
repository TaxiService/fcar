class_name PartMarkers
extends Node3D

# Displays floating markers above resting PersonParts during hospital mode.
# CORE parts get bright red markers, BODY parts get dimmer markers.

@export var max_markers: int = 20
@export var marker_range: float = 200.0
@export var hover_height: float = 2.5
@export var marker_radius: float = 0.15

var people_manager: Node = null
var active: bool = false
var _time: float = 0.0

# Marker pool
var _markers: Array[MeshInstance3D] = []
var _core_material: StandardMaterial3D
var _body_material: StandardMaterial3D


func _ready():
	_create_materials()
	_create_marker_pool()
	visible = false


func _create_materials():
	# Shared material for CORE markers: bright red, unshaded, billboard
	_core_material = StandardMaterial3D.new()
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_material.albedo_color = Color(1.0, 0.3, 0.3, 0.9)
	_core_material.no_depth_test = true
	_core_material.render_priority = 1

	# Shared material for BODY markers: dim blue-gray
	_body_material = StandardMaterial3D.new()
	_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_material.albedo_color = Color(0.5, 0.5, 0.7, 0.7)
	_body_material.no_depth_test = true
	_body_material.render_priority = 1


func _create_marker_pool():
	var mesh = SphereMesh.new()
	mesh.radius = marker_radius
	mesh.height = marker_radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4

	for i in range(max_markers):
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _body_material
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_markers.append(mi)


func set_active(on: bool):
	active = on
	visible = on
	if not on:
		for m in _markers:
			m.visible = false


func _process(delta: float):
	if not active or not people_manager:
		return

	_time += delta

	var cam = Person.lod_camera if Person else null
	var cam_pos: Vector3
	if cam:
		cam_pos = cam.global_position
	else:
		cam_pos = global_position

	var range_sq = marker_range * marker_range
	var marker_idx: int = 0

	# Assign markers to nearby resting parts
	for part in people_manager.all_parts:
		if marker_idx >= max_markers:
			break
		if not is_instance_valid(part):
			continue
		if not part.at_rest:
			continue

		var dx = part.global_position.x - cam_pos.x
		var dz = part.global_position.z - cam_pos.z
		if dx * dx + dz * dz > range_sq:
			continue

		var m = _markers[marker_idx]
		m.global_position = part.global_position + Vector3(0, hover_height, 0)
		m.material_override = _core_material if part.is_core else _body_material

		# Gentle pulse: scale oscillation staggered per marker
		var pulse = 0.8 + 0.2 * sin(_time * 3.0 + marker_idx * 0.7)
		m.scale = Vector3(pulse, pulse, pulse)
		m.visible = true
		marker_idx += 1

	# Hide unused markers
	for i in range(marker_idx, max_markers):
		_markers[i].visible = false
