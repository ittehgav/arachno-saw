extends Area3D
class_name Fly
@export var type:Type = Type.speed;
@export var animation:AnimationPlayer

## sfx nodes are not ASP3Ds because they play at full volume
## regardless of the spider position
@export var contact:AudioStreamPlayer;
@export var speed_sfx:AudioStreamPlayer;

@export var fly_body:MeshInstance3D

## only for TP fly
var tp_target:Fly
var tp_done:bool=false;

enum Type{
	speed,
	shield,
	teleport,
	coin,
	death
}
## ICONS
## will float and spin based on the same animationPlayer
## will have their own material setup
## will just not be visible when
## the fly is another type
@export var buff_icons:Dictionary[Type, Node3D];

@export var type_sfx:Dictionary[Type, AudioStreamPlayer];

const buff_colors:Dictionary[Type, Color] = {
	Type.speed: Color(0.0, 1.0, 0.0, 1.0),
	Type.shield: Color(0.41, 1.0, 1.0, 1.0),
	Type.teleport: Color(0.774, 0.41, 1.0, 1.0),
	Type.coin:Color(1.0, 1.0, 0.0, 1.0),
	Type.death: Color(1.0, 0.0, 0.0, 1.0)
}



func roll_type(current_types:Array[Type])->void:
	type = Type.values().pick_random();
	while type == Type.teleport and Type.teleport in current_types:
		type = Type.values().pick_random();

func _ready()->void:
	_setup();
	animation.play("enter")

func _setup()->void:
	fly_body.material_override.albedo_color = buff_colors[type];
	fly_body.material_override.emission = buff_colors[type]
	buff_icons[type].show()
	

func apply_effect(spider:Crawler)->void:
	contact.play()
	type_sfx[type].play();
	hide()

	animation.play("consume")
	match type:
		Type.speed:
			spider.bonus_speed = 100 * (1 + Run.current_fly_combo * .1)
			## creating it on spider so fly can queue free whenever
			if spider.speed_up_tween and spider.speed_up_tween.is_running():
				spider.speed_up_tween.kill()
			spider.speed_up_tween = spider.create_tween(); 
			spider.speed_up_tween.set_trans(Tween.TRANS_CUBIC)
			spider.speed_up_tween.tween_property(spider, "bonus_speed", 0, 5)
		Type.shield:
			GLB.spider.has_shield = true;
		Type.teleport:
			if not tp_done:
				tp_done = true;
				tp_target.tp_done = true
				await get_tree().physics_frame

				spider.global_position = tp_target.global_position
				
				tp_target.queue_free();
		#Type.coin: increases score, controlled via RunControl

		Type.death:
			spider.die(Crawler.DeathType.skull)
		
	set_monitorable.bind(false).call_deferred()
	await contact.finished;
	queue_free()
	
func clear()->void:
	tp_done = true ## to prevent frame perfect crash
	animation.play("clear")
	await animation.animation_finished;
	queue_free();
