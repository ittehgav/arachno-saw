extends UIRoot;

@export var main_menu_camera:Camera3D
@export var mill_scene:PackedScene
@export var fade_out_rect:ColorRect

func _on_new_game_pressed() -> void:
	var t:= create_tween();
	t.tween_property(main_menu_camera, "position:z", main_menu_camera.position.z + 250, 5)
	await fade_in(fade_out_rect).finished
	var mill:Sawnmill = mill_scene.instantiate();
	get_parent().add_child(mill);
	await fade_out(fade_out_rect).finished;
	queue_free()
