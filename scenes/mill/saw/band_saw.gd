extends Saw

@export var band_material:StandardMaterial3D;

func _on_area_entered(area: Area3D) -> void:
	if area is Fly:
		area.queue_free();
		if area.tp_target:
			area.tp_target.queue_free();
		return;
	super(area);
	play_sfx_loop();
	
func _process(delta:float)->void:
	pass
