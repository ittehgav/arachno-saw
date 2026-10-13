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



func _on_area_entered(area: Area3D) -> void:
	## AREA ENTERED = SAW COLLISION MASK
	## spider will collide with the saw with its mask and the saw's lay
	if area.get_parent().get_parent() is BoardContainer or area.get_parent() is StaticBody3D:
		miss_scan.queue_free();
		board_touched.emit();

func play_sfx_loop(speed: float, length: float) -> void:
	var total_time := length / speed
	var t0 := Time.get_ticks_msec()
	sfx_start.play()
	await sfx_start.finished
	sfx_loop.play()
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	await get_tree().create_timer(total_time - elapsed).timeout
	sfx_loop.stop()
	sfx_end.play()

func _on_area_exited(area: Area3D) -> void:
	if area.get_parent().get_parent() is BoardContainer:
		board_left.emit()



func _on_miss_check_area_entered(_area: Area3D) -> void:
	if not miss_shape_cast.is_colliding():
		GLB.board_container.saw_missed.emit(self);
