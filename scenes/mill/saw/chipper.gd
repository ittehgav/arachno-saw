extends Area3D
class_name Chipper

@export var sfx:AudioStreamPlayer3D;

var sfx_looping:bool:
	set(val):
		if val:
			sfx_loop();
		sfx_looping = val;
func _on_area_entered(area: Area3D) -> void:
	if area is Fly:
		area.queue_free();
		return;
	if area.name == "roller_killbox":return;
	sfx_looping = true;
func _on_area_exited(area: Area3D) -> void:
	if area.name == "roller_killbox" or area is Fly:return;
	sfx_looping = false;

func sfx_loop()->void:
	sfx.play();
	await get_tree().create_timer(randf_range(.25, .4)).timeout;
	if sfx_looping:
		sfx_loop();
