extends Node
# Autoload singleton - access via CityGrid or /root/CityGrid

# Global city infrastructure parameters
# This defines the "air traffic grid" that all vehicles align to

# Vertical structure
@export_category("Vertical Grid")
@export var pillar_height: float = 2000.0  # Total height of city pillars (meters)
@export var section_height: float = 500.0  # Height of each vertical section (meters)
@export var height_grid_spacing: float = 2.5  # Spacing between height-lock planes (meters)

# Horizontal structure (hex grid)
@export_category("Horizontal Grid")
@export var pillar_spacing: float = 1500.0  # Distance between pillars (meters) - TBD

# Derived values
var section_count: int:
	get: return int(pillar_height / section_height)

var planes_per_section: int:
	get: return int(section_height / height_grid_spacing)

# Current prototype section (0-indexed from bottom)
@export_category("Prototype")
@export var active_section: int = 1  # Middle-lower section (500m - 1000m)

var section_floor: float:
	get: return active_section * section_height

var section_ceiling: float:
	get: return (active_section + 1) * section_height


func _ready():
	print("CityGrid initialized:")
	print("  Pillar height: ", pillar_height, "m")
	print("  Sections: ", section_count, " x ", section_height, "m")
	print("  Planes per section: ", planes_per_section, " (", height_grid_spacing, "m spacing)")
	print("  Active section: ", active_section, " (", section_floor, "m - ", section_ceiling, "m)")


# Utility functions

func get_nearest_plane(height: float) -> float:
	# Returns the nearest grid plane to the given height
	return round(height / height_grid_spacing) * height_grid_spacing


func get_plane_index(height: float) -> int:
	# Returns the index of the nearest plane (0 = ground level)
	return int(round(height / height_grid_spacing))


func get_plane_height(index: int) -> float:
	# Returns the height of a specific plane index
	return index * height_grid_spacing


func is_in_active_section(height: float) -> bool:
	# Check if a height is within the current prototype section
	return height >= section_floor and height < section_ceiling


func get_section_for_height(height: float) -> int:
	# Which section does this height belong to?
	return int(height / section_height)
