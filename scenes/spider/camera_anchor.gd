extends Node3D
class_name CrawlerFollower

@export var crawler:Crawler;
@export var pcam:PhantomCamera3D;



@export var you_died_screen:Control;
@export var you_died_message:Label
func _on_spider_died(source:Crawler.DeathType) -> void:
	const dt = Crawler.DeathType
	pcam.follow_mode = PhantomCamera3D.FollowMode.NONE;
	pcam.look_at_mode = PhantomCamera3D.LookAtMode.NONE;
	
	match source:
		dt.saw:
			you_died_message.text = "Avoid touching the saws."
		dt.board:
			you_died_message.text = "Boards always fall spider-side-down."
		dt.skull:
			you_died_message.text = "Don't you know what a skull means?"


	you_died_screen.modulate.a = 0;
	you_died_screen.show()
	var t:= create_tween();
	t.tween_property(you_died_screen, "modulate:a", 1, 1);
	t.parallel().tween_property(pcam, "fov", pcam.fov + 30, 1)
