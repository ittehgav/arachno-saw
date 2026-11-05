extends Area3D
class_name Saw


@export var sfx_start:AudioStreamPlayer3D;
@export var sfx_loop:AudioStreamPlayer3D;
@export var sfx_end:AudioStreamPlayer3D;


var board_x:int;

signal board_touched;
signal board_left;

@export var collision_shape:CollisionShape3D

@export var camera:Camera3D;

@export var particles_container:Node3D;

func set_particles_emitting(to:bool)->void:
	for c:Node in particles_container.get_children():
		c.emitting = to

func _on_area_entered(area: Area3D) -> void:
	## AREA ENTERED = SAW COLLISION MASK
	## spider will collide with the saw with its mask and the saw's lay
	if area.name == "roller_killbox":return;
	if area.get_parent().get_parent() is BoardContainer or area.get_parent() is StaticBody3D:
		board_touched.emit();
		set_particles_emitting(true)

var looping:bool=false;
const loop_wrap_offset = .03
func play_sfx_loop() -> void:
	sfx_start.play()
	GLB.board_container.saw_left.connect(finish_sfx_loop, CONNECT_ONE_SHOT);
	looping = true;
	await get_tree().create_timer(sfx_start.stream.get_length()-loop_wrap_offset).timeout
	if looping:
		saw_sfx_loop();

func saw_sfx_loop()->void:
	sfx_loop.play();
	await get_tree().create_timer(sfx_loop.stream.get_length()-loop_wrap_offset).timeout;
	if looping:
		saw_sfx_loop()


func finish_sfx_loop(_saw:Saw)->void:
	looping = false;
	sfx_loop.stop();
	sfx_start.stop();
	sfx_end.play()


func _on_area_exited(area: Area3D) -> void:
	if area.get_parent().get_parent() is BoardContainer:
		set_particles_emitting(false)
		
		board_left.emit()
