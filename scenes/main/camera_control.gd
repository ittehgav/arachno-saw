extends Node3D

@export var pcam:PhantomCamera3D;

## CAMERA CONTROL
## cameras will follow spider as it moves 90 degree slopes via area3Ds
## areas will regenerate when boards are dropped
## each area will represent a direction relative to the board

## REGIONS 
## top
## left
## right
## bottom

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


const y_off = 100.0;
const z_off = 50.0;
var x_off:int = -40

const side_offsets:Dictionary[CameraAngle, Vector3] = {
	ca.top_right: Vector3(0, y_off, z_off),
	ca.top_left: Vector3(0, y_off, -z_off ),
	ca.bottom_left: Vector3(0, -y_off, -z_off),
	ca.bottom_right:Vector3(0, -y_off, z_off)
}


enum CameraRegion {
	top, right, bottom, left
};const cr = CameraRegion;
enum CameraAngle {
	top_right, top_left, bottom_right, bottom_left
};const ca = CameraAngle;


func _ready()->void:
	current_angle = ca.top_right
func _physics_process(_delta: float) -> void:
	var spider_gp:Vector3 = spider.global_position
	var center:Vector3 = Vector3(spider_gp.x, 0, 0);
	anchor.global_position = spider.global_position.move_toward(center, 30)
	anchor.global_position.x += x_off

@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
var current_angle:CameraAngle=-1:
	set(val):
		if val != current_angle:
			move_camera(val)
		current_angle = val;

const angles_coverage:Dictionary[CameraAngle, Array] = {
	ca.top_right:[cr.top, cr.right],
	ca.top_left:[cr.top, cr.left],
	ca.bottom_left:[cr.bottom, cr.left],
	ca.bottom_right:[cr.bottom, cr.right]
}

var current_region:CameraRegion=cr.top:
	set(val):
		if val not in angles_coverage[current_angle]:
			update_angle(val);
		current_region = val;

func update_angle(new_region:CameraRegion)->void:
	## catch every angle bc teleport might trigger
	match new_region:
		cr.top:
			match current_angle:
				ca.bottom_right:
					current_angle = ca.top_right;
					return
				ca.bottom_left:
					current_angle = ca.top_left;
					return
		cr.right:
			match current_angle:
				ca.top_left:
					current_angle = ca.top_right;
					return
				ca.bottom_left:
					current_angle = ca.top_right;
					return
		cr.bottom:
			match current_angle:
				ca.top_right:
					current_angle = ca.bottom_right;
					return
				ca.top_left:
					current_angle = ca.bottom_left;
					return
		cr.left:
				match current_angle:
					ca.top_right:
						current_angle = ca.top_left;
						return;
					ca.bottom_right:
						current_angle = ca.bottom_left


func move_camera(angle:CameraAngle)->void:
	var t:= create_tween();
	t.tween_property(pcam, "position", side_offsets[angle], .5)


	
func _on_top_body_entered(_body: Node3D) -> void:
	current_region = cr.top
func _on_bottom_body_entered(_body: Node3D) -> void:
	current_region = cr.bottom
func _on_left_body_entered(_body: Node3D) -> void:
	current_region = cr.left
func _on_right_body_entered(_body: Node3D) -> void:
	current_region = cr.right

func _on_behind_body_entered(_body: Node3D) -> void:
	if x_off > 0:
		var t := create_tween();
		t.tween_property(self, "x_off", x_off * -1, .5)
func _on_front_body_entered(_body: Node3D) -> void:
	if x_off < 0:
		var t := create_tween();
		t.tween_property(self, "x_off", x_off * -1, .5)



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
		while not cast.is_colliding() or cast.get_collider(0) == spider and not cast.get_collider(1):
			area.position += motion;
			moved += 1;
			cast.force_shapecast_update()
		motions[area] = moved
	
	var top_motion:float = motions[top_area];
	if top_motion:
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.z -= top_motion
			area.global_position.y -= top_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.y -= top_motion
			area.global_position.y -= top_motion/2
	
	var bottom_motion:float = motions[bottom_area];
	if bottom_motion:
		for area:Area3D in [right_area, left_area]:
			area.get_node("center").shape.size.z -= bottom_motion
			area.global_position.y += bottom_motion/2;
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.y -= bottom_motion
			area.global_position.y += bottom_motion/2
	
	var left_motion:float = motions[left_area];
	print(left_motion)
	if left_motion:
		for area:Area3D in [top_area, bottom_area]:
			area.get_node("center").shape.size.z -= left_motion
			area.global_position.z += left_motion/2;
	
		for area:Area3D in [front_area, back_area]:
			area.get_node("center").shape.size.z -= left_motion
			area.global_position.z += left_motion/2
	
	var right_motion:float = motions[right_area];
	print(right_motion)
	if right_motion:
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
	
	
func get_perpendicular_shapes(area:Area3D)->Array[CollisionShape3D]:
	var perp_areas:Array[Area3D]
	match area.name:
		"top", "bottom":
			perp_areas = [right_area, left_area, front_area, back_area];
		"right", "left":
			perp_areas = [top_area, bottom_area, front_area, back_area];
		"front", "back":
			perp_areas = [top_area, bottom_area, left_area, right_area];
	
	var shapes:Array[CollisionShape3D];
	for a:Area3D in perp_areas:
		shapes.append(a.get_node("center"));
	return shapes
func _on_board_container_boards_changed() -> void:
	adjust_quadrants.call_deferred()
