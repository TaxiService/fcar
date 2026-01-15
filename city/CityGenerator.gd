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

# Connector settings
@export var edge_connector_radius: float = 4.0  # Edge connectors (along hex edges)
@export var crosslink_radius: float = 12.0  # Crosslinks (internal pattern connectors)
@export var connectors_per_biome: int = 1  # How many connector levels per biome section

# Edge connector patterns - which hex edges to connect (vertices 0-5, edges are adjacent pairs)
const EDGE_PATTERNS = {
	"none": [],
	"full": [[0,1], [1,2], [2,3], [3,4], [4,5], [5,0]],  # all 6 edges
	"half_a": [[0,1], [2,3], [4,5]],  # alternating
	"half_b": [[1,2], [3,4], [5,0]],  # alternating offset
	"single": [[0,1]],  # just one edge
}

# Per-biome edge pattern weights (index = biome, from bottom to top)
# Each biome has a dictionary of pattern_name: weight for weighted random selection
@export var biome_edge_patterns: Array[Dictionary] = [
	{"none": 1.0},  # biome 0 (bottom)
	{"single": 1.0},  # biome 1
	{"none": 1.0},  # biome 2
	{"half_a": 1.0},  # biome 3 (top)
]


# Crosslink pattern library - vertex pairs within a hexagon (vertices 0-5)
# These connect non-adjacent spires inside each hex
const CROSSLINK_PATTERNS = {
	"empty": [], # an empty gridblock
	"full": [[0,1], [1,2], [2,3], [3,4], [4,5], [5,0]], # a full hexagon
	"single": [[0, 3]],  # just one through line
	"double":[[0, 4], [1, 3]], # two parallel lines
	"cross": [[0, 3], [1, 4]], # two crossing lines
	"dagger": [[0, 3], [1, 5]], # typographic dagger
	"dagger_strk": [[0, 3], [1, 5], [2, 4]], # double dagger
	"tri_norm": [[0, 2], [2, 4], [4, 0]], # a triangle
	"tri_strk": [[1, 3], [3, 5], [5, 1], [2, 4]], # a triangle struck by a line
	"zed_strk": [[0, 3], [1, 2], [4, 5], [5, 2]], # a Z shape struck by a line
	"rect": [[0, 1], [1, 3], [3, 4], [4, 0]], # a rectangle
	"kite": [[0, 2], [2, 4] , [4, 5], [5, 0]], # a kite
	
}

# Per-biome crosslink pattern weights (index = biome, from bottom to top)
# Each biome has a dictionary of pattern_name: weight for weighted random selection
@export var biome_crosslink_patterns: Array[Dictionary] = [
	{"full": 1.0, "empty": 0.5},  # biome 0 (bottom)
	{"empty": 2.0, "single": 1.0, "rect":1.0, "tri-norm":0.5, "tri-strk":0.5,},  # biome 1
	{"empty": 2.0, "single": 1.0, "cross":1.0, "dagger":0.5, "dagger_strk":0.5},  # biome 2
	{"empty": 2.0, "zed_strk": 1.0, "kite":1.0, "dagger_strk":0.5, "cross":0.5},  # biome 3 (top)
]

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
var hex_vertex_lists: Array = []  # Array of vertex position arrays (one per hex, 6 vertices each)
var connector_edges: Array = []  # Array of [Vector3, Vector3] pairs for edge connector endpoints

# Track used edges per hex per biome to avoid overlaps: { hex_idx: { biome_idx: Set of "v1,v2" strings } }
var used_edges: Dictionary = {}

# Debug settings
@export var show_ground_grid: bool = true
@export var ground_grid_size: float = 10000.0  # 10km grid

# Containers for generated geometry
var spires_container: Node3D
var connectors_container: Node3D
var buildings_container: Node3D

# Building generation
@export_category("Buildings")
@export var generate_buildings: bool = true
@export var building_seed_spacing: float = 90.0  # Seed points every Nm along connectors
@export var building_seed_probability: float = 0.3  # Chance to actually place a seed (sparsity)
@export var building_max_depth: int = 3  # Max blocks from seed
@export var building_branch_chance: float = 0.2  # Chance to branch at each connection
@export var building_max_total: int = 200  # Hard limit on total building blocks

var building_generator: BuildingGenerator

# Stored connector data for building generation: [{start, end, height, biome_idx}]
var connector_data: Array[Dictionary] = []

@export_category("Spawning")
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

	buildings_container = Node3D.new()
	buildings_container.name = "Buildings"
	add_child(buildings_container)

	# Create building generator
	building_generator = BuildingGenerator.new()
	building_generator.name = "BuildingGenerator"
	buildings_container.add_child(building_generator)


func generate_city():
	print("CityGenerator: Starting city generation...")
	print("  Hex edge length: %.0fm" % hex_edge_length)
	print("  Grid rings: %d" % grid_rings)

	# Clear existing
	_clear_generated()

	# Step 1: Generate hex grid and find all unique spire positions + edges
	_generate_hex_grid()

	# Step 2: Create spires at each position
	_generate_spires()

	# Step 3: Create edge connectors between spires
	_generate_connectors()

	# Step 4: Create crosslink connectors within hexagons
	_generate_crosslinks()

	# Step 5: Generate buildings on connectors
	if generate_buildings:
		_generate_buildings()

	print("CityGenerator: Done! Generated %d spires, %d edge connections, %d hexagons" % [spire_positions.size(), connector_edges.size(), hex_vertex_lists.size()])


func _clear_generated():
	spire_positions.clear()
	hex_centers.clear()
	hex_vertex_lists.clear()
	connector_edges.clear()
	used_edges.clear()
	connector_data.clear()

	for child in spires_container.get_children():
		child.queue_free()
	for child in connectors_container.get_children():
		child.queue_free()
	# Clear buildings but keep the generator
	for child in buildings_container.get_children():
		if child != building_generator:
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

	# Convert hex coords to world positions and collect unique vertices + edges
	var vertex_set: Dictionary = {}  # Use dict as set, key = snapped position string
	var edge_set: Dictionary = {}  # Track unique edges, key = sorted endpoint keys

	for coord in hex_coords:
		var center = _axial_to_world(coord)
		hex_centers.append(center)

		# Get the 6 vertices of this hexagon
		var vertices = _get_hex_vertices(center)

		# Store vertex list for this hex (as Vector3 for crosslinks later)
		var vertex_list_3d: Array[Vector3] = []
		for v in vertices:
			vertex_list_3d.append(Vector3(v.x, 0, v.y))
		hex_vertex_lists.append(vertex_list_3d)

		for i in range(6):
			var v = vertices[i]
			# Snap to avoid floating point duplicates
			var key = _snap_position_key(v)
			if not vertex_set.has(key):
				vertex_set[key] = v

			# Add edge to next vertex (wrapping around)
			var v_next = vertices[(i + 1) % 6]
			var key_next = _snap_position_key(v_next)
			var edge_key = _make_edge_key(key, key_next)
			if not edge_set.has(edge_key):
				edge_set[edge_key] = [v, v_next]

	# Convert vertices to array
	for pos in vertex_set.values():
		spire_positions.append(Vector3(pos.x, 0, pos.y))

	# Convert edges to array (as Vector3 pairs at y=0)
	for edge in edge_set.values():
		connector_edges.append([
			Vector3(edge[0].x, 0, edge[0].y),
			Vector3(edge[1].x, 0, edge[1].y)
		])

	print("  Hex count: %d" % hex_centers.size())
	print("  Unique vertices (spires): %d" % spire_positions.size())
	print("  Unique edges (connectors): %d" % connector_edges.size())


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


func _make_edge_key(key_a: String, key_b: String) -> String:
	# Create a consistent key for an edge (order-independent)
	if key_a < key_b:
		return key_a + "|" + key_b
	else:
		return key_b + "|" + key_a


func _generate_spires():
	var biome_height = spire_height / biome_count

	for i in range(spire_positions.size()):
		var pos = spire_positions[i]
		var spire = _create_spire(pos, biome_height)
		spire.name = "Spire_%d" % i
		spires_container.add_child(spire)


func _generate_connectors():
	if biome_edge_patterns.is_empty():
		print("  Edge connectors disabled (no patterns configured)")
		return

	var biome_height = spire_height / biome_count
	var connector_count = 0

	# Generate per-hex per-biome
	for hex_idx in range(hex_vertex_lists.size()):
		var vertices = hex_vertex_lists[hex_idx]

		# Initialize used_edges tracking for this hex
		if not used_edges.has(hex_idx):
			used_edges[hex_idx] = {}

		for biome_idx in range(biome_count):
			# Initialize biome tracking
			if not used_edges[hex_idx].has(biome_idx):
				used_edges[hex_idx][biome_idx] = {}

			# Get pattern weights for this biome
			var weights = biome_edge_patterns[biome_idx] if biome_idx < biome_edge_patterns.size() else {"none": 1.0}
			var pattern_name = _pick_weighted_from_dict(weights)
			var pattern = EDGE_PATTERNS.get(pattern_name, [])

			if pattern.is_empty():
				continue

			# Calculate height for this biome
			var biome_base = biome_height * biome_idx
			for conn_idx in range(connectors_per_biome):
				var height_offset = biome_height * (conn_idx + 0.5) / connectors_per_biome
				var connector_y = biome_base + height_offset

				for pair in pattern:
					var v1_idx = pair[0]
					var v2_idx = pair[1]

					# Mark this edge as used
					var edge_key = _make_edge_key_indices(v1_idx, v2_idx)
					used_edges[hex_idx][biome_idx][edge_key] = true

					var start_pos = vertices[v1_idx]
					var end_pos = vertices[v2_idx]

					var connector = _create_connector(start_pos, end_pos, connector_y, biome_idx, edge_connector_radius)
					connector.name = "EdgeConn_%d_B%d_%s_%d" % [hex_idx, biome_idx, pattern_name, connector_count]
					connectors_container.add_child(connector)
					connector_count += 1

					# Store for building generation
					connector_data.append({
						"start": Vector3(start_pos.x, connector_y, start_pos.z),
						"end": Vector3(end_pos.x, connector_y, end_pos.z),
						"biome_idx": biome_idx
					})

	print("  Generated %d edge connector beams" % connector_count)


func _make_edge_key_indices(v1: int, v2: int) -> String:
	# Consistent key regardless of order
	if v1 < v2:
		return "%d-%d" % [v1, v2]
	else:
		return "%d-%d" % [v2, v1]


func _pick_weighted_from_dict(weights: Dictionary) -> String:
	if weights.is_empty():
		return ""

	# Calculate total weight
	var total_weight = 0.0
	for pattern_name in weights:
		total_weight += weights[pattern_name]

	# Roll and pick
	var roll = randf() * total_weight
	var cumulative = 0.0
	for pattern_name in weights:
		cumulative += weights[pattern_name]
		if roll <= cumulative:
			return pattern_name

	# Fallback to first key
	return weights.keys()[0]


func _generate_crosslinks():
	if biome_crosslink_patterns.is_empty():
		print("  Crosslinks disabled (no patterns configured)")
		return

	var biome_height = spire_height / biome_count
	var crosslink_count = 0
	var skipped_count = 0

	for hex_idx in range(hex_vertex_lists.size()):
		var vertices = hex_vertex_lists[hex_idx]

		# Initialize used_edges tracking if not already done
		if not used_edges.has(hex_idx):
			used_edges[hex_idx] = {}

		# For each biome level, pick from weighted patterns
		for biome_idx in range(biome_count):
			if not used_edges[hex_idx].has(biome_idx):
				used_edges[hex_idx][biome_idx] = {}

			# Get pattern weights for this biome
			var weights = biome_crosslink_patterns[biome_idx] if biome_idx < biome_crosslink_patterns.size() else {"empty": 1.0}
			var pattern_name = _pick_weighted_from_dict(weights)
			var pattern = CROSSLINK_PATTERNS.get(pattern_name, [])

			if pattern.is_empty():
				continue

			# Pick random rotation (0-5)
			var rotation = randi() % 6

			# Calculate height for this biome's crosslinks
			var biome_base = biome_height * biome_idx
			for conn_idx in range(connectors_per_biome):
				var height_offset = biome_height * (conn_idx + 0.5) / connectors_per_biome
				var connector_y = biome_base + height_offset

				# Generate each connection in the pattern
				for pair in pattern:
					# Apply rotation to vertex indices
					var v1_idx = (pair[0] + rotation) % 6
					var v2_idx = (pair[1] + rotation) % 6

					# Check if this edge is already used (by edge connectors)
					var edge_key = _make_edge_key_indices(v1_idx, v2_idx)
					if used_edges[hex_idx][biome_idx].has(edge_key):
						skipped_count += 1
						continue

					# Mark as used to avoid duplicate crosslinks too
					used_edges[hex_idx][biome_idx][edge_key] = true

					var start_pos = vertices[v1_idx]
					var end_pos = vertices[v2_idx]

					var connector = _create_connector(start_pos, end_pos, connector_y, biome_idx, crosslink_radius)
					connector.name = "Crosslink_%d_B%d_%s_%d" % [hex_idx, biome_idx, pattern_name, crosslink_count]
					connectors_container.add_child(connector)
					crosslink_count += 1

					# Store for building generation
					connector_data.append({
						"start": Vector3(start_pos.x, connector_y, start_pos.z),
						"end": Vector3(end_pos.x, connector_y, end_pos.z),
						"biome_idx": biome_idx
					})

	print("  Generated %d crosslink beams (skipped %d overlaps)" % [crosslink_count, skipped_count])


func _create_connector(start: Vector3, end: Vector3, height: float, biome_idx: int, radius: float) -> Node3D:
	var connector_root = Node3D.new()

	# Calculate position and rotation
	var start_3d = Vector3(start.x, height, start.z)
	var end_3d = Vector3(end.x, height, end.z)
	var midpoint = (start_3d + end_3d) / 2.0
	var direction = end_3d - start_3d
	var length = direction.length()

	connector_root.position = midpoint

	# Create cylinder mesh (horizontal)
	var mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length - spire_radius * 2  # Subtract spire radius from each end
	mesh_instance.mesh = cylinder

	# Rotate to align with edge direction (cylinder is vertical by default)
	# We need to rotate it to be horizontal and point in the right direction
	mesh_instance.rotation.x = PI / 2  # Lay flat
	connector_root.rotation.y = atan2(direction.x, direction.z)  # Point toward end

	# Material - slightly darker than spire biome color
	var mat = StandardMaterial3D.new()
	var base_color = biome_colors[biome_idx] if biome_idx < biome_colors.size() else Color.GRAY
	mat.albedo_color = base_color.darkened(0.2)
	mesh_instance.material_override = mat

	connector_root.add_child(mesh_instance)
	return connector_root


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


func _generate_buildings():
	if not building_generator:
		push_error("CityGenerator: BuildingGenerator not initialized")
		return

	# Configure generator
	building_generator.max_growth_depth = building_max_depth
	building_generator.branch_probability = building_branch_chance
	building_generator.max_blocks_total = building_max_total
	building_generator.reset_counter()

	var seed_count = 0
	var blocks_placed = 0

	print("  Starting building generation (max %d blocks)..." % building_max_total)

	# Generate seed points along each connector
	for conn in connector_data:
		# Check total limit
		if blocks_placed >= building_max_total:
			break

		var start: Vector3 = conn.start
		var end: Vector3 = conn.end
		var biome_idx: int = conn.biome_idx

		var direction = end - start
		var length = direction.length()
		var dir_normalized = direction.normalized()

		# Calculate seed points at building_seed_spacing intervals
		var usable_length = length - spire_radius * 2 - building_seed_spacing
		if usable_length <= 0:
			continue

		var num_seeds = int(usable_length / building_seed_spacing)
		var start_offset = spire_radius + building_seed_spacing * 0.5

		for i in range(num_seeds):
			# Check total limit
			if blocks_placed >= building_max_total:
				break

			# Random chance to skip this seed (sparsity control)
			if randf() > building_seed_probability:
				continue

			var t = start_offset + building_seed_spacing * i
			var seed_pos = start + dir_normalized * t

			# Perpendicular direction for growth (alternate sides)
			var up = Vector3.UP
			var side = dir_normalized.cross(up).normalized()
			if i % 2 == 1:
				side = -side

			# Count blocks before
			var before = building_generator.get_child_count()

			# Grow building from this seed
			building_generator._grow_from_seed(seed_pos, side, biome_idx, 0)

			# Count blocks placed
			var placed = building_generator.get_child_count() - before
			blocks_placed += placed
			seed_count += 1

	print("  Generated %d blocks from %d seeds" % [blocks_placed, seed_count])


# Public API for regeneration
func regenerate():
	generate_city()
