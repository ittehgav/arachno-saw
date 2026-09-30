extends Area3D
class_name Saw
@export var particles_nx:CPUParticles3D;
@export var particles_px:CPUParticles3D;
## SAW:
## will VFX, split projections on boards

var board_x:int;

signal board_touched;
signal board_left;



func _on_area_entered(area: Area3D) -> void:
	var p:Node = area.get_parent()
	if p is BoardContainer:
		board_touched.emit();
		if p.global_position.x > global_position.x:
			board_x = 1;
		else:
			board_x = -1
		
func _on_area_exited(area: Area3D) -> void:
	if area.get_parent() is BoardContainer:
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
