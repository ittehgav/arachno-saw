extends PathFollow3D
class_name BoardPathFollow
## makes itself move
@export var moving:bool=false
@export var board_0:StaticBody3D

signal turned(axis:String);

var moving_x:bool=true;

const base_speed = 1;
const x_meters_per_second = 150
const z_meters_per_second = 50;

## gets incremented by run
var accel:float = 1.0;

	
func _enter_tree() -> void:
	GLB.board_path_follow = self;

func _ready()->void:
	board_0.set_collision_layer_value(1, true)
	## will be attached to more view/movement updates?
	
	turned.emit("x")


func _physics_process(delta: float) -> void:
	if moving:
		if moving_x:
			progress += delta * base_speed * x_meters_per_second * accel
		else:
			progress += delta * base_speed * z_meters_per_second * accel;



func _on_turn_scan_area_entered(_area: Area3D) -> void:
	## turn = switch from x to z movement
	moving_x = not moving_x
	var axis:String;
	if moving_x:
		axis = "x";
	else:
		axis = "z";
	turned.emit(axis);
