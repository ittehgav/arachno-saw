extends PathFollow3D
class_name BoardPathFollow
## makes itself move
@export var moving:bool=false

var moving_x:bool=true;

const base_speed = 1;
const x_meters_per_second = 300
const z_meters_per_second = 50;


func _physics_process(delta: float) -> void:
	if moving:
		if moving_x:
			progress += delta *base_speed* x_meters_per_second
		else:
			progress += delta *base_speed* z_meters_per_second


func _on_board_path_board_reached_turn(turn_index: int) -> void:
	print("tur?")
