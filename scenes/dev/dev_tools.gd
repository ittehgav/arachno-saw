extends Node
class_name DevTools;

func _input(e:InputEvent)->void:
	if e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_1:
				move_pf_back();
			KEY_2:
				move_pf_forward();
			KEY_3:
				speed_up_run();

func move_pf_back()->void:
	if GLB.board_path_follow:
		GLB.board_path_follow.progress_ratio -= .05
func move_pf_forward()->void:
	if GLB.board_path_follow:
		GLB.board_path_follow.progress_ratio += .05
func speed_up_run()->void:
	Run._on_accelerate_timeout()
