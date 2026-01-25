class_name DebugVisualizer
extends RefCounted

# Debug visualization meshes
var cylinders: Array[MeshInstance3D] = []
var arrows: Array[MeshInstance3D] = []
var max_thrust: float = 10.0  # For scaling arrows

func create_visuals(parent: Node3D, wheel_nodes: Array) -> void:
	for wheel in wheel_nodes:
		if not wheel:
			continue

		# Create cylinder for thruster direction
		var cylinder_mesh = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.05
		cylinder.bottom_radius = 0.08
		cylinder.height = 0.3
		cylinder_mesh.mesh = cylinder

		# Create material for cylinder (blue-ish)
		var cyl_mat = StandardMaterial3D.new()
		cyl_mat.albedo_color = Color(0.3, 0.5, 1.0, 0.8)
		cyl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cylinder_mesh.material_override = cyl_mat

		parent.add_child(cylinder_mesh)
		cylinders.append(cylinder_mesh)

		# Create arrow for force vector
		var arrow_mesh = MeshInstance3D.new()
		var arrow = CylinderMesh.new()
		arrow.top_radius = 0.0
		arrow.bottom_radius = 0.04
		arrow.height = 0.5
		arrow_mesh.mesh = arrow

		# Create material for arrow (green for force)
		var arrow_mat = StandardMaterial3D.new()
		arrow_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.9)
		arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		arrow_mesh.material_override = arrow_mat

		parent.add_child(arrow_mesh)
		arrows.append(arrow_mesh)


func update_visual(index: int, wheel_pos: Vector3, thrust_direction: Vector3, thrust_magnitude: float) -> void:
	if index >= cylinders.size() or index >= arrows.size():
		return

	var cylinder = cylinders[index]
	var arrow = arrows[index]

	# Position cylinder at wheel, pointing in thrust direction
	cylinder.global_position = wheel_pos

	# Rotate cylinder to point along thrust direction
	if thrust_direction.length() > 0.01:
		var up = thrust_direction.normalized()
		var right = up.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.01:
			right = up.cross(Vector3.RIGHT).normalized()
		var forward = right.cross(up).normalized()
		cylinder.global_transform.basis = Basis(right, up, forward)

	# Position arrow BELOW the cylinder (like thruster exhaust fire!)
	var arrow_length = clamp(thrust_magnitude / max_thrust, 0.1, 2.0) * 0.5
	var exhaust_direction = -thrust_direction.normalized()
	arrow.global_position = wheel_pos + exhaust_direction * (0.15 + arrow_length * 0.5)

	# Flip the basis to point downward
	if thrust_direction.length() > 0.01:
		var down = exhaust_direction
		var right = down.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.01:
			right = down.cross(Vector3.RIGHT).normalized()
		var forward = right.cross(down).normalized()
		arrow.global_transform.basis = Basis(right, down, forward)
	arrow.scale = Vector3(1, arrow_length, 1)


func update_all_disabled(wheel_nodes: Array) -> void:
	# Show all thrusters in disabled state (pointing up, no force)
	for i in range(wheel_nodes.size()):
		if wheel_nodes[i]:
			update_visual(i, wheel_nodes[i].global_position, Vector3.UP, 0.0)
