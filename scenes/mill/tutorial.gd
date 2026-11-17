extends Control

@export var movement_instructions:VBoxContainer;
@export var dont_die_instruction:Label
@export var rmb_instruction:Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await GLB.board_container.saw_touched;
	UIRoot.fade_out(movement_instructions);
	var t:= UIRoot.fade_in(dont_die_instruction)
	var fs:int = dont_die_instruction.get_theme_font_size("font_size");
	t.parallel().tween_property(dont_die_instruction, "theme_override_font_sizes/font_size", fs * 1.25, .2 )
	t.parallel().tween_property(dont_die_instruction, "theme_override_font_sizes/font_size", fs, 1 )
	await t.finished;
	UIRoot.fade_out(dont_die_instruction, 10)
	

var m2_instruction_cleared:bool=false;
func _on_board_path_follow_point_reached(_i: int, split_center: Node3D) -> void:
	if split_center.name == "final_point" and not m2_instruction_cleared:
		m2_instruction_cleared = true;
		rmb_instruction.show();
		var cc:CameraControl = GLB.spider.get_node("camera_control")
		await cc.started_aiming;
		rmb_instruction.hide()
		var path:BodySplitPath = GLB.board_path_follow.get_parent();
		## ugly bad referencing will probably case trouble in the future and i deser it
		var next_path:BodySplitPath = path.get_parent().get_node("path_02")
		cc.pcam.look_at(next_path.global_position)
		print(len(GLB.board_path_follow.point_reached.get_connections()))
		GLB.board_path_follow.point_reached.disconnect(_on_board_path_follow_point_reached)
		print(len(GLB.board_path_follow.point_reached.get_connections()))
