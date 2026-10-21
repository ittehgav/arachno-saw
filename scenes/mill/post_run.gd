extends Control
class_name PostRun

@export var result_label:Label;

@export var score_label:Label;
@export var time_label:Label;

@export var fly_hboxes:Dictionary[Fly.Type, HBoxContainer]

@export var fly_consumed_sfx:AudioStreamPlayer;

const ft = Fly.Type
func show_post_run()->void:
	show()
	
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
	time_label.text = time_str
	
	score_label.text = str(int(Run.score));
	
	var fly_delay_acm := 0.0;
	for type:ft in Run.flies_cosumed.keys():
		var fly_color:Color = Fly.buff_colors[type];
		
		if Run.flies_cosumed[type]:
			var hbox := fly_hboxes[type]
			hbox.modulate = fly_color
			var t:= create_tween()
			t.tween_interval(fly_delay_acm);
			t.tween_callback(_highlight_fly_type.bind(hbox))
		
			t.tween_property(hbox, "offset_transform_scale", Vector2.ONE, .25)
			
			fly_delay_acm += .5;


func _highlight_fly_type(hbox:HBoxContainer)->void:
	hbox.show()
	hbox.offset_transform_scale = Vector2(2, 2)
	fly_consumed_sfx.play()
