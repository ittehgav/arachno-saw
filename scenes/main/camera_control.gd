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
@onready var areas:Array[Area3D] = [top_area, right_area, left_area, bottom_area]

@export var anchor:Node3D;
@export var spider:Crawler


const y_off = 100.0;
const z_off = 100.0;
const x_off = 40

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
	anchor.global_position.x = spider.global_position.x - x_off
@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
var current_angle:CameraAngle=-1:
	set(val):
		if val != current_angle:
			print("mc? ", val)
			move_camera(val)
		current_angle = val;

const angles_coverage:Dictionary[CameraAngle, Array] = {
	ca.top_right:[cr.top, cr.right],
	ca.top_left:[cr.top, cr.left],
	ca.bottom_left:[cr.bottom, cr.left],
	ca.bottom_right:[cr.bottom, cr.right]
}

var current_region:CameraRegion=-1:
	set(val):
		if val not in angles_coverage[current_angle]:
			update_angle(val);
		current_region = val;

func update_angle(new_region:CameraRegion)->void:
	## catch every angle bc teleport might trigger
	match current_region:
		cr.top:
			match new_region:
				cr.left:
					current_angle = ca.top_left;
				cr.right, cr.bottom:
					current_angle = ca.top_right;
		cr.right:
			match new_region:
				cr.top:
					current_angle = ca.top_right;
				cr.bottom, cr.left:
					current_angle = ca.bottom_right;
		cr.bottom:
			match new_region:
				cr.right:
					current_angle = ca.bottom_right;
				cr.left, cr.top:
					current_angle = ca.bottom_left;
		cr.left:
			match new_region:
				cr.bottom:
					current_angle = ca.bottom_left;
				cr.top, cr.right:
					current_angle = ca.top_left
					
					

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
