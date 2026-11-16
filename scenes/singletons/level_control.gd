extends Node
class_name Level;

signal level_transition_started;



func next_level(path:BodySplitPath)->void:
	path.set_process_mode(PROCESS_MODE_INHERIT)
	GLB.assign_new_level(path)
	path.start_stage()
	Run.current_stage += 1;

	
