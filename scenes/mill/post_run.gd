extends Control
class_name PostRun


@export var result_label:Label;

@export var score_label:Label;
@export var time_label:Label;
@export var new_high_score_label:Label;



@export var fly_panel:PanelContainer
@export var fly_hboxes:Dictionary[Fly.Type, HBoxContainer]

@export var fly_consumed_sfx:AudioStreamPlayer;

@export var bgm:AudioStreamPlayer
@export var victory_sfx:AudioStreamPlayer


const ft = Fly.Type
func show_post_run(won:bool)->void:
	bgm.play()
	show()
	if won:
		victory_sfx.play();
		result_label.text = "VICTORY"
	if Run.score > HighScores.highest_score:
		if won:
			await victory_sfx.finished;
		victory_sfx.pitch_scale += 1;
		victory_sfx.play();
		var t:= create_tween();
		new_high_score_label.show()
		t.tween_property(new_high_score_label, "offset_transform_scale", Vector2(1.5, 1.5), .1)
		t.tween_property(new_high_score_label, "offset_transform_scale", Vector2.ONE, .5)
	

	time_label.text = _generate_time_string()
	_display_flies_consumed();
	
	score_label.text = str(int(Run.score));
	
	

func _generate_time_string()->String:
	var seconds:float = Run.get_elapsed_time();
	var minutes:int = 0;
	while seconds > 60:
		minutes += 1;
		seconds -= 60;
	var minutes_str:String="";
	if minutes < 10:
		minutes_str += "0";
	minutes_str += str(minutes);
	var seconds_str:String="";
	if seconds < 10:
		seconds_str += "0";
	
	seconds_str += str(int(seconds));
	var time_str:String = minutes_str+":" + seconds_str;
	return time_str


const fly_delay_step = .75;
func _display_flies_consumed()->void:
	await get_tree().create_timer(1).timeout;
	var fly_delay_acm := 0.0;
	for type:ft in Run.flies_consumed.keys():
		var fly_color:Color = Fly.buff_colors[type];
		
		if Run.flies_consumed[type]:
			fly_panel.show()
			var hbox := fly_hboxes[type]
			hbox.get_node("amount").text = str(Run.flies_consumed[type])
			hbox.modulate = fly_color
			var t:= create_tween()
			t.tween_interval(fly_delay_acm);
			t.tween_callback(_highlight_fly_type.bind(hbox))
		
			t.tween_property(hbox, "offset_transform_scale", Vector2.ONE, .25)
			
			fly_delay_acm += fly_delay_step;

func _highlight_fly_type(hbox:HBoxContainer)->void:
	hbox.show()
	hbox.offset_transform_scale = Vector2(2, 2)
	fly_consumed_sfx.play()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_packed(SceneIndex.main)


func _on_poll_pressed() -> void:
	OS.shell_open("https://forms.gle/tR23SfhZVi5JiuDR7")
