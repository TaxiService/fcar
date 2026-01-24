class_name CityGenerator
extends Node3D

# City generation prototype
# Builds a hex-grid city with spires at vertices and connectors between them

signal city_generation_started()
signal city_generation_progress(phase: String, progress: float, message: String)
signal city_generation_complete()

const TF = ConnectionPoint.TypeFlags
const SF = ConnectionPoint.SizeFlags

# Grid settings
@export var hex_edge_length: float = 420.0  # Distance between adjacent spires (meters)
@export var grid_rings: int = 3  # Number of hex rings around center (0 = just center hex)

# Spire settings
@export var spire_height: float = 1600.0  # 2km tall
@export var biome_count: int = 4  # Number of vertical sections

# Spire geometry per biome (tapers upward)
@export var spire_base_radius: float = 35.0  # Bottom biome radius
@export var spire_base_sides: int = 10  # Bottom biome polygon sides
@export var spire_radius_step: float = 5.0  # Radius reduction per biome going up
@export var spire_sides_step: int = 2  # Sides reduction per biome going up
@export var spire_min_sides: int = 3  # Minimum polygon sides

# Connector settings (rectangular prisms)
@export var edge_connector_width: float = 8.0  # Edge connector width (horizontal)
@export var edge_connector_height: float = 8.0  # Edge connector height (vertical)
@export var crosslink_width: float = 20.0  # Crosslink width (horizontal)
@export var crosslink_height: float = 15.0  # Crosslink height (vertical)
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
	"tri_norm": [[0, 2], [2, 4], [0, 4]], # a triangle
	"tri_strk": [[1, 3], [3, 5], [1, 5], [2, 4]], # a triangle struck by a line
	"zed_strk": [[0, 3], [1, 2], [4, 5], [2, 5]], # a Z shape struck by a line
	"rect": [[0, 1], [1, 3], [3, 4], [0, 4]], # a rectangle
	"kite": [[0, 2], [2, 4] , [4, 5], [0, 5]], # a kite
	
}

# Per-biome crosslink pattern weights (index = biome, from bottom to top)
# Each biome has a dictionary of pattern_name: weight for weighted random selection
@export var biome_crosslink_patterns: Array[Dictionary] = [
	{"full": 0.6, "empty": 0.2, "tri_norm": 0.2, "kite": 0.1},  # biome 0 (bottom)
	{"empty": 0.3, "single": 0.2, "zed_strk":0.1, "dagger":0.15, "rect":0.15},  # biome 1
	{"empty": 0.2, "single": 0.2, "cross":0.1, "tri_strk":0.15, "dagger_strk":0.15},  # biome 2
	{"empty": 0.4, "zed_strk": 0.1, "tri_norm":0.1, "dagger_strk":0.1, "double":0.1},  # biome 3 (top)
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
@export var building_seed_spacing: float = 90.0
@export var building_max_depth: int = 5
@export var building_branch_chance: float = 0.5
@export var building_max_total: int = 500
@export var buildings_on_crosslinks: bool = true
@export var buildings_on_edges: bool = false

# Top seeds (sitting on crosslinks)
@export_subgroup("Top Seeds")
@export var top_seeds_enabled: bool = true
@export var top_seed_probability: float = 0.3
@export_flags("Small", "Medium", "Large") var top_seed_sizes: int = SF.LARGE

# Bottom seeds (hanging beneath crosslinks)
@export_subgroup("Bottom Seeds")  
@export var bottom_seeds_enabled: bool = true
@export var bottom_seed_probability: float = 0.2
@export_flags("Small", "Medium", "Large") var bottom_seed_sizes: int = SF.MEDIUM

# Edge connector overrides (when buildings_on_edges is true)
@export_subgroup("Edge Seeds")
@export_flags("Small", "Medium", "Large") var edge_top_sizes: int = SF.MEDIUM
@export_flags("Small", "Medium", "Large") var edge_bottom_sizes: int = SF.SMALL

var building_generator: BuildingGenerator

# Stored connector data for building generation: [{start, end, height, biome_idx}]
var connector_data: Array[Dictionary] = []

@export_category("Spawning")
@export var spawn_fcar: bool = true
@export var fcar_spawn_height: float = 610.0  # Spawn car at this height

func _ready():
	_create_containers()
	if show_ground_grid:
		_create_ground_grid()
	
	# Use call_deferred to start async generation after scene is ready
	call_deferred("_start_generation")

func _start_generation():
	await generate_city()
	
	if spawn_fcar:
		_try_spawn_fcar()


func _try_spawn_fcar():
	# Look for FCar scene (user needs to save it from main.tscn first)
	var fcar_path = "res://f_car.tscn"
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
	city_generation_started.emit()
	
	print("CityGenerator: Starting city generation...")
	print("  Hex edge length: %.0fm" % hex_edge_length)
	print("  Grid rings: %d" % grid_rings)
	
	city_generation_progress.emit("setup", 0.0, "Clearing previous...")
	_clear_generated()
	await get_tree().process_frame
	
	city_generation_progress.emit("grid", 0.1, "Generating hex grid...")
	_generate_hex_grid()
	await get_tree().process_frame
	
	city_generation_progress.emit("spires", 0.2, "Generating spires...")
	_generate_spires()
	await get_tree().process_frame
	
	city_generation_progress.emit("crosslinks", 0.3, "Generating crosslinks...")
	_generate_crosslinks()
	await get_tree().process_frame
	
	city_generation_progress.emit("connectors", 0.4, "Generating connectors...")
	_generate_connectors()
	await get_tree().process_frame
	
	if generate_buildings:
		city_generation_progress.emit("buildings", 0.5, "Generating buildings...")
		await _generate_buildings()
	
	city_generation_progress.emit("complete", 1.0, "Done!")
	print("CityGenerator: Done! Generated %d spires, %d connectors" % [spire_positions.size(), connector_edges.size()])
	
	city_generation_complete.emit()


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

					var connector = _create_connector(start_pos, end_pos, connector_y, biome_idx, edge_connector_width, edge_connector_height)
					connector.name = "EdgeConn_%d_B%d_%s_%d" % [hex_idx, biome_idx, pattern_name, connector_count]
					connectors_container.add_child(connector)
					connector_count += 1

					# Store for building generation
					connector_data.append({
						"start": Vector3(start_pos.x, connector_y, start_pos.z),
						"end": Vector3(end_pos.x, connector_y, end_pos.z),
						"biome_idx": biome_idx,
						"is_edge": true,
						"width": edge_connector_width,
						"height": edge_connector_height
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

					var connector = _create_connector(start_pos, end_pos, connector_y, biome_idx, crosslink_width, crosslink_height)
					connector.name = "Crosslink_%d_B%d_%s_%d" % [hex_idx, biome_idx, pattern_name, crosslink_count]
					connectors_container.add_child(connector)
					crosslink_count += 1

					# Store for building generation
					connector_data.append({
						"start": Vector3(start_pos.x, connector_y, start_pos.z),
						"end": Vector3(end_pos.x, connector_y, end_pos.z),
						"biome_idx": biome_idx,
						"is_edge": false,
						"width": crosslink_width,
						"height": crosslink_height
					})

	print("  Generated %d crosslink beams (skipped %d overlaps)" % [crosslink_count, skipped_count])


func _create_connector(start: Vector3, end: Vector3, height: float, biome_idx: int, width: float, box_height: float) -> Node3D:
	var connector_root = Node3D.new()

	# Calculate position and rotation
	var start_3d = Vector3(start.x, height, start.z)
	var end_3d = Vector3(end.x, height, end.z)
	var midpoint = (start_3d + end_3d) / 2.0
	var direction = end_3d - start_3d
	var length = direction.length()

	connector_root.position = midpoint
	connector_root.rotation.y = atan2(direction.x, direction.z)  # Point toward end

	# Create box mesh (length along Z after rotation)
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(width, box_height, length)
	mesh_instance.mesh = box

	# Material - slightly darker than spire biome color
	var mat = StandardMaterial3D.new()
	var base_color = biome_colors[biome_idx] if biome_idx < biome_colors.size() else Color.GRAY
	mat.albedo_color = base_color.darkened(0.2)
	mesh_instance.material_override = mat

	connector_root.add_child(mesh_instance)

	# Create collision body with matching box shape
	var collision_body = StaticBody3D.new()
	collision_body.name = "ConnectorCollision"
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(width, box_height, length)
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)
	connector_root.add_child(collision_body)

	return connector_root


func _create_spire(pos: Vector3, biome_height: float) -> Node3D:
	var spire_root = Node3D.new()
	spire_root.position = pos

	# Create a StaticBody3D for collision
	var collision_body = StaticBody3D.new()
	collision_body.name = "SpireCollision"
	spire_root.add_child(collision_body)

	# Create a prism/cylinder mesh for each biome section
	# Each biome has decreasing radius and sides going upward
	for i in range(biome_count):
		var section = MeshInstance3D.new()
		section.name = "Biome_%d" % i

		# Calculate radius and sides for this biome level
		var top_radius = spire_base_radius - (i * spire_radius_step)
		var sides = maxi(spire_min_sides, spire_base_sides - (i * spire_sides_step))

		# Bottom biome gets a tapered foundation (2x radius at base)
		var bottom_radius = top_radius
		if i == 0:
			bottom_radius = top_radius * 1

		# Create cylinder/prism mesh
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = top_radius
		cylinder.bottom_radius = bottom_radius
		cylinder.height = biome_height
		cylinder.radial_segments = sides
		section.mesh = cylinder

		# Position (cylinder origin is center, so offset by half height)
		section.position.y = biome_height * i + biome_height / 2.0

		# Material with biome color
		var mat = StandardMaterial3D.new()
		mat.albedo_color = biome_colors[i] if i < biome_colors.size() else Color.WHITE
		section.material_override = mat

		spire_root.add_child(section)

		# Create collision shape for this section
		var collision_shape = CollisionShape3D.new()
		collision_shape.name = "Collision_%d" % i
		var shape = CylinderShape3D.new()
		# Use the larger radius for collision (safer)
		shape.radius = min(top_radius, bottom_radius)
		shape.height = biome_height
		collision_shape.shape = shape
		collision_shape.position.y = biome_height * i + biome_height / 2.0
		collision_body.add_child(collision_shape)

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


func _calculate_spire_aabbs() -> Array[AABB]:
	# Calculate AABBs for all spires to prevent building overlap
	var aabbs: Array[AABB] = []

	for pos in spire_positions:
		# Use the largest radius (bottom biome) for conservative AABB
		var radius = spire_base_radius
		# AABB covers entire spire height
		var aabb_pos = Vector3(pos.x - radius, 0, pos.z - radius)
		var aabb_size = Vector3(radius * 2, spire_height, radius * 2)
		aabbs.append(AABB(aabb_pos, aabb_size))

	return aabbs


func _calculate_connector_aabbs() -> Array[AABB]:
	# Calculate AABBs for all connectors to prevent building overlap
	var aabbs: Array[AABB] = []

	for conn in connector_data:
		var start: Vector3 = conn.start
		var end: Vector3 = conn.end
		var width: float = conn.width
		var height: float = conn.height

		# Calculate connector midpoint and direction
		var midpoint = (start + end) / 2.0
		var direction = end - start
		var length = direction.length()

		# Create axis-aligned bounding box that encompasses the rotated box
		# For a rotated box, we need to consider both dimensions
		var half_width = width / 2.0
		var half_height = height / 2.0
		var half_length = length / 2.0

		# Get rotation angle
		var angle = atan2(direction.x, direction.z)

		# Calculate the AABB size accounting for rotation
		# The rotated box projects onto X and Z axes
		var cos_a = abs(cos(angle))
		var sin_a = abs(sin(angle))
		var aabb_x = half_width * cos_a + half_length * sin_a
		var aabb_z = half_width * sin_a + half_length * cos_a

		var aabb_pos = Vector3(midpoint.x - aabb_x, midpoint.y - half_height, midpoint.z - aabb_z)
		var aabb_size = Vector3(aabb_x * 2, height, aabb_z * 2)
		aabbs.append(AABB(aabb_pos, aabb_size))

	return aabbs


func _generate_buildings():
	if not building_generator:
		push_error("CityGenerator: BuildingGenerator not initialized")
		return
	
	# Configure generator
	building_generator.max_growth_depth = building_max_depth
	building_generator.branch_probability = building_branch_chance
	building_generator.max_structural_blocks = building_max_total
	building_generator.max_decoration_blocks = int(building_max_total * 0.3)  # 30% extra for decorations
	building_generator.decoration_probability = 0.4
	building_generator.reset()
	
	# Register spire AABBs
	var spire_aabbs = _calculate_spire_aabbs()
	building_generator.register_external_aabbs(spire_aabbs)
	
	# Connect progress signals (disconnect first in case of regeneration)
	if building_generator.generation_progress.is_connected(_on_building_progress):
		building_generator.generation_progress.disconnect(_on_building_progress)
	building_generator.generation_progress.connect(_on_building_progress)
	
	city_generation_progress.emit("buildings", 0.0, "Queueing seeds...")
	await get_tree().process_frame
	
	# Queue seeds
	var top_count = 0
	var bottom_count = 0
	
	for conn in connector_data:
		var is_edge: bool = conn.get("is_edge", true)
		if is_edge and not buildings_on_edges:
			continue
		if not is_edge and not buildings_on_crosslinks:
			continue
		
		var start: Vector3 = conn.start
		var end: Vector3 = conn.end
		var biome_idx: int = conn.biome_idx
		var conn_height: float = conn.height
		
		var direction = end - start
		var length = direction.length()
		var dir_normalized = direction.normalized()
		
		var usable_length = length - spire_base_radius * 2 - building_seed_spacing
		if usable_length <= 0:
			continue
		
		var num_seeds = int(usable_length / building_seed_spacing)
		var start_offset = spire_base_radius + building_seed_spacing * 0.5
		var connector_heading = atan2(dir_normalized.x, dir_normalized.z)
		
		var current_top_sizes: int = edge_top_sizes if is_edge else top_seed_sizes
		var current_bottom_sizes: int = edge_bottom_sizes if is_edge else bottom_seed_sizes
		var seed_type: int = TF.SEED
		
		for i in range(num_seeds):
			var t = start_offset + building_seed_spacing * i
			var seed_pos = start + dir_normalized * t
			var center_y = seed_pos.y
			var half_height = conn_height / 2.0
			
			if top_seeds_enabled and randf() <= top_seed_probability:
				var top_pos = Vector3(seed_pos.x, center_y + half_height, seed_pos.z)
				building_generator.queue_seed(top_pos, Vector3.UP, biome_idx, seed_type, current_top_sizes, connector_heading)
				top_count += 1
			
			if bottom_seeds_enabled and randf() <= bottom_seed_probability:
				var bottom_pos = Vector3(seed_pos.x, center_y - half_height, seed_pos.z)
				building_generator.queue_seed(bottom_pos, Vector3.DOWN, biome_idx, seed_type, current_bottom_sizes, connector_heading)
				bottom_count += 1
	
	print("  Queued %d top + %d bottom = %d total seeds" % [top_count, bottom_count, top_count + bottom_count])
	city_generation_progress.emit("buildings", 0.1, "Processing %d seeds..." % (top_count + bottom_count))
	
	# Run async generation (yields periodically)
	await building_generator.process_queue()
	
	city_generation_progress.emit("buildings", 1.0, "Buildings complete")


func _on_building_progress(current: int, message: String):
	# Forward to city generation progress
	var max_blocks = building_generator.max_structural_blocks + building_generator.max_decoration_blocks
	var progress = float(current) / max(max_blocks, 1)
	city_generation_progress.emit("buildings", 0.1 + progress * 0.9, message)

func generate_city_sync():
	print("CityGenerator: Starting city generation (sync)...")
	_clear_generated()
	_generate_hex_grid()
	_generate_spires()
	_generate_crosslinks()
	_generate_connectors()
	
	if generate_buildings:
		_generate_buildings_sync()
	
	print("CityGenerator: Done!")


func _generate_buildings_sync():
	if not building_generator:
		return
	
	building_generator.max_growth_depth = building_max_depth
	building_generator.branch_probability = building_branch_chance
	building_generator.max_structural_blocks = building_max_total
	building_generator.max_decoration_blocks = int(building_max_total * 0.3)
	building_generator.decoration_probability = 0.4
	building_generator.reset()
	
	var spire_aabbs = _calculate_spire_aabbs()
	building_generator.register_external_aabbs(spire_aabbs)
	
	# Queue seeds (same as async version but without awaits)
	for conn in connector_data:
		var is_edge: bool = conn.get("is_edge", true)
		if is_edge and not buildings_on_edges:
			continue
		if not is_edge and not buildings_on_crosslinks:
			continue
		
		var start: Vector3 = conn.start
		var end: Vector3 = conn.end
		var biome_idx: int = conn.biome_idx
		var conn_height: float = conn.height
		
		var direction = end - start
		var length = direction.length()
		var dir_normalized = direction.normalized()
		
		var usable_length = length - spire_base_radius * 2 - building_seed_spacing
		if usable_length <= 0:
			continue
		
		var num_seeds = int(usable_length / building_seed_spacing)
		var start_offset = spire_base_radius + building_seed_spacing * 0.5
		var connector_heading = atan2(dir_normalized.x, dir_normalized.z)
		
		var current_top_sizes: int = edge_top_sizes if is_edge else top_seed_sizes
		var current_bottom_sizes: int = edge_bottom_sizes if is_edge else bottom_seed_sizes
		var seed_type: int = TF.SEED
		
		for i in range(num_seeds):
			var t = start_offset + building_seed_spacing * i
			var seed_pos = start + dir_normalized * t
			var center_y = seed_pos.y
			var half_height = conn_height / 2.0
			
			if top_seeds_enabled and randf() <= top_seed_probability:
				var top_pos = Vector3(seed_pos.x, center_y + half_height, seed_pos.z)
				building_generator.queue_seed(top_pos, Vector3.UP, biome_idx, seed_type, current_top_sizes, connector_heading)
			
			if bottom_seeds_enabled and randf() <= bottom_seed_probability:
				var bottom_pos = Vector3(seed_pos.x, center_y - half_height, seed_pos.z)
				building_generator.queue_seed(bottom_pos, Vector3.DOWN, biome_idx, seed_type, current_bottom_sizes, connector_heading)
	
	building_generator.process_queue_sync()

# Public API for regeneration
func regenerate():
	generate_city()
