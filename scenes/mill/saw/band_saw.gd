extends Saw
class_name XSaw

@export var motion_animation:AnimationPlayer
@export var band_animation:AnimationPlayer

func _on_area_entered(area: Area3D) -> void:
	if area is Fly:
		area.queue_free();
		if area.tp_target:
			area.tp_target.queue_free();
		return;
	super(area);
	if area.name != "roller_killbox":
		play_sfx_loop();

func start_motion()->void:
	motion_animation.play("saw_motion");
	band_animation.play("band_spin")
