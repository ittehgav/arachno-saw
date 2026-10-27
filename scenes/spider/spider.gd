extends Node3D
class_name Spider;
## encapsulate anything to do with the mesh itself to here


@export var animation:AnimationPlayer;
@export var skeleton:Skeleton3D;


## to check 
@export var feet:Array[RayCast3D];

@export var shield_icon:Node3D;

@export var body_materials:Array[Material];


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




func get_feet_colliders()->Array[Object]:
	var colliders:Array[Object] = [];
	for r:RayCast3D in feet:
		var c:Object = r.get_collider();
		if c:colliders.append(c)
	return colliders;



func _on_spider_fly_consumed(fly: Fly) -> void:
	const ft = Fly.Type;
	match fly.type:
		ft.shield:
			shield_icon.show()

func _on_spider_shield_lost() -> void:
	shield_icon.hide();


func _on_board_container_boards_changed() -> void:
	_check_board_death()

func _check_board_death()->void:
	var dr:Array[StaticBody3D] = GLB.board_container.dropped_boards
	for f:RayCast3D in feet:
		var c:Object = f.get_collider()
		if c in dr:
			get_parent().board_death(c)
			return


func _on_spider_died(_source: Crawler.DeathType) -> void:
	var t:= create_tween();
	t.tween_property(self, "scale", scale * 0, .5);
