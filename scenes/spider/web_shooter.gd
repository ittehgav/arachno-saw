extends Node3D
class_name WebShooter
## handles input for web aswell as visual feedbacks
## only thing about web that's not here is how it affects the camera
@export var spider:Crawler

@export var web_fail_sfx:AudioStreamPlayer;
@export var web_shoot_sfx:AudioStreamPlayer;
@export var web_hit_sfx:AudioStreamPlayer;
@export var web_land_sfx:AudioStreamPlayer;


@export var camera_control:CameraControl
@export var crosshair:TextureRect;


## will be replaced by trail3D one day?
@export var web:MeshInstance3D;
@export var tip_node: Node3D

@export var relative_raycast:RayCast3D;
@export var raycast:RayCast3D;

var aim_valid:bool;

@onready var tip_origin: = tip_node.position;
@onready var web_origin: = web.position
@onready var raycast_origin: = raycast.position

const web_speed = 2000.0
func shoot_web(target:Vector3, body:StaticBody3D)->void:
	web_shoot_sfx.play()
	reset_web()
	await get_tree().process_frame
	show()
	shoot_web_cylinder(target)
	camera_control.move_camera_toward(target, web_speed)
	spider.disable_movement();

	
	spider.stage_switch_started.emit()
	
	await web_tween.finished
	var p:Node = body.get_parent();
	while not p is BodySplitPath:
		assert(not p is MainNode)
		p = p.get_parent();

	web_hit(target, p)

func web_hit(target:Vector3, path:BodySplitPath)->void:
	LevelControl.level_transition_started.emit()
	spider.reparent.bind(path.get_node("board_path_follow")).call_deferred()
	
	web_hit_sfx.play()
	camera_control.reset_camera();
	var t:= create_tween();
	spider.process_mode = Node.PROCESS_MODE_ALWAYS
	t.tween_property(spider, "global_position", target.move_toward(spider.global_position, 3), 1);
		
	spider.look_at(target, Vector3.UP)
	spider.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	
	await t.finished;
	spider.process_mode = Node.PROCESS_MODE_INHERIT
	LevelControl.next_level(path)
	spider.enable_movement()
	spider.stage_switch_ended.emit()
	reset_web()

	




var web_tween:Tween;
func shoot_web_cylinder(target:Vector3)->void:
	if web_tween and web_tween.is_running():
		web_tween.kill();
		
	
	var cyl:CylinderMesh = web.mesh;
	look_at(target);
	var distance:float = global_position.distance_to(target);
	var duration := distance/web_speed;
	web_tween = create_tween();
	web_tween.tween_property(cyl, "height", distance, duration);
	web_tween.parallel().tween_property(web, "global_position", web.global_position.move_toward(target, distance/2), duration)
	web_tween.parallel().tween_property(tip_node, "global_position", target, duration)

func reset_web()->void:
	hide();
	var cyl:CylinderMesh = web.mesh;
	cyl.height = .01;
	tip_node.position = Vector3.ZERO;
	web.position = Vector3.ZERO
	


func _update_stretch(tip: Vector3, mesh_instance: MeshInstance3D, origin: Vector3) -> void:
	mesh_instance.set_meta("stretch_tip", tip)

	var cyl := mesh_instance.mesh as CylinderMesh
	var dir := tip - origin
	var length := dir.length()
	if length < 0.001:
		return
	dir /= length

	# Resize the mesh so its height spans origin -> tip
	cyl.height = length

	# Orient the cylinder's Y axis along dir, centered at the midpoint
	var ref := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var right := ref.cross(dir).normalized()
	var fwd := right.cross(dir).normalized()
	var new_basis := Basis(right, dir, fwd)

	mesh_instance.global_transform = Transform3D(new_basis, origin + dir * length * 0.5)

	if tip_node:
		tip_node.global_position = tip
		tip_node.look_at(tip + dir, ref)

func _process(_delta:float)->void:
	if camera_control.aiming:
		if relative_raycast.is_colliding():
			raycast.look_at(relative_raycast.get_collision_point());
			crosshair.modulate.a = 1;
			aim_valid = true;
		else:
			crosshair.modulate.a = .5
			aim_valid = false;

func _input(e:InputEvent)->void:
	if camera_control.aiming and e.is_action_pressed("shoot_web"):
		if not aim_valid:
			web_fail_sfx.play();
		else:
			shoot_web(raycast.get_collision_point(), raycast.get_collider())
			
func _on_camera_control_started_aiming() -> void:
	crosshair.show()


func _on_camera_control_stopped_aiming() -> void:
	crosshair.hide()
