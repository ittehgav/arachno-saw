extends UIRoot
class_name InGameUI

@export var score_label:Label;
## just leave an instance here 
## instead of having to track previous 
## score value some other way
var current_score:int;
@export var hud:Control;
@export var post_run:PostRun

@export var black_fade:ColorRect

func _ready()->void:
	super()
	Run.score_changed.connect(_on_run_score_changed)
	
	Run.fly_combo_started.connect(_on_fly_combo_started);
	Run.fly_combo_incremented.connect(_on_fly_combo_incremented);
	Run.fly_combo_ended.connect(_on_fly_combo_ended);
	
var last_recorded_score:float;
func _on_run_score_changed() -> void:
	score_pop(Run.score - last_recorded_score)
	last_recorded_score = Run.score;
	
	score_label.text = str(int(last_recorded_score))

var current_pop_value:float;
func score_pop(change:float)->void:
	if change < 10:return;
	if change > current_pop_value:
		current_pop_value = change;
	var t:=create_tween();
	var s:float = pow(current_pop_value, 1.0/5.0);
	score_label.offset_transform_scale = Vector2(s, s)
	t.tween_property(score_label, "offset_transform_scale", Vector2.ONE, .5 )

@export var fly_combo_display:Control;
@export var fly_combo_label:Label;
@export var fly_rect:TextureRect

@export var combo_increment_animation:AnimationPlayer;

@export var fly_mesh:MeshInstance3D;

@export var combo_timeout_bar:TextureProgressBar;
@export var saw_pov:SubViewport

@export var fly_point_gain_label:Label;
@export var combo_multiplier_label:Label;

@export var you_died_screen:Control;
@export var you_died_message:Label
@export var you_died_continue_btn:Button

func _process(_delta: float) -> void:
	combo_timeout_bar.value = Run.fly_combo_timeout.time_left


func _on_spider_run_won() -> void:
	hud.hide();
	Run.finish_run(true);
	post_run.show_post_run(true)
	get_tree().paused = true

func _on_spider_died(source:Crawler.DeathType) -> void:
	hud.hide();
	Run.finish_run(false)
	const dt = Crawler.DeathType
	match source:
		dt.saw:
			you_died_message.text = "You needed to do one simple thing."
		dt.board:
			you_died_message.text = "Are you even trying?"
		dt.skull:
			you_died_message.text = "Don't you know what a skull means?"
		dt.roller:
			you_died_message.text = "The rollers are fully spider-proof."

	const death_pause_delay = .5
	Run._elapsed_time -= death_pause_delay;
	you_died_screen.modulate.a = 0;
	you_died_screen.show()

	var t:= create_tween();
	t.tween_property(you_died_screen, "modulate:a", 1, death_pause_delay);
	t.tween_callback(func()->void:get_tree().paused = true);
	t.tween_callback(you_died_continue_btn.show);



func _on_fly_combo_started()->void:
	## combo incremented will emit on the same frame
	fly_combo_display.show();
	
func _on_fly_combo_incremented(type:Fly.Type)->void:
	combo_increment_animation.play("combo_increment")
	update_combo_label();
	
	var fly_color:Color = Fly.buff_colors[type];
	fly_rect.modulate = fly_color;

	combo_timeout_bar.tint_progress = fly_color - Color(0, 0, 0, .6)
	

	fly_point_gain_label.modulate = fly_color;
	fly_point_gain_label.text = "+" + str(snapped(Run.fly_score_values[type] * Run.combo_multiplier, .01));
	
	combo_multiplier_label.text = "(*" + str(Run.combo_multiplier)+")"

func update_combo_label()->void:
	fly_combo_label.text = str(Run.current_fly_combo);
	
 
func _on_fly_combo_ended()->void:
	fly_combo_display.hide()

var score_tween:Tween;
func tween_score_label()->void:
	score_tween = create_tween();
	score_tween.tween_method(set_score_text, current_score, Run.current_score, .1);
	
func set_score_text(target:int)->void:
	score_label.text = str(target);


func _on_board_container_saw_touched(saw: Saw) -> void:
	if is_instance_valid(saw.camera):
		saw.camera.reparent(saw_pov)
		await get_tree().process_frame
		saw.camera.global_position = saw.global_position + Vector3(100, 700, 200);
		saw.camera.look_at(saw.global_position)


func _on_board_container_saw_left(_saw: Saw) -> void:
	saw_pov.get_node("saw_cam").queue_free()


func _on_continue_pressed() -> void:
	await fade_out(you_died_screen).finished;
	post_run.show_post_run(false)


	


func _on_play_again_pressed() -> void:
	await fade_in(black_fade).finished;
	var new_run:Sawmill = SceneIndex.sawmill_scene.instantiate();
	new_run.ready.connect(func()->void:get_tree().paused=false;new_run.gen.generate_level(), CONNECT_ONE_SHOT)
	
	GLB.sawmill.queue_free();
	get_tree().current_scene.add_child(new_run);
