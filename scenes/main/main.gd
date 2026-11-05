extends Node3D
## design doc or something?
## COLLISION LAYERS/MASKS:
## 1: spider - killboxes - flies
## 2: saw - board collision
## 3: saw - miss check
## 4: path - turn scan
## 5: boards - fly spawner detection
## 6: camera region control
## 7: spider roller warnin area3Ds

## DIFFICULTY THINGS THAT CAN SCALE
## skull fly spawn rate
## board movement speed
## spider movement speed

@export var main_menu_spider:Crawler;

func _ready()->void:
	main_menu_spider.set_physics_process(false);
	main_menu_spider.body.set_physics_process(false)
	main_menu_spider.body.animation.speed_scale = 1
	
