# PerformanceDebug.gd
# Real-time performance overlay - press F3 to toggle
# Shows FPS, draw calls, objects, and helps identify bottlenecks
class_name PerformanceDebug
extends CanvasLayer

@export var toggle_key: Key = KEY_F3
@export var update_interval: float = 0.25  # Update 4x per second

var _panel: PanelContainer
var _label: Label
var _visible: bool = false
var _update_timer: float = 0.0

# Track frame times for more accurate measurement
var _frame_times: Array[float] = []
var _max_frame_samples: int = 30


func _ready():
	layer = 200
	_build_ui()
	_panel.visible = false


func _build_ui():
	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	
	# Dark semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	
	# Position top-left
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(10, 10)
	
	add_child(_panel)
	
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	_panel.add_child(_label)


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			toggle_key:
				_visible = !_visible
				_panel.visible = _visible
				get_viewport().set_input_as_handled()
			KEY_M:
				_debug_fill_nearby_zones()
				get_viewport().set_input_as_handled()
			KEY_N:
				_debug_print_nearby_zones()
				get_viewport().set_input_as_handled()
			KEY_B:
				_debug_spawn_at_camera()
				get_viewport().set_input_as_handled()
			KEY_V:
				_debug_inspect_people()
				get_viewport().set_input_as_handled()


func _process(delta: float):
	# Track frame time
	_frame_times.append(delta)
	if _frame_times.size() > _max_frame_samples:
		_frame_times.pop_front()
	
	if not _visible:
		return
	
	_update_timer += delta
	if _update_timer < update_interval:
		return
	_update_timer = 0.0
	
	_update_display()


func _update_display():
	var text = ""
	
	# === FPS & Frame Time ===
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var avg_frame_time = _get_average_frame_time() * 1000.0  # to ms
	var worst_frame_time = _get_worst_frame_time() * 1000.0
	
	text += "=== PERFORMANCE ===\n"
	text += "FPS: %.0f (%.1f ms avg, %.1f ms worst)\n" % [fps, avg_frame_time, worst_frame_time]
	
	# === CPU Indicators ===
	var process_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nav_time = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	
	text += "\n=== CPU ===\n"
	text += "Process: %.2f ms\n" % process_time
	text += "Physics: %.2f ms\n" % physics_time
	if nav_time > 0.01:
		text += "Navigation: %.2f ms\n" % nav_time
	
	# === Object Counts ===
	var object_count = Performance.get_monitor(Performance.OBJECT_COUNT)
	var node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphan_count = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	text += "\n=== OBJECTS ===\n"
	text += "Objects: %d\n" % object_count
	text += "Nodes: %d\n" % node_count
	if orphan_count > 0:
		text += "Orphans: %d (!)\n" % orphan_count
	
	# === RENDERING (GPU indicators) ===
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects_drawn = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vram_used = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	
	text += "\n=== RENDERING ===\n"
	text += "Draw Calls: %d\n" % draw_calls
	text += "Objects Drawn: %d\n" % objects_drawn
	text += "Primitives: %d\n" % primitives
	text += "VRAM: %.1f MB\n" % vram_used
	
	# === DIAGNOSIS ===
	text += "\n=== DIAGNOSIS ===\n"
	text += _get_diagnosis(fps, process_time, physics_time, draw_calls, objects_drawn, node_count)
	
	_label.text = text


func _get_average_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0
	var total = 0.0
	for t in _frame_times:
		total += t
	return total / _frame_times.size()


func _get_worst_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0
	var worst = 0.0
	for t in _frame_times:
		worst = max(worst, t)
	return worst


func _get_diagnosis(fps: float, process_ms: float, physics_ms: float, draw_calls: int, objects_drawn: int, nodes: int) -> String:
	var issues: Array[String] = []
	
	# Check for common problems
	if fps < 30:
		issues.append("⚠ LOW FPS!")
	
	# CPU bound indicators
	if process_ms > 10.0:
		issues.append("→ CPU: High _process time (%.1f ms)" % process_ms)
		issues.append("  Check scripts with expensive _process()")
	
	if physics_ms > 8.0:
		issues.append("→ CPU: High physics time (%.1f ms)" % physics_ms)
		issues.append("  Too many physics bodies?")
	
	if nodes > 10000:
		issues.append("→ CPU: Many nodes (%d)" % nodes)
		issues.append("  Consider pooling or culling")
	
	# GPU bound indicators
	if draw_calls > 1000:
		issues.append("→ GPU: High draw calls (%d)" % draw_calls)
		issues.append("  Enable batching, reduce materials")
	
	if objects_drawn > 2000:
		issues.append("→ GPU: Many objects drawn (%d)" % objects_drawn)
		issues.append("  Use visibility ranges or impostors")
	
	# If low FPS but no obvious cause
	if fps < 30 and issues.size() == 1:
		issues.append("→ Possibly GPU shader/fill-rate bound")
		issues.append("  Try lowering resolution or disabling effects")
	
	if issues.is_empty():
		return "✓ Performance looks OK"
	
	return "\n".join(issues)


# === Public API ===

func show_overlay():
	_visible = true
	_panel.visible = true


func hide_overlay():
	_visible = false
	_panel.visible = false


func is_overlay_visible() -> bool:
	return _visible


# === Debug Spawn Controls ===
# M = Fill nearby zones with people
# N = Print info about nearby zones
# B = Spawn people directly at camera position

func _get_people_manager() -> Node:
	# Try common paths
	for path in ["/root/CityTest/PeopleManager", "/root/Main/PeopleManager"]:
		if has_node(path):
			return get_node(path)
	# Search from root
	return _find_node_with_method(get_tree().root, "register_zone")


func _find_node_with_method(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child in node.get_children():
		var found = _find_node_with_method(child, method)
		if found:
			return found
	return null


func _get_camera_position() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if camera:
		return camera.global_position
	return Vector3.ZERO


func _debug_fill_nearby_zones():
	var pm = _get_people_manager()
	if not pm:
		print("[DEBUG] PeopleManager not found!")
		return

	var cam_pos = _get_camera_position()
	print("[DEBUG] M pressed - Filling zones near %s" % cam_pos)

	if pm.has_method("debug_fill_nearby_zones"):
		var spawned = pm.debug_fill_nearby_zones(cam_pos, 500.0, 200)
		print("[DEBUG] Spawned %d people in nearby zones" % spawned)
	else:
		print("[DEBUG] PeopleManager missing debug_fill_nearby_zones method")

	if pm.has_method("print_status"):
		pm.print_status()


func _debug_print_nearby_zones():
	var pm = _get_people_manager()
	if not pm:
		print("[DEBUG] PeopleManager not found!")
		return

	var cam_pos = _get_camera_position()
	print("[DEBUG] N pressed - Checking zones near %s" % cam_pos)

	if pm.has_method("debug_get_nearby_zones"):
		var zones = pm.debug_get_nearby_zones(cam_pos, 300.0)
		print("[DEBUG] Found %d zones within 300m:" % zones.size())
		for i in range(mini(10, zones.size())):
			var zone = zones[i]
			var dist = cam_pos.distance_to(zone.global_position)
			print("  Zone %d: pos=%s, dist=%.0fm, people=%d/%d, enabled=%s" % [
				i, zone.global_position, dist, zone.get_people_count(), zone.max_people, zone.enabled
			])
		if zones.size() > 10:
			print("  ... and %d more zones" % (zones.size() - 10))
	else:
		print("[DEBUG] PeopleManager missing debug_get_nearby_zones method")


func _debug_spawn_at_camera():
	var pm = _get_people_manager()
	if not pm:
		print("[DEBUG] PeopleManager not found!")
		return

	var cam_pos = _get_camera_position()
	# Spawn slightly below camera, in a grid
	var spawn_pos = cam_pos + Vector3(0, -5, -10)
	print("[DEBUG] B pressed - Spawning people at %s" % spawn_pos)

	if pm.has_method("spawn_person_at"):
		for i in range(5):
			var offset = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
			var person = pm.spawn_person_at(spawn_pos + offset)
			if person:
				print("  Spawned person at %s, visible=%s" % [person.global_position, person.visible])
			else:
				print("  Failed to spawn person!")
	else:
		print("[DEBUG] PeopleManager missing spawn_person_at method")


func _debug_inspect_people():
	var pm = _get_people_manager()
	if not pm:
		print("[DEBUG] PeopleManager not found!")
		return

	var cam_pos = _get_camera_position()
	print("[DEBUG] V pressed - Inspecting active people")

	var all_people = pm.get("all_people")
	if all_people == null:
		print("[DEBUG] Cannot access all_people array")
		return

	print("[DEBUG] Total active: %d" % all_people.size())

	# Find closest people to camera
	var people_with_dist: Array = []
	for person in all_people:
		if is_instance_valid(person):
			var dist = cam_pos.distance_to(person.global_position)
			people_with_dist.append({"person": person, "dist": dist})

	people_with_dist.sort_custom(func(a, b): return a.dist < b.dist)

	print("[DEBUG] 10 closest people:")
	for i in range(mini(10, people_with_dist.size())):
		var p = people_with_dist[i].person
		var dist = people_with_dist[i].dist
		print("  #%d: pos=%s, dist=%.0fm, visible=%s, state=%s" % [
			i, p.global_position, dist, p.visible,
			p.get("current_state") if p.get("current_state") != null else "?"
		])

	# Stats about positions
	if not people_with_dist.is_empty():
		var min_y = INF
		var max_y = -INF
		var avg_dist = 0.0
		for pd in people_with_dist:
			var pos = pd.person.global_position
			min_y = min(min_y, pos.y)
			max_y = max(max_y, pos.y)
			avg_dist += pd.dist
		avg_dist /= people_with_dist.size()
		print("[DEBUG] Y range: %.0f to %.0f, avg distance: %.0fm" % [min_y, max_y, avg_dist])
