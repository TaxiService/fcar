class_name TrafficCar
extends Node3D

enum State { INACTIVE, CRUISING, DISTURBED }

static var lod_camera: Camera3D = null

var state: State = State.INACTIVE
var route_index: int = -1
var curve_offset: float = 0.0
var tube_offset: Vector3 = Vector3.ZERO
var speed: float = 0.0
var target_speed: float = 0.0
var slot_index: int = -1

# Disturbed state (after player collision)
var disturbed_velocity: Vector3 = Vector3.ZERO
var disturbed_timer: float = 0.0
var disturbed_duration: float = 2.0

# Visual
var facing_direction: Vector3 = Vector3.FORWARD

# Collision half-extents for manual AABB check (used by FCar, not Godot physics)
var collision_half_extents: Vector3 = Vector3(1.0, 0.5, 2.0)

var _visual: Node3D = null

func set_visual(node: Node3D):
	_visual = node
	add_child(_visual)

func activate(route_idx: int, offset: float, tube_off: Vector3, spd: float):
	route_index = route_idx
	curve_offset = offset
	tube_offset = tube_off
	target_speed = spd
	speed = spd
	state = State.CRUISING
	visible = true
	disturbed_velocity = Vector3.ZERO
	disturbed_timer = 0.0

func deactivate():
	state = State.INACTIVE
	route_index = -1
	slot_index = -1
	curve_offset = 0.0
	speed = 0.0
	target_speed = 0.0
	tube_offset = Vector3.ZERO
	disturbed_velocity = Vector3.ZERO
	disturbed_timer = 0.0
	visible = false

func apply_disturbance(impact_velocity: Vector3, _impact_point: Vector3):
	state = State.DISTURBED
	disturbed_velocity = impact_velocity
	disturbed_timer = 0.0
