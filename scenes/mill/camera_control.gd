extends Node3D

@export var pcam:PhantomCamera3D;

## camera control:
## camera will follow spider from a certain angle with some dampening

## always starts at top
@export var top_area:Area3D;
@export var right_area:Area3D;
@export var left_area:Area3D;
@export var bottom_area:Area3D;

@export var back_area:Area3D;
@export var front_area:Area3D

@onready var areas:Array[Area3D] = [top_area, bottom_area, left_area, right_area, front_area, back_area]

@export var anchor:Node3D;
@export var spider:Crawler

func adjust_quadrants()->void:
	var shapes:Array[CollisionShape3D]
	var motions:Dictionary[Area3D, float]
	for area:Area3D in areas:
		shapes.append(area.get_node("center"))
		var motion:=Vector3.ZERO;
		match area.name:
			"top":
				motion.y = -1;
			"bottom":
				motion.y = 1;
			"right":
				motion.z = -1;
			"left":
				motion.z = 1;
			"behind":
				motion.x = 1;
			"front":
				motion.x = -1;
		
		var cast:ShapeCast3D = area.get_node("ShapeCast3D");
		cast.force_shapecast_update()
		var moved:int = 0;
		while not cast.is_colliding() or (cast.get_collider(0) == spider and not cast.get_collider(1)):
			area.position += motion;
			moved += 1;
			cast.force_shapecast_update()
		motions[area] = moved
	
	var top_motion:float = motions[top_area];
	if top_motion:
		for shape:CollisionShape3D in [top_area.get_node("left"), top_area.get_node("right")]:
			shape.shape.radius -= top_motion/2
		
		
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.z -= top_motion
			area.global_position.y -= top_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.y -= top_motion
			area.global_position.y -= top_motion/2


	var bottom_motion:float = motions[bottom_area];
	if bottom_motion:
		for shape:CollisionShape3D in [bottom_area.get_node("left"), bottom_area.get_node("right")]:
			shape.shape.radius -= bottom_motion/2
			
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.z -= bottom_motion
			area.global_position.y += bottom_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.y -= bottom_motion
			area.global_position.y += bottom_motion/2


	var left_motion:float = motions[left_area];
	if left_motion:
		for shape:CollisionShape3D in [left_area.get_node("left"), left_area.get_node("right")]:
			shape.shape.radius -= left_motion/2
		
		for area:Area3D in [top_area, bottom_area]:
			area.get_node("center").shape.size.z -= left_motion
			area.global_position.z += left_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.z -= left_motion
			area.global_position.z += left_motion/2


	var right_motion:float = motions[right_area];
	if right_motion:
		for shape:CollisionShape3D in [right_area.get_node("left"), right_area.get_node("right")]:
			shape.shape.radius -= right_motion/2
	
		for area:Area3D in [top_area, bottom_area]:
			area.get_node("center").shape.size.z -= right_motion
			area.global_position.z -= right_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.z -= right_motion
			area.global_position.z -= right_motion/2


	var back_motion:float = motions[back_area];
	if back_motion:
		for area:Area3D in [top_area, bottom_area]:
			area.get_node("center").shape.size.x -= back_motion
			area.global_position.x += back_motion/2;
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.x -= back_motion
			area.global_position.x += back_motion/2
	
	var front_motion:float = motions[front_area];
	if front_motion:
		for area:Area3D in [top_area, bottom_area]:
			area.get_node("center").shape.size.x -= front_motion
			area.global_position.x -= front_motion/2;
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.x -= front_motion
			area.global_position.x -= front_motion/2

func _on_board_container_boards_changed() -> void:
	adjust_quadrants.call_deferred()


func _on_spider_died(_source: Crawler.DeathType) -> void:
	pcam.follow_mode = PhantomCamera3D.FollowMode.NONE;
	pcam.look_at_mode = PhantomCamera3D.LookAtMode.NONE;
	var t:= create_tween();
	t.tween_property(pcam.camera_3d_resource, "fov", pcam.fov + 30, 1)
