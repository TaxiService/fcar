class_name CityGenerator
extends Node3D

# City generation prototype
# Builds a hex-grid city with spires at vertices and connectors between them

# Grid settings
@export var hex_edge_length: float = 1500.0  # Distance between adjacent spires (meters)
@export var grid_rings: int = 1  # Number of hex rings around center (0 = just center hex)

# Spire settings
@export var spire_height: float = 2000.0  # 2km tall
@export var spire_radius: float = 15.0  # 30m diameter
@export var biome_count: int = 4  # Number of vertical sections

# Visual settings
@export var biome_colors: Array[Color] = [
	Color(0.15, 0.25, 0.4),   # Bottom - deep blue/industrial
	Color(0.25, 0.45, 0.3),   # Lower-mid - greenish
	Color(0.45, 0.35, 0.25),  # Upper-mid - brownish
	Color(0.55, 0.55, 0.65),  # Top - pale/sky
]

# Runtime data
var spire_positions: Array[Vector3] = []  # All spire world positions
var hex_centers: Array[Vector2] = []  # Hex center positions (2D, xz plane)

# Debug settings
@export var show_ground_grid: bool = true
@export var ground_grid_size: float = 10000.0  # 10km grid

# Containers for generated geometry
var spires_container: Node3D
var connectors_container: Node3D


@export var spawn_fcar: bool = true
@export var fcar_spawn_height: float = 500.0  # Spawn car at this height

func _ready():
	_create_containers()
	if show_ground_grid:
		_create_ground_grid()
	generate_city()

	# Try to spawn FCar if available
	if spawn_fcar:
		_try_spawn_fcar()


func _try_spawn_fcar():
	# Look for FCar scene (user needs to save it from main.tscn first)
	var fcar_path = "res://FCar.tscn"
	if ResourceLoader.exists(fcar_path):
		var fcar_scene = load(fcar_path)
		var fcar = fcar_scene.instantiate()
		fcar.position = Vector3(0, fcar_spawn_height, 0)
		add_child(fcar)
		print("CityGenerator: Spawned FCar at height %.0fm" % fcar_spawn_height)

		# Disable freecam if FCar has its own camera
		var freecam = get_parent().get_node_or_null("FreeCam")
		if freecam:
			freecam.queue_free()
			print("CityGenerator: Removed FreeCam (using FCar camera)")
	else:
		print("CityGenerator: FCar.tscn not found - using FreeCam")
		print("  To add FCar: In main.tscn, right-click FCar > Save Branch as Scene > save as res://FCar.tscn")


func _create_containers():
	spires_container = Node3D.new()
	spires_container.name = "Spires"
	add_child(spires_container)

	connectors_container = Node3D.new()
	connectors_container.name = "Connectors"
	add_child(connectors_container)


func generate_city():
	print("CityGenerator: Starting city generation...")
	print("  Hex edge length: %.0fm" % hex_edge_length)
	print("  Grid rings: %d" % grid_rings)

	# Clear existing
	_clear_generated()

	# Step 1: Generate hex grid and find all unique spire positions
	_generate_hex_grid()

	# Step 2: Create spires at each position
	_generate_spires()

	print("CityGenerator: Done! Generated %d spires" % spire_positions.size())


func _clear_generated():
	spire_positions.clear()
	hex_centers.clear()

	for child in spires_container.get_children():
		child.queue_free()
	for child in connectors_container.get_children():
		child.queue_free()


func _generate_hex_grid():
	# Using axial coordinates (q, r) for hex grid
	# Spires are placed at hex VERTICES, not centers
	# For a pointy-top hex, vertices are at 60-degree intervals

	# First, collect all hex centers using axial coords
	var hex_coords: Array[Vector2i] = []

	# Center hex
	hex_coords.append(Vector2i(0, 0))

	# Rings around center
	for ring in range(1, grid_rings + 1):
		var coords = _get_hex_ring(ring)
		hex_coords.append_array(coords)

	# Convert hex coords to world positions and collect unique vertices
	var vertex_set: Dictionary = {}  # Use dict as set, key = snapped position string

	for coord in hex_coords:
		var center = _axial_to_world(coord)
		hex_centers.append(center)

		# Get the 6 vertices of this hexagon
		var vertices = _get_hex_vertices(center)
		for v in vertices:
			# Snap to avoid floating point duplicates
			var key = _snap_position_key(v)
			if not vertex_set.has(key):
				vertex_set[key] = v

	# Convert to array
	for pos in vertex_set.values():
		spire_positions.append(Vector3(pos.x, 0, pos.y))

	print("  Hex count: %d" % hex_centers.size())
	print("  Unique vertices (spires): %d" % spire_positions.size())


func _get_hex_ring(ring: int) -> Array[Vector2i]:
	# Get all hex coordinates in a ring at distance 'ring' from center
	var results: Array[Vector2i] = []

	if ring == 0:
		results.append(Vector2i(0, 0))
		return results

	# Axial direction vectors for the 6 hex directions
	var directions = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
	]

	# Start at one corner and walk around the ring
	var coord = Vector2i(ring, 0)  # Start position

	for i in range(6):  # 6 sides
		for j in range(ring):  # 'ring' hexes per side
			results.append(coord)
			coord = coord + directions[(i + 2) % 6]  # Move to next

	return results


func _axial_to_world(coord: Vector2i) -> Vector2:
	# Convert axial hex coordinate to world position (xz plane)
	# For pointy-top hexagons:
	var x = hex_edge_length * (sqrt(3.0) * coord.x + sqrt(3.0) / 2.0 * coord.y)
	var z = hex_edge_length * (3.0 / 2.0 * coord.y)
	return Vector2(x, z)


func _get_hex_vertices(center: Vector2) -> Array[Vector2]:
	# Get the 6 vertices of a pointy-top hexagon
	var vertices: Array[Vector2] = []
	for i in range(6):
		var angle = PI / 3.0 * i + PI / 6.0  # Pointy-top: offset by 30 degrees
		var vertex = center + Vector2(cos(angle), sin(angle)) * hex_edge_length
		vertices.append(vertex)
	return vertices


func _snap_position_key(pos: Vector2) -> String:
	# Create a string key for deduplication (snap to 1m precision)
	return "%d,%d" % [int(round(pos.x)), int(round(pos.y))]


func _generate_spires():
	var biome_height = spire_height / biome_count

	for i in range(spire_positions.size()):
		var pos = spire_positions[i]
		var spire = _create_spire(pos, biome_height)
		spire.name = "Spire_%d" % i
		spires_container.add_child(spire)


func _create_spire(pos: Vector3, biome_height: float) -> Node3D:
	var spire_root = Node3D.new()
	spire_root.position = pos

	# Create a cylinder mesh for each biome section
	for i in range(biome_count):
		var section = MeshInstance3D.new()
		section.name = "Biome_%d" % i

		# Create cylinder mesh
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = spire_radius
		cylinder.bottom_radius = spire_radius
		cylinder.height = biome_height
		section.mesh = cylinder

		# Position (cylinder origin is center, so offset by half height)
		section.position.y = biome_height * i + biome_height / 2.0

		# Material with biome color
		var mat = StandardMaterial3D.new()
		mat.albedo_color = biome_colors[i] if i < biome_colors.size() else Color.WHITE
		section.material_override = mat

		spire_root.add_child(section)

	return spire_root


func _create_ground_grid():
	# Create a simple ground plane with grid for reference
	var ground = MeshInstance3D.new()
	ground.name = "GroundGrid"

	var plane = PlaneMesh.new()
	plane.size = Vector2(ground_grid_size, ground_grid_size)
	plane.subdivide_width = int(ground_grid_size / 500)  # Grid line every 500m
	plane.subdivide_depth = int(ground_grid_size / 500)
	ground.mesh = plane

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.18, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = mat

	ground.position.y = -1  # Slightly below origin
	add_child(ground)


# Public API for regeneration
func regenerate():
	generate_city()
