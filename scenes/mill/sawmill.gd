extends Node3D
class_name Sawmill
## runs a generated track, tracks will encompass any variable that may turn dynamic
## for now just holding the class name and global hook
## same singleton treatment as Run?
@export var gen:NoiseSplitSequence;
@export var freeze_frame_timer:Timer;



func _ready() -> void:
	## declaring this on ready so i can free it with a liveinstance of the retry run
	GLB.sawmill =self;
	Run.start_run()
	


func _on_spider_fly_consumed(_fly: Fly) -> void:
	Engine.time_scale = 0;
	freeze_frame_timer.start()


func _on_freeze_frame_timeout() -> void:
	Engine.time_scale = 1;
