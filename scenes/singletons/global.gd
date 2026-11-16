extends Node

var spider:Crawler;
var sawmill:Sawmill

var current_path:BodySplitPath;


var next_path:BodySplitPath:
	get():
		if current_path.name == "path":
			return current_path.get_parent().get_node("path_02")
		else:
			var n:int = int(current_path.name.split("_")[1])
			var nstr:String = "";
			if n < 9:
				nstr += "0";
			nstr += str(n+1)
			return current_path.get_parent().get_node("path_"+nstr);

var board_container:BoardContainer;
var board_path_follow:BoardPathFollow;

func assign_new_level(path:BodySplitPath)->void:
	current_path = path
	recursive_check_assign(path)
	

func recursive_check_assign(target:Node)->void:
	if target is BoardPathFollow:
		target.accel = board_path_follow.accel;
		board_path_follow = target;
		target.moving = true
	if target is BoardContainer:
		board_container = target

	for c in target.get_children():
		recursive_check_assign(c)
