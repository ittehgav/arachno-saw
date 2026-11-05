extends PathFollow3D
class_name BoardPathFollow
## makes itself move
@export var moving:bool=false
@export var board_0:StaticBody3D


signal point_reached(i:int, split_center:Node3D);

var moving_x:bool=true;

const base_speed = 1;
const x_meters_per_second = 100
const z_meters_per_second = 40;

@export var warning:MeshInstance3D

## gets incremented by run
var accel:float = 1.0;
@export var camera_anchor:Node3D;
@export var path:BodySplitPath
	
func _enter_tree() -> void:
	var p:Node = get_parent();
	while not p is BodySplitPath:
		p = p.get_parent();
	if p.is_in_group("extra_path_copy"):
		return;
	GLB.board_path_follow = self;

func _ready()->void:
	board_0.set_collision_layer_value(1, true)
	## will be attached to more view/movement updates?



func _physics_process(delta: float) -> void:
	if moving:
		if moving_x:
			progress += delta * base_speed * x_meters_per_second * accel
		else:
			progress += delta * base_speed * z_meters_per_second * accel;



func _on_turn_scan_area_entered(area: Area3D) -> void:
	## turn = switch from x to z movement
	var i:int = int(area.name.split("_")[1])
	point_reached.emit(i, area.get_parent());


func board_fall()->void:
	var t:= create_tween();
	t.tween_property(self, "v_offset", path.saw_offset.y, .5);
	t.parallel().tween_property(warning, "position:y", warning.position.y - path.saw_offset.y, .5)
	t.tween_callback(board_fall_camera_feedback);

func board_fall_camera_feedback()->void:
	const recoil = 100
	var origin:=camera_anchor.position
	camera_anchor.global_position.y -= recoil
	
	var t := create_tween();
	t.tween_property(camera_anchor, "position", origin, .15)


func _on_board_container_saw_left(saw: Saw) -> void:
	if saw.name == "trunk_bottom":
		board_fall();
	


func _on_point_reached(i: int, center:Node3D) -> void:
	var tpi:int = i - 2;
	if tpi < 0:return;
	var saw:Saw = center.get_node("Saw")
	if saw is XSaw:
		## follow's global position = container's gp
		var gap:float = abs(global_position.x - center.global_position.x)
		var t:Timer = Timer.new();
		t.wait_time = 1;
		t.timeout.connect(t.queue_free)
		add_child(t)
		
		while gap > 1 and not t.is_stopped():
			## surely this is consistent?
			await get_tree().process_frame
			gap = abs(global_position.x - center.global_position.x);
		global_position.x = center.global_position.x
		moving = false;
		saw.start_motion()
		await GLB.board_container.saw_left;
		moving = true
		
