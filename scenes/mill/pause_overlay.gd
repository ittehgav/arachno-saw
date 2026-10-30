extends Control

signal game_paused;
signal game_unpaused

@export var pause_btn:Button;

@export var pause_sfx:AudioStreamPlayer
@export var unpause_sfx:AudioStreamPlayer

func _ready()->void:
	## clean condition to keep it from catching pause on 
	Run.finished.connect(_on_run_finished)

func _input(e:InputEvent)->void:
	if e.is_action_pressed("pause"):
		toggle_pause();
	
func toggle_pause()->void:
	UIRoot.press_grow(pause_btn, 1.5)
	
	if get_tree().paused:
		## unpause
		get_tree().paused = false;
		unpause_sfx.play()
		game_unpaused.emit()
		hide()

	else:
		## pause
		get_tree().paused = true;
		pause_sfx.play();
		game_paused.emit()
		show()



func _on_run_finished(_won:bool)->void:
	queue_free()


func _on_pause_pressed() -> void:
	toggle_pause();
