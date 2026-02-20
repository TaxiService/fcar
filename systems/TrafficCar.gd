class_name TrafficCar
extends Node3D

static var lod_camera: Camera3D = null

var route_index: int = -1
var slot_index: int = -1
var data_index: int = -1

# Visual
var facing_direction: Vector3 = Vector3.FORWARD

var _visual: Node3D = null

func set_visual(node: Node3D):
	_visual = node
	add_child(_visual)

func activate(route_idx: int, offset: float, tube_off: Vector3, spd: float):
	route_index = route_idx
	visible = true

func deactivate():
	route_index = -1
	slot_index = -1
	data_index = -1
	visible = false
