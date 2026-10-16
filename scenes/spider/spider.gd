extends Node3D
class_name Spider;
## encapsulate anything to do with the mesh itself to here

@export var explosion:MeshExploder

@export var animation:AnimationPlayer;
@export var skeleton:Skeleton3D;


## to check 
@export var feet:Array[RayCast3D];

@export var shield_highlight:SpotLight3D;


#@onready var pr1i:int = skeleton.find_bone("pivot_r1");
#@onready var pr2i:int = skeleton.find_bone("pivot_r2");
#@onready var pr3i:int = skeleton.find_bone("pivot_r3");
#@onready var pr4i:int = skeleton.find_bone("pivot_r4");
#
#@onready var pl1i:int = skeleton.find_bone("pivot_l1");
#@onready var pl2i:int = skeleton.find_bone("pivot_l2");
#@onready var pl3i:int = skeleton.find_bone("pivot_l3");
#@onready var pl4i:int = skeleton.find_bone("pivot_l4");
#
#@onready var pivots:Array[int] = [pr1i, pr2i, pr3i, pr4i, pl1i, pl2i, pl3i, pl4i]


const anim_scale = 1.5
const rotation_speed = 20
## TODO add a raycast to the tip of each leg and 
## make them pivot in a way where when the spiter is at the corner of a plank,
## the legs stick to the surface
func _physics_process(_delta: float) -> void:
	## reads input the same way movement does
	## which is ugly and bad and sucks
	## and we'll probably start everything over once we get a feel for the 
	## whole scope?
	var v:Vector2 = Input.get_vector("move_left", "move_right", "move_back", "move_forward");
	animation.speed_scale = v.y * anim_scale


func explode() -> void:
	explosion.emit_all();

func get_feet_colliders()->Array[Object]:
	var colliders:Array[Object] = [];
	for r:RayCast3D in feet:
		var c:Object = r.get_collider();
		if c:colliders.append(c)
	return colliders;


func _on_spider_died(_source:Crawler.DeathType) -> void:
	explode();

func check_board_death(board:StaticBody3D)->void:
	var touching_feet:int=0;
	for f:RayCast3D in feet:
		if f.get_collider() == board:
			touching_feet += 1;
	if touching_feet:
		get_parent().board_death(board)
#
#

func _on_spider_fly_consumed(fly: Fly) -> void:
	const ft = Fly.Type;
	match fly.type:
		ft.shield:
			shield_highlight.show()

func _on_spider_shield_lost() -> void:
	shield_highlight.hide();





func _on_board_container_board_dropped(board: StaticBody3D) -> void:
	check_board_death(board)
