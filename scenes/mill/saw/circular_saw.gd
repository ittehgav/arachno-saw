extends Saw
class_name CircularSaw





func _ready()->void:
	collision_shape.shape.radius = 150


func _on_area_entered(area: Area3D) -> void:
	if area is Fly:
		area.queue_free();
		if area.tp_target:
			area.tp_target.queue_free();
		return;
	super(area);
	const speed :float= BoardPathFollow.x_meters_per_second
	var shape:CollisionShape3D = area.get_node("CollisionShape3D2");
	var box:BoxShape3D = shape.shape;
	var length:float = box.size.x;
	play_sfx_loop(speed, length)
