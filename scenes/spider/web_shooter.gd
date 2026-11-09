extends Node3D
class_name WebShooter
## will be replaced by trail3D one day?
@export var web:MeshInstance3D;
@onready var web_string_mesh:CylinderMesh = web.mesh;
@export var raycast:RayCast3D;

func shoot_web(target:Vector3)->void:
	## TARGET - GLOBAL POSITION (raycast's collider_position)
	var distance:=web.global_position.distance_to(target);
	var offset:= distance/2.0;
	var duration := distance/10.0
	
	web.look_at(target, Vector3.UP);
	web.rotate_object_local(Vector3.RIGHT, PI/2.0)
	
	var t:= create_tween();
	t.set_trans(Tween.TRANS_CUBIC)
	t.set_ease(Tween.EASE_OUT)
	
	t.parallel().tween_property(web_string_mesh, "height", distance, duration);
	t.parallel().tween_property(web, "position", Vector3.UP * offset, duration)
