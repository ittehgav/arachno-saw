extends Node3D



@export var surface_check:RayCast3D;
@export var surface_finder:RayCast3D;
@export var spider:Crawler
@export var ticker:Timer;

func _on_stick_ticker_timeout() -> void:
	if not surface_check.is_colliding():
		spider.tp_to_safety()


func _on_spider_movement_disabled() -> void:
	ticker.stop()

func _on_spider_movement_enabled() -> void:
	ticker.start()
