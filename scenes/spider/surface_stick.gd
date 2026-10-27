extends Node3D

@export var surface_check:RayCast3D;
@export var surface_finder:RayCast3D;
@export var spider:Crawler


func _on_stick_ticker_timeout() -> void:
	if not surface_check.is_colliding():
		print("notscis?")
		var board_gp:Vector3 = GLB.board_container.safe_board.global_position
		print(GLB.board_container.safe_board)
		print(spider.global_position, board_gp)
		
		surface_finder.global_position = spider.global_position
		surface_finder.look_at(board_gp);
		surface_finder.force_raycast_update();

		spider.global_position = surface_finder.get_collision_point();

		await get_tree().process_frame
		var t:Transform3D = spider.global_transform;
		t = t.looking_at(board_gp, Vector3.UP);
		
		var r:Vector3 = t.basis.get_euler() + Vector3(-PI/2.0, 0, 0);
		spider.rotation = r;
