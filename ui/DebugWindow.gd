class_name DebugWindow
extends Control

# A simple debug info panel to demonstrate the windowing system
# Shows car status, passenger info, etc.

var car_ref: Node = null  # Reference to FCar
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1  # Update 10 times per second

# Labels
var speed_label: Label
var altitude_label: Label
var vertical_vel_label: Label
var booster_angles_label: Label
var passengers_label: Label
var ready_label: Label
var stability_label: Label


func _ready():
	_build_ui()


func _build_ui():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "-- CAR STATUS --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(title)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Speed
	speed_label = Label.new()
	speed_label.text = "Speed: ---"
	vbox.add_child(speed_label)

	# Altitude
	altitude_label = Label.new()
	altitude_label.text = "Altitude: ---"
	vbox.add_child(altitude_label)

	# Vertical velocity
	vertical_vel_label = Label.new()
	vertical_vel_label.text = "Vert Vel: ---"
	vbox.add_child(vertical_vel_label)

	# Booster angles
	booster_angles_label = Label.new()
	booster_angles_label.text = "Boosters: ---"
	vbox.add_child(booster_angles_label)

	# Stability
	stability_label = Label.new()
	stability_label.text = "Stability: ---"
	vbox.add_child(stability_label)

	# Another separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Ready for fares
	ready_label = Label.new()
	ready_label.text = "Ready: ---"
	vbox.add_child(ready_label)

	# Passengers
	passengers_label = Label.new()
	passengers_label.text = "Passengers: ---"
	vbox.add_child(passengers_label)

	# Apply style to all labels
	for child in vbox.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))


func set_car(car: Node):
	car_ref = car


func _process(delta: float):
	update_timer += delta
	if update_timer < UPDATE_INTERVAL:
		return
	update_timer = 0.0

	if not car_ref or not is_instance_valid(car_ref):
		return

	# Update speed
	if car_ref.has_method("get") and "linear_velocity" in car_ref:
		var vel = car_ref.linear_velocity as Vector3
		var speed = vel.length()
		var speed_kmh = speed * 3.6  # Convert m/s to km/h
		speed_label.text = "Speed: %.1f km/h" % speed_kmh

	# Update altitude
	altitude_label.text = "Altitude: %.1f m" % car_ref.global_position.y

	# Update vertical velocity
	if "linear_velocity" in car_ref:
		var vert_vel = car_ref.linear_velocity.y
		var direction = "^" if vert_vel > 0.5 else ("v" if vert_vel < -0.5 else "-")
		vertical_vel_label.text = "Vert Vel: %s %.1f m/s" % [direction, vert_vel]
		# Color based on direction
		if vert_vel > 0.5:
			vertical_vel_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		elif vert_vel < -0.5:
			vertical_vel_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		else:
			vertical_vel_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

	# Update booster angles
	if "booster_system" in car_ref and car_ref.booster_system:
		var bs = car_ref.booster_system
		booster_angles_label.text = "Thigh: %.0f  Shin: %.0f" % [bs.thigh_angle_left, bs.shin_angle_left]
	else:
		booster_angles_label.text = "Boosters: N/A"

	# Update stability
	if "is_stable" in car_ref:
		var stable = car_ref.is_stable
		stability_label.text = "Stability: %s" % ("STABLE" if stable else "UNSTABLE")
		stability_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3) if stable else Color(1.0, 0.3, 0.3))

	# Update ready status
	if "is_ready_for_fares" in car_ref:
		var ready = car_ref.is_ready_for_fares
		ready_label.text = "Ready: %s" % ("YES" if ready else "NO")
		ready_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3) if ready else Color(0.6, 0.6, 0.6))

	# Update passengers
	if "passengers" in car_ref:
		var count = car_ref.passengers.size()
		var capacity = car_ref.cargo_capacity if "cargo_capacity" in car_ref else 2
		passengers_label.text = "Passengers: %d/%d" % [count, capacity]

		# Check for hurried passengers
		var hurried_count = 0
		for p in car_ref.passengers:
			if is_instance_valid(p) and p.in_a_hurry:
				hurried_count += 1

		if hurried_count > 0:
			passengers_label.text += " (%d hurried!)" % hurried_count
			passengers_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			passengers_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
