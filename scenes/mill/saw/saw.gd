extends Area3D
class_name Saw

@export var miss_scan:Area3D;

@export var sfx_start:AudioStreamPlayer3D;
@export var sfx_loop:AudioStreamPlayer3D;
@export var sfx_end:AudioStreamPlayer3D;

@export var particles_nx:CPUParticles3D;
@export var particles_px:CPUParticles3D;
## SAW:
## will VFX, split projections on boards

var board_x:int;

signal board_touched;
signal board_left;

@export var collision_shape:CollisionShape3D

func _ready()->void:
	collision_shape.shape.radius = 150

func _on_area_entered(area: Area3D) -> void:
	## AREA ENTERED = SAW COLLISION MASK
	## spider will collide with the saw with its mask and the saw's lay
	var p:Node = area.get_parent().get_parent()
	if area.get_parent().get_parent() is BoardContainer or area.get_parent() is StaticBody3D:
		miss_scan.queue_free();
		## shape name that comes out of the duplicator tool script;
		## result of duplicating the cs2D before parenting it to the area
		## its fine 
		var shape:CollisionShape3D = area.get_node("CollisionShape3D2");
		
		var x_size:int = shape.shape.size.x
		start_sfx_loop(x_size)
		board_touched.emit();
		if p.global_position.x > global_position.x:
			board_x = 1;
		else:
			board_x = -1

@onready var start_duration:float = sfx_start.stream.get_length()
@onready var loop_duration:float = sfx_loop.stream.get_length()
@onready var end_duration:float = sfx_end.stream.get_length()
var loop_count:float;
func start_sfx_loop(board_size:float)->void:
	const speed = BoardPathFollow.x_meters_per_second as float;
	var target_length:= board_size/speed;
	var outer_duration:float = start_duration + end_duration
	var loop_time:float = target_length - outer_duration;
	loop_count= loop_time/loop_duration + 2;
	sfx_start.play();
	var wait:float = start_duration - .05
	await get_tree().create_timer(wait).timeout;
	play_sfx_loop();

func play_sfx_loop()->void:
	if loop_count > 1:
		var wait:float = loop_duration -.05
		sfx_loop.play();
		loop_count -= 1;
		await get_tree().create_timer(wait).timeout;
		play_sfx_loop();
	else:
		var wait:float = loop_duration * loop_count - .05;
		
		sfx_loop.play();
		await get_tree().create_timer(wait).timeout;
		sfx_loop.stop();
		sfx_end.play();


func _on_area_exited(area: Area3D) -> void:
	if area.get_parent().get_parent() is BoardContainer:
		board_left.emit()


func _on_board_touched() -> void:
	if board_x == 1:
		particles_px.emitting = true;
	else:
		particles_nx.emitting = true;

func _on_board_left() -> void:
	if board_x == 1:
		particles_px.emitting = false;
	else:
		particles_nx.emitting = false;


func _on_miss_check_area_entered(area: Area3D) -> void:
	GLB.board_container.saw_missed.emit(self);
