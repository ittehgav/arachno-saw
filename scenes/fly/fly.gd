extends Area3D
class_name Fly
@export var type:Type = Type.speed;
@export var consume_animation:AnimationPlayer

## sfx nodes are not ASP3Ds because they play at full volume
## regardless of the spider position
@export var contact:AudioStreamPlayer;
@export var speed_sfx:AudioStreamPlayer;

enum Type{
	speed,
	shield,
	teleport
}
const buff_colors:Dictionary[Type, Color] = {
	Type.speed: Color(1.0, 1.0, 0.0, 1.0),
	Type.shield: Color(0.41, 1.0, 1.0, 1.0),
	Type.teleport: Color(0.774, 0.41, 1.0, 1.0)
}


func apply_effect(spider:Crawler)->void:
	contact.play()
	consume_animation.play("consume")
	match type:
		Type.speed:
			speed_sfx.play()
			spider.bonus_speed = 100
			monitorable = false;
			var t:= create_tween();
			t.set_trans(Tween.TRANS_CUBIC)
			t.tween_property(spider, "bonus_speed", 0, 5)
			t.tween_callback(queue_free);
			
