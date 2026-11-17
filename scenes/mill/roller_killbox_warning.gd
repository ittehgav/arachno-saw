extends MeshInstance3D

@export var refresh_ticker:Timer;
@export var roller_line:Node3D
var nearby_rollers:Array[RollerLine];

var current_playing:Array[AnimationPlayer]

const roller_spacing = 450;
var roller_origin:float = 0;
var active:bool=false;


func refresh_rollers()->void:
	if not roller_origin:
		roller_origin = roller_line.get_child(0).global_position.x;
	var rn:int = int(position.x/roller_spacing)
	
	var rollers:Array[RollerLine] = []
	for i:int in range(-1, 2):
		var ri:int = rn + i;
		var n:Node = roller_line.get_child(ri)
		if n:
			assert(n is RollerLine)
			rollers.append(n);
	
	for r:RollerLine in nearby_rollers:
		if r not in rollers:
			set_playing(r, false);
			nearby_rollers.erase(r);
	
	for r:RollerLine in rollers:
		if r not in nearby_rollers:
			set_playing(r, true);
			nearby_rollers.append(r)
	
func set_playing(r:RollerLine, to:bool)->void:
	var a:AnimationPlayer = r.warning_animation
	if to:
		if a not in current_playing:
			current_playing.append(a);
			a.play("warning")
	else:
		if a in current_playing:
			current_playing.erase(a);
			a.play("RESET")
	
func _physics_process(_delta: float) -> void:
	global_position.x = GLB.spider.global_position.x


func _on_warning_region_body_entered(body: Node3D) -> void:
	assert(body is Crawler)
	refresh_rollers();
	refresh_ticker.start()
	active = true;


func _on_warning_region_body_exited(body: Node3D) -> void:
	assert(body is Crawler)
	active = false;
	refresh_ticker.stop()
	clear_animations();

func clear_animations()->void:
	for a:AnimationPlayer in current_playing:
		a.play("RESET")
	current_playing = []


func _on_refresh_rollers_ticker_timeout() -> void:
	refresh_rollers()
