extends Saw
class_name CircularSaw


@export var particles_nx:CPUParticles3D;
@export var particles_px:CPUParticles3D;

func _ready()->void:
	collision_shape.shape.radius = 150


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
