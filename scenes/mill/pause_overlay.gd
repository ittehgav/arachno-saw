extends Control

signal game_paused;
signal game_unpaused

@export var pause_sfx:AudioStreamPlayer
@export var unpause_sfx:AudioStreamPlayer

func _ready()->void:
	## clean condition to keep it from catching pause on 
	Run.finished.connect(_on_run_finished)

func _input(e:InputEvent)->void:
	if e.is_action_pressed("pause"):
		if get_tree().paused:
			get_tree().paused = false;
			unpause_sfx.play()
			game_unpaused.emit()
			hide()
		else:
			get_tree().paused = true;
			pause_sfx.play();
			game_paused.emit()
			show()
func _on_run_finished(_won:bool)->void:
	queue_free()
