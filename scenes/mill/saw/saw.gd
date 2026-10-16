extends Area3D
class_name Saw

@export var miss_scan:Area3D;

@export var sfx_start:AudioStreamPlayer3D;
@export var sfx_loop:AudioStreamPlayer3D;
@export var sfx_end:AudioStreamPlayer3D;


var board_x:int;

signal board_touched;
signal board_left;

@export var collision_shape:CollisionShape3D
@export var miss_shape_cast:ShapeCast3D

@export var camera:Camera3D;


func _on_area_entered(area: Area3D) -> void:
	## AREA ENTERED = SAW COLLISION MASK
	## spider will collide with the saw with its mask and the saw's lay
	if area.get_parent().get_parent() is BoardContainer or area.get_parent() is StaticBody3D:
		miss_scan.queue_free();
		board_touched.emit();

var looping:bool=false;
func play_sfx_loop() -> void:
	sfx_start.play()
	GLB.board_container.saw_left.connect(finish_sfx_loop)
	looping = true;
	await sfx_start.finished
	if looping:
		sfx_loop.play()


func finish_sfx_loop(_saw:Saw)->void:
	looping = false;
	sfx_loop.stop();
	sfx_start.stop();
	sfx_end.play()


func _on_area_exited(area: Area3D) -> void:
	if area.get_parent().get_parent() is BoardContainer:
		board_left.emit()



func _on_miss_check_area_entered(_area: Area3D) -> void:
	if not miss_shape_cast.is_colliding():
		GLB.board_container.saw_missed.emit(self);
