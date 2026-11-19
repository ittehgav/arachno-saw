extends "res://scenes/spider/crawler_movement.gd"
class_name Crawler;

signal fly_consumed(fly:Fly)
signal died(source:DeathType)
signal shield_lost;

signal run_won;

enum DeathType{
	saw,
	board,
	skull,
	roller
}
@export var pcam:PhantomCamera3D

@export var body:Spider

@export var death_sfx:AudioStreamPlayer

@export var blink_animation:AnimationPlayer;
@export var cheat_death_sfx:AudioStreamPlayer;

@export var buff_glow_mesh:MeshInstance3D
@export var buff_glow_animation:AnimationPlayer

var moving:bool=false;
## bc board deaths can be async and on drop board i need to know
## its alive in order to win the run
var dead:bool=false;

var has_shield:bool=false;




func _ready()->void:
	GLB.spider = self;

func teleport_to(t:Transform3D)->void:
	disable_movement();
	global_transform = t;
	await get_tree().physics_frame;
	await get_tree().physics_frame;
	enable_movement()



## not claude
## some stuff goes here so the signals become less scattered
const shaking_amp = 5;
func _on_board_container_saw_touched(_saw: Saw) -> void:
	pcam.noise.amplitude = shaking_amp
	pcam.noise.frequency = 50 ## editor thingy only goes to 10 

func _on_board_container_saw_left(_saw: Saw) -> void:
	pcam.noise.amplitude = 0;


func win_run()->void:
	run_won.emit();

func board_death(board:StaticBody3D)->void:
	## easier than to keep the board var around until
	## death prevention is checked
	if not has_shield: 
		reparent(board);
		set_physics_process(false)
	die(DeathType.board)

func _on_collision_scan_area_entered(area: Area3D) -> void:
	if area is Saw:
		die(DeathType.saw);
	elif area is Fly:
		fly_consumed.emit(area)
		area.apply_effect(self)
	elif area.name == "roller_killbox":
		## would need to add a script to roller killbox just
		## for the classname otherwise
		die(DeathType.roller)

var invulnerable:bool=false;
func die(source:DeathType)->void:
	if has_shield:
		has_shield = false;
		cheat_death(source)
		shield_lost.emit()
		return;
	set_physics_process(false)
	death_sfx.play()
	dead = true;
	died.emit(source)

func cheat_death(type:DeathType)->void:
	cheat_death_sfx.play()
	blink_animation.play("blink");
	match type:
		DeathType.saw, DeathType.board, DeathType.roller:
			tp_to_safety()

func tp_to_safety()->void:
	await get_tree().physics_frame 
	## when boards drop, takes a frame 
	## for safe region detectors to refgresy
	var safe:Node3D = GLB.board_container.safe_board.get_node("safe");
	var t:Transform3D = safe.global_transform;
	set_physics_process(false);
	global_transform = t;
	await get_tree().physics_frame;
	await get_tree().process_frame;
	set_physics_process(true);


@onready var body_scale: = body.scale
func _on_fly_consumed(fly: Fly) -> void:
	if fly.type == Fly.Type.death:return;
	## should never overlap animations?
	body.scale *= 1.25;
	var t:= create_tween();
	t.tween_property(body, "scale", body_scale, .5)

	var m:StandardMaterial3D = buff_glow_mesh.mesh.material;
	var color:Color = Fly.buff_colors[fly.type];
	m.albedo_color = color
	m.emission = color;
	buff_glow_animation.play("buff_glow")
