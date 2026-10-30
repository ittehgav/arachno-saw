extends UIRoot;

@export var main_menu_camera:Camera3D
@export var fade_out_rect:ColorRect

@export var high_scores:VBoxContainer;
@export var loader:AssetPreloader;
@export var preload_overlay:ColorRect;

@export var clear_high_scores_confirmation:Control;



func _ready()->void:
	super()
	if len(HighScores.current_high_scores):
		high_scores.show()
		refresh_high_scores();
	HighScores.highscores_changed.connect(refresh_high_scores)
	await loader.finished;
	fade_out(preload_overlay)

func _on_new_game_pressed() -> void:
	var t:= create_tween();
	t.tween_property(main_menu_camera, "position:z", main_menu_camera.position.z + 250, 5)
	await fade_in(fade_out_rect).finished
	var mill:Sawmill = SceneIndex.sawmill_scene.instantiate();
	mill.ready.connect(mill.gen.generate_level, CONNECT_ONE_SHOT)
	get_parent().add_child(mill);
	await fade_out(self).finished;
	queue_free()
	
func refresh_high_scores()->void:
	for c:Node in high_scores.get_children():
		if c is Label:
			c.queue_free();

	for e:Dictionary in HighScores.current_high_scores:
		var h:= HBoxContainer.new();
		
		var name_label:= Label.new();
		name_label.text = e.name + ": ";
		name_label.add_theme_font_size_override("font_size", 32)
		h.add_child(name_label);
		
		var score_label:=Label.new();
		score_label.text = str(e.score);
		score_label.add_theme_font_size_override("font_size", 48)
		h.add_child(score_label)
		high_scores.add_child(h)



func _on_clear_pressed() -> void:
	fade_in(clear_high_scores_confirmation)


func _on_confirm_pressed() -> void:
	HighScores.clear_record();
	fade_out(clear_high_scores_confirmation);
	high_scores.hide();

func _on_cancel_pressed() -> void:
	fade_out(clear_high_scores_confirmation)
