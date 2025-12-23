extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0,1,5)

#func _process(delta):
	#look_at(target.global_position, Vector3.UP)
	#print(target.global_basis.x)
	#global_transform.origin = target.global_transform.origin 

@export var lerp_speed = 20
#@export var target: Node3D
#@export var offset = Vector3.ZERO

func _physics_process(delta):
	if !target:
		return

	var target_xform = target.global_transform.translated_local(offset)
	#var target_xform = target.global_transform.looking_at(target.global_transform.origin, Vector3.UP) #no
	global_transform = global_transform.interpolate_with(target_xform, lerp_speed * delta)

	look_at(target.global_transform.origin, Vector3.UP ) #target.transform.basis.y
