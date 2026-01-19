class_name ShiftManager
extends Node

# Shift-based scoring system for taxi fares

# Configuration
@export var max_speed: float = 22.2  # m/s (80 km/h) - reference for hurry calculations
@export var fares_per_shift: int = 10
@export var eject_min_progress: float = 0.4  # Must complete 40% of trip to get partial pay on eject

# Scoring constants
const BASE_FARE: int = 25  # Per trip
const PER_PERSON_FARE: int = 25  # Per passenger
const DISTANCE_DIVISOR: float = 20.0  # Distance in meters / this = bonus ₧
const HURRY_MULTIPLIER: float = 20.0  # Multiplier for hurry bonus calculation
const HURRY_TIME_BUFFER: float = 0.03  # 3 seconds per 100 meters added to minimum time

# Shift state
var shift_active: bool = false
var fare_count: int = 0
var total_score: int = 0

# Per-passenger tracking (keyed by person instance_id)
# Stores: { pickup_pos, destination_pos, original_distance, board_time, in_a_hurry, group_size }
var active_fares: Dictionary = {}

# Track which group_ids have already been counted this frame/delivery cycle
var _counted_groups: Dictionary = {}  # group_id -> true

# Reference to FCar (set externally)
var fcar: Node = null

# Signals
signal fare_completed(score: int, breakdown: Dictionary)
signal shift_started()
signal shift_ended(total_score: int)
signal score_updated(new_total: int, fare_count: int)


func _ready():
	# Try to find FCar and connect signals
	call_deferred("_connect_to_fcar")


func _connect_to_fcar():
	if fcar:
		_connect_signals()
		return

	# Try to find FCar in the scene
	var root = get_tree().root
	fcar = _find_node_by_class(root, "FCar")
	if fcar:
		_connect_signals()
		print("ShiftManager: Connected to FCar")
	else:
		push_warning("ShiftManager: FCar not found")


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == class_name_str:
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


func _connect_signals():
	if not fcar:
		return

	if not fcar.passenger_boarded.is_connected(_on_passenger_boarded):
		fcar.passenger_boarded.connect(_on_passenger_boarded)
	if not fcar.passenger_delivered.is_connected(_on_passenger_delivered):
		fcar.passenger_delivered.connect(_on_passenger_delivered)
	if not fcar.passenger_ejected.is_connected(_on_passenger_ejected):
		fcar.passenger_ejected.connect(_on_passenger_ejected)


func _on_passenger_boarded(person: Node):
	# Start shift on first fare
	if not shift_active:
		_start_shift()

	# Capture fare data at pickup time
	var person_id = person.get_instance_id()
	var pickup_pos = fcar.global_position
	var destination_pos = Vector3.ZERO

	if is_instance_valid(person.destination):
		destination_pos = person.destination.global_position

	var original_distance = pickup_pos.distance_to(destination_pos)

	# Count group size (how many people with same group_id are boarding)
	var group_size = 1
	if person.group_id != -1:
		group_size = _count_group_members_boarding(person.group_id)

	active_fares[person_id] = {
		"pickup_pos": pickup_pos,
		"destination_pos": destination_pos,
		"original_distance": original_distance,
		"board_time": Time.get_ticks_msec() / 1000.0,
		"in_a_hurry": person.in_a_hurry,
		"group_size": group_size,
		"group_id": person.group_id
	}

	print("ShiftManager: Tracking fare - distance: %.0fm, hurry: %s, group: %d" % [original_distance, person.in_a_hurry, group_size])


func _count_group_members_boarding(group_id: int) -> int:
	# Count passengers in FCar with matching group_id
	var count = 0
	for passenger in fcar.passengers:
		if is_instance_valid(passenger) and passenger.group_id == group_id:
			count += 1
	return max(1, count)


func _on_passenger_delivered(person: Node, destination: Node):
	var person_id = person.get_instance_id()

	if not active_fares.has(person_id):
		push_warning("ShiftManager: Delivered passenger not tracked")
		return

	var fare_data = active_fares[person_id]
	var actual_time = (Time.get_ticks_msec() / 1000.0) - fare_data.board_time

	# Only count fare once per group (use first member delivered)
	var should_count_fare = true
	if fare_data.group_id != -1:
		# Check if we already counted this group
		should_count_fare = not _group_already_counted(fare_data.group_id)

	if should_count_fare:
		var breakdown = _calculate_fare_score(fare_data, actual_time)
		total_score += breakdown.total
		fare_count += 1

		print("ShiftManager: Fare %d complete! +%d₧ (base:%d person:%d dist:%d hurry:%d)" % [
			fare_count, breakdown.total, breakdown.base, breakdown.per_person,
			breakdown.distance, breakdown.hurry
		])

		fare_completed.emit(breakdown.total, breakdown)
		score_updated.emit(total_score, fare_count)

		# Check for shift end
		if fare_count >= fares_per_shift:
			_end_shift()

	# Clean up tracking
	active_fares.erase(person_id)


func _group_already_counted(group_id: int) -> bool:
	# Check if we already counted a fare for this group
	if _counted_groups.has(group_id):
		return true
	# Mark this group as counted
	_counted_groups[group_id] = true
	return false


func _on_passenger_ejected(person: Node):
	var person_id = person.get_instance_id()

	if not active_fares.has(person_id):
		return

	var fare_data = active_fares[person_id]

	# Calculate progress (how far did we travel toward destination?)
	var current_pos = fcar.global_position
	var distance_traveled = fare_data.pickup_pos.distance_to(current_pos)
	var progress = distance_traveled / fare_data.original_distance if fare_data.original_distance > 0 else 0.0

	# Only count fare once per group
	var should_count_fare = true
	if fare_data.group_id != -1:
		should_count_fare = not _group_already_counted(fare_data.group_id)

	if should_count_fare:
		var partial_score = 0

		if progress >= eject_min_progress:
			# Pay partial distance bonus based on progress
			var full_distance_bonus = ceili(fare_data.original_distance / DISTANCE_DIVISOR)
			partial_score = int(full_distance_bonus * progress)

			print("ShiftManager: Ejected at %.0f%% progress, partial pay: %d₧" % [progress * 100, partial_score])
		else:
			print("ShiftManager: Ejected too early (%.0f%%), no pay" % [progress * 100])

		if partial_score > 0:
			total_score += partial_score
			fare_count += 1

			var breakdown = {
				"base": 0,
				"per_person": 0,
				"distance": partial_score,
				"hurry": 0,
				"total": partial_score,
				"ejected": true,
				"progress": progress
			}

			fare_completed.emit(partial_score, breakdown)
			score_updated.emit(total_score, fare_count)

			if fare_count >= fares_per_shift:
				_end_shift()

	active_fares.erase(person_id)


func _calculate_fare_score(fare_data: Dictionary, actual_time: float) -> Dictionary:
	var base = BASE_FARE
	var per_person = PER_PERSON_FARE * fare_data.group_size
	var distance_bonus = ceili(fare_data.original_distance / DISTANCE_DIVISOR)

	var hurry_bonus = 0
	if fare_data.in_a_hurry and actual_time > 0.01:  # Guard against division by zero
		var min_time = fare_data.original_distance / max_speed
		var reasonable_time = min_time + (fare_data.original_distance * HURRY_TIME_BUFFER)
		hurry_bonus = int(HURRY_MULTIPLIER * reasonable_time / actual_time)

	return {
		"base": base,
		"per_person": per_person,
		"distance": distance_bonus,
		"hurry": hurry_bonus,
		"total": base + per_person + distance_bonus + hurry_bonus,
		"ejected": false
	}


func _start_shift():
	shift_active = true
	fare_count = 0
	total_score = 0
	active_fares.clear()
	_counted_groups.clear()

	print("ShiftManager: === SHIFT STARTED ===")
	shift_started.emit()
	score_updated.emit(total_score, fare_count)


func _end_shift():
	shift_active = false

	print("ShiftManager: === SHIFT COMPLETE === Total: %d₧ ===" % total_score)
	shift_ended.emit(total_score)


# Public API

func get_score() -> int:
	return total_score


func get_fare_count() -> int:
	return fare_count


func is_shift_active() -> bool:
	return shift_active


func get_shift_progress() -> String:
	return "%d/%d" % [fare_count, fares_per_shift]
