extends Saw
class_name CircularSaw








func _on_area_entered(area: Area3D) -> void:
	if area is Fly:
		area.queue_free();
		if area.tp_target:
			area.tp_target.queue_free();
		return;
	super(area);
	if area.name != "roller_killbox":
		play_sfx_loop()
