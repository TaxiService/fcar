class_name PersonPart
extends Sprite3D

enum PartType { CORE, BODY }

var part_type: PartType = PartType.BODY
var is_core: bool:
	get: return part_type == PartType.CORE
var source_person_id: int = 0
var tint_color: Color = Color.BLACK
var point_value: int = 0
var in_cargo: bool = false
var collecting: bool = false  # Flying toward car for pickup
var collect_target: Node3D = null  # The car to fly toward
var collision_immune_timer: float = 0.0
var at_rest: bool = false
var velocity: Vector3 = Vector3.ZERO
var base_y: float = 0.0
var bob_time: float = 0.0

static var _next_person_id: int = 0


static func allocate_person_id() -> int:
	var id = _next_person_id
	_next_person_id += 1
	return id


func _ready():
	# Disable built-in billboard (shader handles it)
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	double_sided = true

	# 130px * 0.006 = 0.78m visual size (~260px effective at 2x)
	pixel_size = 0.006

	# Origin at bottom center (half frame height in pixels)
	offset.y = 65.0


func set_part_color(color: Color):
	tint_color = color
	set_instance_shader_parameter("person_color", Vector3(color.r, color.g, color.b))
	set_instance_shader_parameter("pixel_lod", 0.0)


func start_collecting(target: Node3D):
	collecting = true
	collect_target = target
	at_rest = false
	collision_immune_timer = 99.0  # Immune while collecting


func _process(delta: float):
	# In cargo: hidden, no physics, no LOD — position set by FCar
	if in_cargo:
		visible = false
		return

	# Collecting: fly toward car
	if collecting:
		if not is_instance_valid(collect_target):
			collecting = false
			collect_target = null
			return
		var dir = (collect_target.global_position - global_position)
		var dist = dir.length()
		if dist < 1.0:
			# Arrived — FCar will finalize collection
			return
		global_position += dir.normalized() * 15.0 * delta
		visible = true
		return

	# Collision immunity countdown
	if collision_immune_timer > 0.0:
		collision_immune_timer -= delta

	if not at_rest:
		# Gravity
		velocity.y -= 9.8 * delta

		# Move
		global_position += velocity * delta

		# Horizontal drag
		velocity.x *= 0.95
		velocity.z *= 0.95

		# Ground clamp
		if global_position.y <= base_y:
			global_position.y = base_y
			velocity.y = 0.0

			# Check if horizontal speed is negligible
			var horiz_speed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
			if horiz_speed < 0.1:
				velocity = Vector3.ZERO
				at_rest = true
	else:
		# Bob gently when at rest (pickup item feel)
		bob_time += delta
		global_position.y = base_y + sin(bob_time * 3.0) * 0.05

	# Simple distance-based visibility (200m)
	var cam = Person.lod_camera
	if cam:
		var dx = global_position.x - cam.global_position.x
		var dz = global_position.z - cam.global_position.z
		visible = (dx * dx + dz * dz) < 40000.0  # 200m squared
