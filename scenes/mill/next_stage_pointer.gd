extends Control

@export var pcam:PhantomCamera3D;
@export var cam:Camera3D;

@export var ticker:Timer;

@export var top_pointer:Control;
@export var right_pointer:Control
@export var bottom_pointer:Control;
@export var left_pointer:Control;

var target:Vector3;
const center_deadzone = .3
func update_target_pointers() -> void:
	var viewport_size := get_viewport().get_visible_rect().size


	var center := viewport_size * 0.5

	# Hide everything by default.
	top_pointer.hide()
	right_pointer.hide()
	bottom_pointer.hide()
	left_pointer.hide()

	if cam.is_position_behind(target):
		var basis := cam.global_transform.basis
		var to_target := (target - cam.global_position).normalized()

		# Always point down when behind.
		bottom_pointer.show()

		# Compare the angle to the camera's left/right directions.
		var right_dot := to_target.dot(basis.x)
		var left_dot := -right_dot

		if abs(right_dot) > 0.05:
			if right_dot > 0.0:
				right_pointer.show()
			else:
				left_pointer.show()

		return

	var screen_pos := cam.unproject_position(target)
	var offset := (screen_pos - center) / center

	if offset.length() < center_deadzone:
		return

	top_pointer.visible = offset.y < -center_deadzone
	bottom_pointer.visible = offset.y > center_deadzone
	right_pointer.visible = offset.x > center_deadzone
	left_pointer.visible = offset.x < -center_deadzone


func _on_board_path_follow_point_reached(_i: int, area: Area3D) -> void:
	var path:BodySplitPath;
	
	if area.name == "final_point":
		var p:Node = get_parent();
		while not p is BodySplitPath:
			p = p.get_parent();
		path = p;
		if path.is_ancestor_of(GLB.spider):
			var next_path:BodySplitPath = GLB.next_path;
			target = next_path.global_position
			show()
			ticker.start()
			await next_path.stage_started;
			hide();
			ticker.stop()




func _on_ticker_timeout() -> void:
	update_target_pointers()
	


func _on_spider_web_hit() -> void:
	hide()
