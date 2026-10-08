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
			
