extends AudioStreamPlayer



func _ready()->void:
	Run.finished.connect(_on_run_finished);
	Run.get_node("accelerate").timeout.connect(accelerate_pitch)

func _on_run_finished(won:bool)->void:
	## these are single lifetime is ok
	if not won:
		var t:=create_tween();
		t.tween_property(self, "pitch_scale", .1, 4);
		t.tween_callback(stop)

func accelerate_pitch()->void:
	pitch_scale += .005


func _on_spider_run_won() -> void:
	stop()
