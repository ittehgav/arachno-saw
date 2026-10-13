extends Control


@export var score_label:Label;
## just leave an instance here 
## instead of having to track previous 
## score value some other way
var current_score:int;

func _ready()->void:
	Run.score_changed.connect(_on_run_score_changed)
	
	Run.fly_combo_started.connect(_on_fly_combo_started);
	Run.fly_combo_incremented.connect(_on_fly_combo_incremented);
	Run.fly_combo_ended.connect(_on_fly_combo_ended);
	

func _on_run_score_changed() -> void:
	score_label.text = str(int(Run.score))

@export var fly_combo_display:Control;
@export var fly_combo_label:Label;

@export var combo_increment_animation:AnimationPlayer;

@export var fly_mesh:MeshInstance3D;

@export var combo_timeout_bar:TextureProgressBar;



func _process(_delta: float) -> void:
	combo_timeout_bar.value = Run.fly_combo_timeout.time_left

func _on_fly_combo_started()->void:
	## combo incremented will emit on the same frame
	fly_combo_display.show();
	
	
func _on_fly_combo_incremented(type:Fly.Type)->void:
	print("cincre?")
	combo_increment_animation.play("combo_increment")
	update_combo_label();
	
	var fly_color:Color = Fly.buff_colors[type];

	var m:StandardMaterial3D = fly_mesh.material_override;
	combo_timeout_bar.tint_progress = fly_color - Color(0, 0, 0, .6)
	
	m.emission = fly_color;
	m.albedo_color = fly_color;
	print(fly_mesh.material_override.emission)

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
